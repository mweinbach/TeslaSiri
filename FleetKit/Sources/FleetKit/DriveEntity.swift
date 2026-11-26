import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation
import OSLog

/// A completed drive. Indexed in Spotlight with distance, duration, speed,
/// energy, date, and start/end locations.
public struct DriveEntity: AppEntity, IndexedEntity, SyncableEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drive")
    public static let defaultQuery = DriveEntityQuery()

    public let id: String // sessionID

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(title: "Distance", description: "Distance driven on this trip, in miles.")
    public var distanceMiles: Double?

    @Property(title: "Duration", description: "How long the drive took, in minutes.")
    public var durationMinutes: Int?

    @Property(title: "Average Speed", description: "Average speed over the drive, in miles per hour.")
    public var avgSpeedMPH: Double?

    @Property(title: "Top Speed", description: "Highest speed reached during the drive, in miles per hour.")
    public var maxSpeedMPH: Double?

    @Property(title: "Energy Used", description: "Battery energy the drive used, in kilowatt-hours.")
    public var energyUsedKWH: Double?

    @Property(
        title: "Start Address",
        description: "Where the drive started: a street address or a saved place name such as Home or Work."
    )
    public var startAddress: String?

    @Property(
        title: "Destination",
        description: "Where the drive ended: a street address or a saved place name such as Home or Work.",
        indexingKey: \.namedLocation
    )
    public var endAddress: String?

    @Property(
        title: "Started At",
        description: "When the drive started, in the user's time zone.",
        indexingKey: \.contentCreationDate
    )
    public var startedAt: Date

    @Property(title: "Ended At", description: "When the drive ended, in the user's time zone.")
    public var endedAt: Date?

    @Property(title: "Starting Battery", description: "Battery percent when the drive started, from 0 to 100.")
    public var startingBatteryPercent: Int?

    @Property(title: "Ending Battery", description: "Battery percent when the drive ended, from 0 to 100.")
    public var endingBatteryPercent: Int?

    @Property(title: "Battery Used", description: "Percentage points of battery the drive used, such as 12.")
    public var batteryUsedPercent: Int?

    @Property(
        title: "Efficiency",
        description: "Energy used per mile, in watt-hours per mile (Wh/mi). Lower is more efficient; around 250 is typical."
    )
    public var efficiencyWhPerMile: Double?

    @Property(title: "Rated Range Used", description: "EPA-rated range the drive used, in miles. Compare with Distance to judge efficiency.")
    public var ratedRangeUsedMiles: Double?

    @Property(title: "Autopilot Distance", description: "Miles driven on Autopilot or FSD (Supervised) during this trip.")
    public var autopilotDistanceMiles: Double?

    @Property(title: "Cabin Temperature", description: "Average cabin temperature during the drive, in degrees Fahrenheit.")
    public var insideTempF: Double?

    @Property(title: "Outside Temperature", description: "Average outside temperature during the drive, in degrees Fahrenheit.")
    public var outsideTempF: Double?

    @Property(title: "Drive Tag", description: "The label the user gave this drive, such as Work or Personal. Empty when untagged.")
    public var tag: String?

    @Property(title: "Start Latitude", description: "Starting GPS latitude in decimal degrees, for map rendering.", visibility: .internal)
    public var startLatitude: Double?

    @Property(title: "Start Longitude", description: "Starting GPS longitude in decimal degrees, for map rendering.", visibility: .internal)
    public var startLongitude: Double?

    @Property(title: "End Latitude", description: "Ending GPS latitude in decimal degrees, for map rendering.", visibility: .internal)
    public var endLatitude: Double?

    @Property(title: "End Longitude", description: "Ending GPS longitude in decimal degrees, for map rendering.", visibility: .internal)
    public var endLongitude: Double?

    public init(info: FleetDriveInfo) {
        self.id = info.sessionID
        self.vin = info.vin
        self.distanceMiles = info.distanceMiles
        self.durationMinutes = info.durationMinutes
        self.avgSpeedMPH = info.avgSpeedMPH
        self.maxSpeedMPH = info.maxSpeedMPH
        self.energyUsedKWH = info.energyUsedKWH
        self.startAddress = info.startAddress
        self.endAddress = info.endAddress
        self.startedAt = info.startedAtDate
        self.endedAt = info.endedAtDate
        self.startingBatteryPercent = info.startingBatteryPercent
        self.endingBatteryPercent = info.endingBatteryPercent
        self.batteryUsedPercent = info.batteryUsedPercent
        self.efficiencyWhPerMile = info.efficiencyWhPerMile
        self.ratedRangeUsedMiles = info.ratedRangeUsedMiles
        self.autopilotDistanceMiles = info.autopilotDistanceMiles
        self.insideTempF = info.insideTempF
        self.outsideTempF = info.outsideTempF
        self.tag = info.tag
        self.startLatitude = info.startLatitude
        self.startLongitude = info.startLongitude
        self.endLatitude = info.endLatitude
        self.endLongitude = info.endLongitude
    }

    public var distanceText: String {
        distanceMiles.map { FleetKitFormatting.distance(miles: $0, fractionLength: 1) }
            ?? String(localized: "Drive", bundle: .module, comment: "Fallback title for a drive without distance")
    }

    public var durationText: String? {
        durationMinutes.map { FleetKitFormatting.durationMinutes($0) }
    }

    public var batterySummaryText: String? {
        guard let start = startingBatteryPercent, let end = endingBatteryPercent else { return nil }
        return "\(FleetKitFormatting.percent(start)) → \(FleetKitFormatting.percent(end))"
    }

    public var efficiencyText: String? {
        guard let whPerMile = efficiencyWhPerMile else { return nil }
        if FleetKitFormatting.prefersMetric() {
            let whPerKm = Int((whPerMile / 1.609344).rounded())
            return String(localized: "\(whPerKm) Wh/km", bundle: .module, comment: "Driving energy efficiency in watt-hours per kilometer")
        }
        let rounded = Int(whPerMile.rounded())
        return String(localized: "\(rounded) Wh/mi", bundle: .module, comment: "Driving energy efficiency in watt-hours per mile")
    }

    public var routeText: String {
        if let startAddress, let endAddress {
            return String(localized: "\(startAddress) to \(endAddress)", bundle: .module, comment: "Drive route from start address to destination address")
        }
        if let startAddress {
            return String(localized: "Started at \(startAddress)", bundle: .module, comment: "Drive route when only the starting address is known")
        }
        if let endAddress {
            return String(localized: "Ended at \(endAddress)", bundle: .module, comment: "Drive route when only the destination address is known")
        }
        return startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    public var appleMapsRouteURL: URL? {
        var components = URLComponents(string: "http://maps.apple.com/")
        var items: [URLQueryItem] = []
        if let sLat = startLatitude, let sLon = startLongitude {
            items.append(URLQueryItem(name: "saddr", value: String(format: "%.6f,%.6f", sLat, sLon)))
        } else if let startAddress, !startAddress.isEmpty {
            items.append(URLQueryItem(name: "saddr", value: startAddress))
        }
        if let eLat = endLatitude, let eLon = endLongitude {
            items.append(URLQueryItem(name: "daddr", value: String(format: "%.6f,%.6f", eLat, eLon)))
        } else if let endAddress, !endAddress.isEmpty {
            items.append(URLQueryItem(name: "daddr", value: endAddress))
        }
        guard !items.isEmpty else { return nil }
        items.append(URLQueryItem(name: "dirflg", value: "d"))
        components?.queryItems = items
        return components?.url
    }

    public var detailText: String {
        var parts: [String] = [routeText]
        if let durationText { parts.append(durationText) }
        if let avgSpeedMPH {
            let speed = FleetKitFormatting.speed(mph: avgSpeedMPH)
            parts.append(String(localized: "avg \(speed)", bundle: .module, comment: "Abbreviated average speed on a drive, e.g. 'avg 24 mph'"))
        }
        if let maxSpeedMPH {
            let speed = FleetKitFormatting.speed(mph: maxSpeedMPH)
            parts.append(String(localized: "max \(speed)", bundle: .module, comment: "Abbreviated maximum speed on a drive, e.g. 'max 55 mph'"))
        }
        if let energyUsedKWH { parts.append(FleetKitFormatting.energyKWH(energyUsedKWH)) }
        if let efficiencyText { parts.append(efficiencyText) }
        if let batterySummaryText { parts.append(batterySummaryText) }
        return parts.joined(separator: " • ")
    }

    /// Detailed natural-language summary suitable for Siri voice readout.
    public func spokenSummary(vehicleName: String? = nil) -> String {
        let whenText = startedAt.formatted(date: .abbreviated, time: .shortened)
        let subject = vehicleName ?? String(localized: "Your Tesla", bundle: .module, comment: "Default vehicle subject in spoken drive summary")
        let durationPhrase = durationMinutes.map { FleetKitFormatting.durationMinutes($0, width: .wide) }
        var sentences: [String] = []

        if let startAddress, let endAddress {
            if let durationPhrase {
                sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) from \(startAddress) to \(endAddress) in \(durationPhrase).", bundle: .module, comment: "Spoken drive summary lead with start, destination, and duration"))
            } else {
                sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) from \(startAddress) to \(endAddress).", bundle: .module, comment: "Spoken drive summary lead with start and destination"))
            }
        } else if let endAddress {
            if let durationPhrase {
                sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) to \(endAddress) in \(durationPhrase).", bundle: .module, comment: "Spoken drive summary lead with destination and duration"))
            } else {
                sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) to \(endAddress).", bundle: .module, comment: "Spoken drive summary lead with destination"))
            }
        } else if let startAddress {
            if let durationPhrase {
                sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) starting at \(startAddress) in \(durationPhrase).", bundle: .module, comment: "Spoken drive summary lead with start address and duration"))
            } else {
                sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) starting at \(startAddress).", bundle: .module, comment: "Spoken drive summary lead with start address"))
            }
        } else if let durationPhrase {
            sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText) in \(durationPhrase).", bundle: .module, comment: "Spoken drive summary lead with duration"))
        } else {
            sentences.append(String(localized: "On \(whenText), \(subject) drove \(distanceText).", bundle: .module, comment: "Spoken drive summary lead"))
        }

        if let start = startingBatteryPercent, let end = endingBatteryPercent {
            let startPct = FleetKitFormatting.percent(start)
            let endPct = FleetKitFormatting.percent(end)
            if let energy = energyUsedKWH, let efficiency = efficiencyText {
                let kwh = FleetKitFormatting.energyKWH(energy)
                sentences.append(String(localized: "Battery went from \(startPct) to \(endPct), using \(kwh) (\(efficiency)).", bundle: .module, comment: "Spoken battery, energy, and efficiency sentence for a drive"))
            } else if let energy = energyUsedKWH {
                let kwh = FleetKitFormatting.energyKWH(energy)
                sentences.append(String(localized: "Battery went from \(startPct) to \(endPct), using \(kwh).", bundle: .module, comment: "Spoken battery and energy sentence for a drive"))
            } else if let efficiency = efficiencyText {
                sentences.append(String(localized: "Battery went from \(startPct) to \(endPct) (\(efficiency)).", bundle: .module, comment: "Spoken battery and efficiency sentence for a drive"))
            } else {
                sentences.append(String(localized: "Battery went from \(startPct) to \(endPct).", bundle: .module, comment: "Spoken battery change sentence for a drive"))
            }
        } else if let energy = energyUsedKWH, let efficiency = efficiencyText {
            let kwh = FleetKitFormatting.energyKWH(energy)
            sentences.append(String(localized: "Used \(kwh) (\(efficiency)).", bundle: .module, comment: "Spoken energy and efficiency sentence for a drive"))
        } else if let energy = energyUsedKWH {
            let kwh = FleetKitFormatting.energyKWH(energy)
            sentences.append(String(localized: "Used \(kwh).", bundle: .module, comment: "Spoken energy used sentence for a drive"))
        } else if let efficiency = efficiencyText {
            sentences.append(String(localized: "Efficiency was \(efficiency).", bundle: .module, comment: "Spoken efficiency sentence for a drive"))
        }

        if let avg = avgSpeedMPH {
            let avgText = FleetKitFormatting.speed(mph: avg)
            if let max = maxSpeedMPH {
                let maxText = FleetKitFormatting.speed(mph: max)
                sentences.append(String(localized: "Average speed was \(avgText), with a top speed of \(maxText).", bundle: .module, comment: "Spoken average and top speed for a drive"))
            } else {
                sentences.append(String(localized: "Average speed was \(avgText).", bundle: .module, comment: "Spoken average speed for a drive"))
            }
        } else if let max = maxSpeedMPH {
            let maxText = FleetKitFormatting.speed(mph: max)
            sentences.append(String(localized: "Top speed was \(maxText).", bundle: .module, comment: "Spoken top speed for a drive"))
        }

        if let ap = autopilotDistanceMiles, ap > 0.05 {
            let apDistance = FleetKitFormatting.distance(miles: ap, width: .wide, fractionLength: 1)
            sentences.append(String(localized: "\(apDistance) on Autopilot.", bundle: .module, comment: "Spoken Autopilot distance on a drive"))
        }

        if let tag, !tag.isEmpty {
            sentences.append(String(localized: "Tagged as \(tag).", bundle: .module, comment: "Spoken drive tag label"))
        }

        return sentences.joined(separator: " ")
    }

    public var displayRepresentation: DisplayRepresentation {
        let date = startedAt.formatted(date: .abbreviated, time: .shortened)
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: "\(distanceText) • \(date)"),
            subtitle: LocalizedStringResource(stringLiteral: detailText)
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let formattedDate = startedAt.formatted(date: .abbreviated, time: .shortened)
        let title = String(localized: "Tesla Drive \(formattedDate)", bundle: .module, comment: "Spotlight title for a completed Tesla drive")
        let description = String(
            localized: "Tesla drive for vehicle \(FleetKitLog.vin(vin)). \(distanceText). \(detailText).",
            bundle: .module,
            comment: "Spotlight searchable description for a completed Tesla drive"
        )
        attributes.title = title
        attributes.displayName = title
        attributes.kind = String(localized: "Tesla Drive", bundle: .module, comment: "Spotlight kind for a Tesla drive")
        attributes.contentCreationDate = startedAt
        attributes.contentModificationDate = endedAt ?? startedAt
        attributes.contentDescription = description
        attributes.textContent = description
        attributes.keywords = [
            "Tesla",
            String(localized: "drive", bundle: .module, comment: "Spotlight keyword for a drive"),
            String(localized: "trip", bundle: .module, comment: "Spotlight keyword for a trip"),
            String(localized: "route", bundle: .module, comment: "Spotlight keyword for a route"),
            String(localized: "miles", bundle: .module, comment: "Spotlight keyword for miles"),
            String(localized: "mileage", bundle: .module, comment: "Spotlight keyword for mileage"),
            String(localized: "distance", bundle: .module, comment: "Spotlight keyword for distance"),
            String(localized: "duration", bundle: .module, comment: "Spotlight keyword for duration"),
            String(localized: "time", bundle: .module, comment: "Spotlight keyword for time"),
            String(localized: "average speed", bundle: .module, comment: "Spotlight keyword for average speed"),
            String(localized: "avg speed", bundle: .module, comment: "Spotlight keyword for abbreviated average speed"),
            String(localized: "max speed", bundle: .module, comment: "Spotlight keyword for maximum speed"),
            String(localized: "energy", bundle: .module, comment: "Spotlight keyword for energy"),
            "kWh",
            String(localized: "efficiency", bundle: .module, comment: "Spotlight keyword for efficiency"),
            FleetKitLog.vin(vin), startAddress, endAddress, tag
        ].compactMap { $0 }
        return attributes
    }
}

