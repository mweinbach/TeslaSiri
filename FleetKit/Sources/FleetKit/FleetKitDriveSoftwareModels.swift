import Foundation

public struct FleetDriveRoutePoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let speedMPH: Double?
    public let heading: Double?
    public let autopilotState: String?
    public let timestampMS: Int64?

    public var isAutopilotActive: Bool {
        guard let state = autopilotState?.lowercased(), !state.isEmpty else { return false }
        return state != "off" && state != "none" && state != "standby"
    }

    public init(
        latitude: Double,
        longitude: Double,
        speedMPH: Double? = nil,
        heading: Double? = nil,
        autopilotState: String? = nil,
        timestampMS: Int64? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.speedMPH = speedMPH
        self.heading = heading
        self.autopilotState = autopilotState
        self.timestampMS = timestampMS
    }
}

public struct FleetDriveInfo: Codable, Sendable, Identifiable {
    public let sessionID: String
    public let vin: String
    public let distanceMiles: Double?
    public let durationMS: Int64?
    public let avgSpeedMPH: Double?
    public let maxSpeedMPH: Double?
    public let energyUsedKWH: Double?
    public let startedAt: Int64
    public let endedAt: Int64?
    public let startAddress: String?
    public let endAddress: String?
    public let startLatitude: Double?
    public let startLongitude: Double?
    public let endLatitude: Double?
    public let endLongitude: Double?
    public let startingBatteryPercent: Int?
    public let endingBatteryPercent: Int?
    public let ratedRangeUsedMiles: Double?
    public let autopilotDistanceMiles: Double?
    public let insideTempF: Double?
    public let outsideTempF: Double?
    public let tag: String?

    public var id: String { sessionID }
    public var startedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000) }
    public var endedAtDate: Date? { endedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    var durationMinutes: Int? { durationMS.map { Int($0 / 60_000) } }

    public var batteryUsedPercent: Int? {
        guard let start = startingBatteryPercent, let end = endingBatteryPercent else { return nil }
        return start - end
    }

    public var efficiencyWhPerMile: Double? {
        guard let miles = distanceMiles, miles > 0.05, let energy = energyUsedKWH, energy >= 0 else {
            return nil
        }
        return (energy * 1000.0) / miles
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case vin
        case distanceMiles = "distance_miles"
        case durationMS = "duration_ms"
        case avgSpeedMPH = "avg_speed_mph"
        case maxSpeedMPH = "max_speed_mph"
        case energyUsedKWH = "energy_used_kwh"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case startAddress = "start_address"
        case endAddress = "end_address"
        case startLatitude = "starting_latitude"
        case startLongitude = "starting_longitude"
        case endLatitude = "ending_latitude"
        case endLongitude = "ending_longitude"
        case startingBatteryPercent = "starting_battery"
        case endingBatteryPercent = "ending_battery"
        case ratedRangeUsedMiles = "rated_range_used"
        case autopilotDistanceMiles = "autopilot_distance"
        case insideTempF = "average_inside_temperature"
        case outsideTempF = "average_outside_temperature"
        case tag
    }

    init(
        sessionID: String,
        vin: String,
        distanceMiles: Double?,
        durationMS: Int64?,
        avgSpeedMPH: Double?,
        maxSpeedMPH: Double?,
        energyUsedKWH: Double?,
        startedAt: Int64,
        endedAt: Int64?,
        startAddress: String?,
        endAddress: String?,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        startingBatteryPercent: Int? = nil,
        endingBatteryPercent: Int? = nil,
        ratedRangeUsedMiles: Double? = nil,
        autopilotDistanceMiles: Double? = nil,
        insideTempF: Double? = nil,
        outsideTempF: Double? = nil,
        tag: String? = nil
    ) {
        self.sessionID = sessionID
        self.vin = vin
        self.distanceMiles = distanceMiles
        self.durationMS = durationMS
        self.avgSpeedMPH = avgSpeedMPH
        self.maxSpeedMPH = maxSpeedMPH
        self.energyUsedKWH = energyUsedKWH
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.startingBatteryPercent = startingBatteryPercent
        self.endingBatteryPercent = endingBatteryPercent
        self.ratedRangeUsedMiles = ratedRangeUsedMiles
        self.autopilotDistanceMiles = autopilotDistanceMiles
        self.insideTempF = insideTempF
        self.outsideTempF = outsideTempF
        self.tag = tag
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        vin = try c.decodeIfPresent(String.self, forKey: .vin) ?? ""
        distanceMiles = c.flexibleDouble(.distanceMiles)
        durationMS = c.flexibleInt64(.durationMS)
        avgSpeedMPH = c.flexibleDouble(.avgSpeedMPH)
        maxSpeedMPH = c.flexibleDouble(.maxSpeedMPH)
        energyUsedKWH = c.flexibleDouble(.energyUsedKWH)
        startedAt = c.flexibleInt64(.startedAt) ?? 0
        endedAt = c.flexibleInt64(.endedAt)
        startAddress = try c.decodeIfPresent(String.self, forKey: .startAddress)
        endAddress = try c.decodeIfPresent(String.self, forKey: .endAddress)
        startLatitude = c.flexibleDouble(.startLatitude)
        startLongitude = c.flexibleDouble(.startLongitude)
        endLatitude = c.flexibleDouble(.endLatitude)
        endLongitude = c.flexibleDouble(.endLongitude)
        startingBatteryPercent = c.flexibleInt64(.startingBatteryPercent).map(Int.init)
        endingBatteryPercent = c.flexibleInt64(.endingBatteryPercent).map(Int.init)
        ratedRangeUsedMiles = c.flexibleDouble(.ratedRangeUsedMiles)
        autopilotDistanceMiles = c.flexibleDouble(.autopilotDistanceMiles)
        insideTempF = c.flexibleDouble(.insideTempF)
        outsideTempF = c.flexibleDouble(.outsideTempF)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
    }
}

