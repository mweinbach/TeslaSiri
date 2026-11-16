import Foundation

extension TeslascopeClient {
    public func drives(
        vin: String, limit: Int, from: Date? = nil, to: Date? = nil, tag: String? = nil,
        requireCompleteRows: Bool = false
    ) async throws -> [FleetDriveInfo] {
        let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await activity(vin: vin, kind: "drive", limit: limit, from: from, to: to,
                                  requireCompleteRows: requireCompleteRows) { row in
            guard let drive = row.drive(vin: vin) else { throw FleetKitError.badResponse }
            if let tag, !tag.isEmpty, drive.tag?.caseInsensitiveCompare(tag) != .orderedSame {
                return nil
            }
            return drive
        }
    }

    public func charges(
        vin: String, limit: Int, from: Date? = nil, to: Date? = nil,
        requireCompleteRows: Bool = false
    ) async throws -> [FleetChargeInfo] {
        try await activity(vin: vin, kind: "charge", limit: limit, from: from, to: to,
                           requireCompleteRows: requireCompleteRows) { row in
            guard let charge = row.charge(vin: vin) else { throw FleetKitError.badResponse }
            return charge
        }
    }

    // The activity feed documents newest-first ordering and date bounds. The separate
    // /drives and /charges paginators do not guarantee either.
    private func activity<Result>(
        vin: String, kind: String, limit: Int, from: Date?, to: Date?, requireCompleteRows: Bool,
        transform: (TeslascopeSession) throws -> Result?
    ) async throws -> [Result] {
        guard limit > 0 else { return [] }
        let publicID = try await publicID(vin: vin)
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 20), 100)))]
        if let from { query.append(URLQueryItem(name: "start_at", value: from.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))) }
        if let to { query.append(URLQueryItem(name: "end_at", value: to.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))) }
        var page = 1
        var result: [Result] = []
        var seen: Set<Int> = []
        while result.count < limit {
            try Task.checkCancellation()
            let data = try await request(["vehicle", publicID, "activity"],
                                         query: query + [URLQueryItem(name: "page", value: String(page))])
            let batch = try JSONDecoder().decode(TeslascopeEnvelope<ActivityPage>.self, from: data).response
            guard batch.current_page == page else { throw FleetKitError.badResponse }
            for activity in batch.data where activity.type == kind {
                let row = kind == "drive" ? activity.drive : activity.charge
                guard let row, let id = row.id, id > 0, let started = row.start else {
                    if requireCompleteRows { throw FleetKitError.badResponse }
                    continue
                }
                guard seen.insert(id).inserted else {
                    if requireCompleteRows { throw FleetKitError.badResponse }
                    continue
                }
                if let from, started < from { continue }
                if let to, started > to { continue }
                if let item = try transform(row) { result.append(item) }
                if result.count == limit { break }
            }
            guard batch.next_page_url != nil else { break }
            guard !batch.data.isEmpty else { throw FleetKitError.badResponse }
            // Keep the original authorized host and vehicle path on every page.
            page += 1
        }
        return result
    }

    public func drive(vin: String, sessionID: String) async throws -> FleetDriveInfo {
        let row = try await session(vin: vin, sessionID: sessionID, kind: "drive")
        guard let drive = row.drive(vin: vin) else { throw FleetKitError.badResponse }
        return drive
    }

    public func charge(vin: String, sessionID: String) async throws -> FleetChargeInfo {
        let row = try await session(vin: vin, sessionID: sessionID, kind: "charge")
        guard let charge = row.charge(vin: vin) else { throw FleetKitError.badResponse }
        return charge
    }

    private func session(vin: String, sessionID: String, kind: String) async throws -> TeslascopeSession {
        let prefix = "\(vin):teslascope:"
        guard sessionID.hasPrefix(prefix), let id = Int(sessionID.dropFirst(prefix.count)), id > 0 else {
            throw FleetKitError.badResponse
        }
        let publicID = try await publicID(vin: vin)
        let data = try await request(["vehicle", publicID, kind, String(id)])
        let row = try JSONDecoder().decode(TeslascopeEnvelope<TeslascopeSession>.self, from: data).response
        guard row.id == id else { throw FleetKitError.badResponse }
        return row
    }

    public func driveTelemetry(vin: String, sessionID: String) async throws -> [TeslascopeDriveSample] {
        let row = try await session(vin: vin, sessionID: sessionID, kind: "drive")
        return row.progress.sorted { ($0.timestampMS ?? 0) < ($1.timestampMS ?? 0) }
    }

    public func drivePath(vin: String, sessionID: String, maxPoints: Int = 72) async throws -> [FleetDriveRoutePoint] {
        let samples = try await driveTelemetry(vin: vin, sessionID: sessionID)
        return sampleRoute(samples.compactMap(\.routePoint), maxPoints: maxPoints)
    }

    public func drivePath(vin: String, from: Date, to: Date, maxPoints: Int = 72) async throws -> [FleetDriveRoutePoint] {
        guard to >= from else { return [] }
        let rows = try await drives(vin: vin, limit: 2, from: from, to: from)
        guard rows.count == 1, let row = rows.first else { return [] }
        let samples = try await driveTelemetry(vin: vin, sessionID: row.id)
        let window = from.timeIntervalSince1970 * 1000 ... to.timeIntervalSince1970 * 1000
        let points = samples.compactMap(\.routePoint).filter { point in
            point.timestampMS.map { window.contains(Double($0)) } == true
        }
        return sampleRoute(points, maxPoints: maxPoints)
    }

    private func sampleRoute(_ points: [FleetDriveRoutePoint], maxPoints: Int) -> [FleetDriveRoutePoint] {
        guard maxPoints > 1, points.count > maxPoints else { return points }
        return (0..<maxPoints).map { points[$0 * (points.count - 1) / (maxPoints - 1)] }
    }

    public func releaseNotes(
        vin: String, version: String, staged: Bool? = nil
    ) async throws -> [FleetReleaseNoteInfo] {
        let version = version.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard !version.isEmpty, version != ".", version != "..", !version.contains("/") else {
            throw FleetKitError.badResponse
        }
        var vehicleNotesAreStaged = staged
        if vehicleNotesAreStaged == nil {
            let data = try await stateData(vin: vin)
            let state = try FleetIntentClient.spotlightState(data, tires: nil, vin: vin).1
            if version == state.availableVersion { vehicleNotesAreStaged = true }
            else if version == state.currentVersion { vehicleNotesAreStaged = false }
        }
        if let staged = vehicleNotesAreStaged {
            let publicID = try await publicID(vin: vin)
            do {
                let path = staged ? "staged-release-notes" : "release-notes"
                let data = try await request(["vehicle", publicID, path])
                let notes = try JSONDecoder().decode(TeslascopeEnvelope<VehicleNotes>.self, from: data).response
                let returnedVersion = staged ? notes.staged_version : notes.deployed_version
                if returnedVersion == nil || returnedVersion == version { return notes.release_notes }
            } catch FleetKitError.api { /* The pass-through may require a different subscription. */ }
            catch is DecodingError { /* Use the version catalog if the pass-through format is unavailable. */ }
        }

        let data = try await request(["software", version])
        let release = try JSONDecoder().decode(TeslascopeEnvelope<SoftwareRelease>.self, from: data).response
        guard release.version == version else { throw FleetKitError.badResponse }
        return release.features.compactMap { feature in
            switch feature {
            case .title(let title) where !title.isEmpty:
                return FleetReleaseNoteInfo(title: title, customerVersion: version)
            case .note(let note) where !note.title.isEmpty:
                return FleetReleaseNoteInfo(title: note.title, subtitle: note.subtitle, details: note.details,
                                            customerVersion: note.customerVersion ?? version)
            default: return nil
            }
        }
    }
}