extension DriveEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { $0.spokenSummary() })
    }
}

public struct DriveEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    public init() {}

    public func entities(for identifiers: [DriveEntity.ID]) async throws -> [DriveEntity] {
        guard !identifiers.isEmpty else { return [] }

        let service = FleetIntentService.make()
        let vehicles = try await service.vehicles()
        var remaining = Set(identifiers)
        let hasLegacyID = identifiers.contains { !$0.contains(":") }
        let requestedVINs = Set(identifiers.map { String($0.prefix { $0 != ":" }) })
        var found: [DriveEntity] = []

        for vehicle in vehicles where !remaining.isEmpty && (hasLegacyID || requestedVINs.contains(vehicle.vin)) {
            let drives = try await service.drives(vin: vehicle.vin, limit: 100)
            for drive in drives where remaining.contains(drive.sessionID) {
                found.append(DriveEntity(info: drive))
                remaining.remove(drive.sessionID)
            }
        }

        FleetKitLog.entities.info("DriveEntityQuery matched \(found.count, privacy: .public) of \(identifiers.count, privacy: .public) requested drive(s)")
        return found
    }

    public func entities(matching string: String) async throws -> [DriveEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = FleetIntentService.make()
        let vehicles = try await service.vehicles()
        var all: [DriveEntity] = []
        for vehicle in vehicles {
            do {
                let drives = try await service.drives(vin: vehicle.vin, limit: 50).map(DriveEntity.init(info:))
                all.append(contentsOf: drives)
            } catch FleetKitError.sessionExpired {
                throw FleetKitError.sessionExpired
            } catch {
                continue
            }
        }
        guard !query.isEmpty else {
            return Array(all.prefix(15))
        }
        return all.filter { drive in
            drive.startAddress?.localizedCaseInsensitiveContains(query) == true
                || drive.endAddress?.localizedCaseInsensitiveContains(query) == true
                || drive.tag?.localizedCaseInsensitiveContains(query) == true
                || drive.distanceText.localizedCaseInsensitiveContains(query)
                || drive.startedAt.formatted(date: .abbreviated, time: .shortened).localizedCaseInsensitiveContains(query)
        }
    }

    public func suggestedEntities() async throws -> [DriveEntity] {
        let service = FleetIntentService.make()
        let vehicle = try await service.resolvedVehicle(nil)
        let drives = try await service.drives(vin: vehicle.vin, limit: 10).map(DriveEntity.init(info:))
        FleetKitLog.entities.info("DriveEntityQuery suggesting \(drives.count, privacy: .public) drive(s) for \(vehicle.name, privacy: .public)")
        return drives
    }

    public func reindexEntities(for identifiers: [DriveEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(entities(for: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let service = FleetIntentService.make()
        var all: [DriveEntity] = []
        for vehicle in try await service.vehicles() {
            all.append(contentsOf: try await service.drives(vin: vehicle.vin, limit: 50).map(DriveEntity.init(info:)))
        }
        try await FleetSpotlightIndexer.donate(all)
    }
}