public struct FleetReleaseNoteInfo: Codable, Sendable, Identifiable {
    public let title: String
    public let subtitle: String?
    public let details: String?
    public let customerVersion: String?

    public var id: String {
        let noteTitle = title + (subtitle ?? "")
        return customerVersion.map { "\($0):\(noteTitle)" } ?? noteTitle
    }

    enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case details = "description"
        case customerVersion = "customer_version"
    }

    public init(
        title: String,
        subtitle: String? = nil,
        details: String? = nil,
        customerVersion: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.customerVersion = customerVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        customerVersion = try c.decodeIfPresent(String.self, forKey: .customerVersion)
    }
}

public struct FleetSoftwareInfo: Codable, Sendable {
    public let currentVersion: String?
    public let availableVersion: String?
    public let updateAvailable: Bool
    public let installable: Bool
    public let status: String?
    public let downloadPercent: Double?
    public let installPercent: Double?
    public let expectedDurationMinutes: Double?
    public let releaseNotes: [FleetReleaseNoteInfo]

    enum CodingKeys: String, CodingKey {
        case currentVersion = "current_version"
        case availableVersion = "available_version"
        case updateAvailable = "update_available"
        case installable
        case status
        case downloadPercent = "download_percent"
        case installPercent = "install_percent"
        case expectedDurationMinutes = "expected_duration_minutes"
        case releaseNotes = "release_notes"
    }

    init(
        currentVersion: String?,
        availableVersion: String?,
        updateAvailable: Bool,
        installable: Bool,
        status: String?,
        downloadPercent: Double?,
        installPercent: Double?,
        expectedDurationMinutes: Double?,
        releaseNotes: [FleetReleaseNoteInfo] = []
    ) {
        self.currentVersion = currentVersion
        self.availableVersion = availableVersion
        self.updateAvailable = updateAvailable
        self.installable = installable
        self.status = status
        self.downloadPercent = downloadPercent
        self.installPercent = installPercent
        self.expectedDurationMinutes = expectedDurationMinutes
        self.releaseNotes = releaseNotes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentVersion = try c.decodeIfPresent(String.self, forKey: .currentVersion)
        availableVersion = try c.decodeIfPresent(String.self, forKey: .availableVersion)
        updateAvailable = try c.decodeIfPresent(Bool.self, forKey: .updateAvailable) ?? false
        installable = try c.decodeIfPresent(Bool.self, forKey: .installable) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status)
        downloadPercent = c.flexibleDouble(.downloadPercent)
        installPercent = c.flexibleDouble(.installPercent)
        expectedDurationMinutes = c.flexibleDouble(.expectedDurationMinutes)
        releaseNotes = try c.decodeIfPresent([FleetReleaseNoteInfo].self, forKey: .releaseNotes) ?? []
    }
}

public struct FleetControlActionsInfo: Decodable, Sendable {
    public let actions: [String]
    public let chargeActions: [String]
    public let schemas: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case actions
        case chargeActions = "charge_actions"
        case schemas
    }

    init(actions: [String], chargeActions: [String], schemas: [String: [String]]) {
        self.actions = actions
        self.chargeActions = chargeActions
        self.schemas = schemas
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actions = try c.decodeIfPresent([String].self, forKey: .actions) ?? []
        chargeActions = try c.decodeIfPresent([String].self, forKey: .chargeActions) ?? []
        schemas = try c.decodeIfPresent([String: [String]].self, forKey: .schemas) ?? [:]
    }

    /// Whether the backend advertises the given action for this account/vehicle.
    public func supports(_ action: String) -> Bool {
        actions.contains(action) || chargeActions.contains(action)
    }
}

extension KeyedDecodingContainer {
    func flexibleInt64(_ key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(string)
        }
        return nil
    }
}