private struct ActivityPage: Decodable {
    let current_page: Int
    let next_page_url: String?
    let data: [Activity]

    struct Activity: Decodable {
        let type: String
        let drive: TeslascopeSession?
        let charge: TeslascopeSession?
    }
}

private struct VehicleNotes: Decodable {
    let release_notes: [FleetReleaseNoteInfo]
    let deployed_version, staged_version: String?

    init(from decoder: Decoder) throws {
        enum Keys: String, CodingKey { case response, release_notes, deployed_version, staged_version }
        let outer = try decoder.container(keyedBy: Keys.self)
        let fields = outer.contains(.response) ? try outer.nestedContainer(keyedBy: Keys.self, forKey: .response) : outer
        release_notes = try fields.decode([FleetReleaseNoteInfo].self, forKey: .release_notes).filter { !$0.title.isEmpty }
        deployed_version = try fields.decodeIfPresent(String.self, forKey: .deployed_version)
        staged_version = try fields.decodeIfPresent(String.self, forKey: .staged_version)
    }
}

private struct SoftwareRelease: Decodable {
    let version: String
    let features: [Feature]

    enum Feature: Decodable {
        case title(String)
        case note(FleetReleaseNoteInfo)
        case restricted

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let title = try? container.decode(String.self) {
                self = .title(title)
            } else {
                enum Keys: String, CodingKey { case car_types, countries }
                let fields = try decoder.container(keyedBy: Keys.self)
                let models = try fields.decodeIfPresent([String].self, forKey: .car_types) ?? []
                let countries = try fields.decodeIfPresent([String].self, forKey: .countries) ?? []
                self = models.isEmpty && countries.isEmpty ? .note(try container.decode(FleetReleaseNoteInfo.self)) : .restricted
            }
        }
    }
}

private struct TeslascopeSession: Decodable {
    enum Key: String, CodingKey {
        case id, created_at, duration, distance, avg_speed, type, battery_level_start, battery_level_end
        case battery_range_start, battery_range_end, latitude_start, longitude_start, latitude_end, longitude_end
        case charge_energy_added, fast_charger_type, latitude, longitude, odometer, cost, currency, name, progress
    }

    let id: Int?
    let start: Date?
    let durationMS: Int64?
    let distanceMiles, averageSpeed, startRange, endRange: Double?
    let startBattery, endBattery: Int?
    let startLat, startLon, endLat, endLon: Double?
    let tag: String?
    let energyAdded, latitude, longitude, odometer, cost: Double?
    let currency, name, chargerType: String?
    let progress: [TeslascopeDriveSample]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        start = try c.decodeIfPresent(String.self, forKey: .created_at).flatMap(historyDate)
        durationMS = c.flexibleDouble(.duration).flatMap { $0 >= 0 ? Int64(exactly: ($0 * 1000).rounded()) : nil }
        distanceMiles = c.flexibleDouble(.distance)
        averageSpeed = c.flexibleDouble(.avg_speed)
        startBattery = c.flexibleDouble(.battery_level_start).flatMap(Int.init(exactly:))
        endBattery = c.flexibleDouble(.battery_level_end).flatMap(Int.init(exactly:))
        startRange = c.flexibleDouble(.battery_range_start)
        endRange = c.flexibleDouble(.battery_range_end)
        startLat = c.flexibleDouble(.latitude_start)
        startLon = c.flexibleDouble(.longitude_start)
        endLat = c.flexibleDouble(.latitude_end)
        endLon = c.flexibleDouble(.longitude_end)
        tag = try c.decodeIfPresent(String.self, forKey: .type)
        energyAdded = c.flexibleDouble(.charge_energy_added)
        latitude = c.flexibleDouble(.latitude)
        longitude = c.flexibleDouble(.longitude)
        odometer = c.flexibleDouble(.odometer)
        cost = c.flexibleDouble(.cost)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)?.uppercased()
        name = try c.decodeIfPresent(String.self, forKey: .name)
        chargerType = try c.decodeIfPresent(String.self, forKey: .fast_charger_type)
        progress = try c.decodeIfPresent([TeslascopeDriveSample].self, forKey: .progress) ?? []
    }

    private var startMS: Int64? { start.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } }
    // updated_at is a record modification time and can be months after a completed charge.
    private var endMS: Int64? {
        guard let startMS, let durationMS else { return nil }
        let sum = startMS.addingReportingOverflow(durationMS)
        return sum.overflow ? nil : sum.partialValue
    }

    func drive(vin: String) -> FleetDriveInfo? {
        guard let id, let startMS else { return nil }
        return FleetDriveInfo(
            sessionID: "\(vin):teslascope:\(id)", vin: vin, distanceMiles: distanceMiles,
            durationMS: durationMS, avgSpeedMPH: averageSpeed, maxSpeedMPH: progress.compactMap(\.speedMPH).max(),
            energyUsedKWH: nil, startedAt: startMS, endedAt: endMS, startAddress: nil, endAddress: nil,
            startLatitude: startLat, startLongitude: startLon, endLatitude: endLat, endLongitude: endLon,
            startingBatteryPercent: startBattery, endingBatteryPercent: endBattery,
            ratedRangeUsedMiles: startRange.flatMap { start in endRange.map { max(0, start - $0) } }, tag: tag
        )
    }

    func charge(vin: String) -> FleetChargeInfo? {
        guard let id, let startMS else { return nil }
        return FleetChargeInfo(
            sessionID: "\(vin):teslascope:\(id)", vin: vin, startedAt: startMS, endedAt: endMS,
            location: name, latitude: latitude, longitude: longitude,
            isSupercharger: chargerType?.caseInsensitiveCompare("Tesla") == .orderedSame,
            odometerMiles: odometer, energyAddedKWH: energyAdded,
            milesAdded: startRange.flatMap { start in endRange.map { max(0, $0 - start) } },
            startingBatteryPercent: startBattery, endingBatteryPercent: endBattery, cost: cost, currency: currency
        )
    }
}

public struct TeslascopeDriveSample: Decodable, Sendable {
    private enum Key: String, CodingKey {
        case created_at, latitude, longitude, speed, heading, odometer, power, battery_level, shift_state
    }
    public let timestampMS: Int64?
    public let latitude, longitude, speedMPH, heading, odometerMiles, powerKW: Double?
    public let batteryPercent: Int?
    public let gear: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        timestampMS = try c.decodeIfPresent(String.self, forKey: .created_at)
            .flatMap(historyDate).map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        latitude = c.flexibleDouble(.latitude)
        longitude = c.flexibleDouble(.longitude)
        speedMPH = c.flexibleDouble(.speed)
        heading = c.flexibleDouble(.heading)
        odometerMiles = c.flexibleDouble(.odometer)
        powerKW = c.flexibleDouble(.power)
        batteryPercent = c.flexibleDouble(.battery_level).flatMap(Int.init(exactly:))
        gear = try c.decodeIfPresent(String.self, forKey: .shift_state)
    }

    fileprivate var routePoint: FleetDriveRoutePoint? {
        guard let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return FleetDriveRoutePoint(latitude: latitude, longitude: longitude, speedMPH: speedMPH,
                                   heading: heading, timestampMS: timestampMS)
    }
}

private func historyDate(_ value: String) -> Date? {
    try? Date.ISO8601FormatStyle().parse(value)
}
