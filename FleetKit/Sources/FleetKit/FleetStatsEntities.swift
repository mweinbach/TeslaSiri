import AppIntents
import CoreSpotlight
import CoreTransferable
import OSLog
import Foundation

/// Time window used by driving and charging statistics tools.
public enum StatsPeriod: String, AppEnum, Sendable {
    case sinceLastCharge
    case today
    case last7Days
    case last30Days
    case last90Days

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stats Period")
    public static let caseDisplayRepresentations: [StatsPeriod: DisplayRepresentation] = [
        .sinceLastCharge: DisplayRepresentation(title: "Since Last Charge", subtitle: "Usage since the most recent completed charge"),
        .today: DisplayRepresentation(title: "Today", subtitle: "Since midnight local time"),
        .last7Days: DisplayRepresentation(title: "Last 7 Days", subtitle: "Past week"),
        .last30Days: DisplayRepresentation(title: "Last 30 Days", subtitle: "Past month"),
        .last90Days: DisplayRepresentation(title: "Last 90 Days", subtitle: "Past 3 months")
    ]

    public var displayTitle: String {
        switch self {
        case .sinceLastCharge:
            String(localized: "Since Last Charge", bundle: .module, comment: "Display title for stats period since last charge")
        case .today:
            String(localized: "Today", bundle: .module, comment: "Display title for today's stats period")
        case .last7Days:
            String(localized: "Last 7 Days", bundle: .module, comment: "Display title for 7-day stats period")
        case .last30Days:
            String(localized: "Last 30 Days", bundle: .module, comment: "Display title for 30-day stats period")
        case .last90Days:
            String(localized: "Last 90 Days", bundle: .module, comment: "Display title for 90-day stats period")
        }
    }

    public var spokenLabel: String {
        switch self {
        case .sinceLastCharge:
            String(localized: "since the last charge", bundle: .module, comment: "Spoken time window phrase for since last charge")
        case .today:
            String(localized: "today", bundle: .module, comment: "Spoken time window phrase for today")
        case .last7Days:
            String(localized: "over the last 7 days", bundle: .module, comment: "Spoken time window phrase for last 7 days")
        case .last30Days:
            String(localized: "over the last 30 days", bundle: .module, comment: "Spoken time window phrase for last 30 days")
        case .last90Days:
            String(localized: "over the last 90 days", bundle: .module, comment: "Spoken time window phrase for last 90 days")
        }
    }

    public func startDate(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .sinceLastCharge:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now)
        case .last90Days:
            return calendar.date(byAdding: .day, value: -90, to: now)
        }
    }
}

/// Aggregated driving, efficiency, Autopilot, and consumption statistics for a Tesla vehicle.
public struct DrivingStatsEntity: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Driving Stats")

    @Property(title: "Vehicle Name", description: "The owner's name for the car these numbers are about.")
    public var vehicleName: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(title: "Period", description: "The time window these totals cover, such as Last 7 Days or Since Last Charge.")
    public var periodTitle: String

    @Property(title: "Completed Drives", description: "Number of completed drives in the period.")
    public var driveCount: Int

    @Property(title: "Total Distance (Miles)", description: "Total miles driven in the period.")
    public var totalDistanceMiles: Double

    @Property(title: "Total Drive Time (Minutes)", description: "Total time spent driving in the period, in minutes.")
    public var totalDurationMinutes: Int

    @Property(title: "Total Driving Energy (kWh)", description: "Battery energy used for driving in the period, in kilowatt-hours.")
    public var totalEnergyUsedKWH: Double?

    @Property(title: "Average Efficiency (Wh/mi)", description: "Average energy used per mile, in watt-hours per mile. Lower is more efficient.")
    public var averageEfficiencyWhPerMile: Double?

    @Property(title: "Average Efficiency (mi/kWh)", description: "Average miles driven per kilowatt-hour. Higher is more efficient.")
    public var milesPerKWH: Double?

    @Property(title: "Average Speed (MPH)", description: "Average speed while driving in the period, in miles per hour.")
    public var averageSpeedMPH: Double?

    @Property(title: "Top Speed (MPH)", description: "Highest speed reached in the period, in miles per hour.")
    public var topSpeedMPH: Double?

    @Property(title: "Longest Drive (Miles)", description: "Distance of the longest single drive in the period, in miles.")
    public var longestDriveMiles: Double?

    @Property(title: "Autopilot Distance (Miles)", description: "Miles driven on Autopilot or FSD (Supervised) in the period.")
    public var autopilotDistanceMiles: Double?

    @Property(title: "Autopilot Share (%)", description: "Share of all miles driven on Autopilot or FSD (Supervised), as a percent.")
    public var autopilotSharePercent: Double?

    @Property(title: "Idle / Phantom Energy Since Charge (kWh)", description: "Energy used while parked since the last charge (Sentry Mode, climate, standby), in kilowatt-hours.")
    public var idleEnergySinceChargeKWH: Double?

    @Property(title: "Battery Used Since Charge (%)", description: "Percentage points of battery used since the last charge, driving and parked combined.")
    public var batteryPercentUsedSinceCharge: Double?

    public var displayRepresentation: DisplayRepresentation {
        let usesMetric = FleetKitFormatting.prefersMetric()
        let efficiencyString: String? = averageEfficiencyWhPerMile.map { whPerMi in
            if usesMetric {
                let whPerKm = Int((whPerMi / 1.609344).rounded())
                return String(localized: "\(whPerKm) Wh/km", bundle: .module, comment: "Driving efficiency in watt-hours per kilometer")
            }
            return String(localized: "\(Int(whPerMi.rounded())) Wh/mi", bundle: .module, comment: "Driving efficiency in watt-hours per mile")
        }
        let subtitle = [
            String(localized: "\(driveCount) drives", bundle: .module, comment: "Drive count in driving stats subtitle"),
            totalEnergyUsedKWH.map { FleetKitFormatting.energyKWH($0) },
            efficiencyString
        ].compactMap { $0 }.joined(separator: " • ")
        let distanceText = FleetKitFormatting.distance(miles: totalDistanceMiles, usesMetric: usesMetric, fractionLength: 1)
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: "\(distanceText) (\(periodTitle))"),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }

    public init() {
        self.vehicleName = ""
        self.vin = ""
        self.periodTitle = ""
        self.driveCount = 0
        self.totalDistanceMiles = 0
        self.totalDurationMinutes = 0
        self.totalEnergyUsedKWH = nil
        self.averageEfficiencyWhPerMile = nil
        self.milesPerKWH = nil
        self.averageSpeedMPH = nil
        self.topSpeedMPH = nil
        self.longestDriveMiles = nil
        self.autopilotDistanceMiles = nil
        self.autopilotSharePercent = nil
        self.idleEnergySinceChargeKWH = nil
        self.batteryPercentUsedSinceCharge = nil
    }

    public init(
        vehicle: FleetVehicleInfo,
        period: StatsPeriod,
        drives: [FleetDriveInfo],
        consumption: FleetConsumptionInfo? = nil
    ) {
        self.vehicleName = vehicle.name
        self.vin = vehicle.vin
        self.periodTitle = period.displayTitle
        self.driveCount = drives.count

        let summedMiles = drives.compactMap(\.distanceMiles).reduce(0, +)
        let resolvedMiles = (period == .sinceLastCharge && summedMiles == 0)
            ? (consumption?.distanceDrivenMiles ?? 0)
            : summedMiles
        self.totalDistanceMiles = resolvedMiles

        let totalMS = drives.compactMap(\.durationMS).reduce(Int64(0), +)
        self.totalDurationMinutes = Int(totalMS / 60_000)

        let energies = drives.compactMap(\.energyUsedKWH)
        if energies.count == drives.count && !drives.isEmpty {
            self.totalEnergyUsedKWH = energies.reduce(0, +)
        } else {
            self.totalEnergyUsedKWH = consumption?.energyUsedByDrivingKWH
        }

        if let resolvedDrivingEnergy = totalEnergyUsedKWH, resolvedMiles > 0.05, resolvedDrivingEnergy > 0 {
            self.averageEfficiencyWhPerMile = (resolvedDrivingEnergy * 1000.0) / resolvedMiles
            self.milesPerKWH = resolvedMiles / resolvedDrivingEnergy
        } else {
            self.averageEfficiencyWhPerMile = nil
            self.milesPerKWH = nil
        }

        if totalMS > 0 && resolvedMiles > 0 {
            let hours = Double(totalMS) / 3_600_000.0
            self.averageSpeedMPH = hours > 0 ? (resolvedMiles / hours) : nil
        } else {
            let speeds = drives.compactMap(\.avgSpeedMPH)
            self.averageSpeedMPH = speeds.isEmpty ? nil : (speeds.reduce(0, +) / Double(speeds.count))
        }

        self.topSpeedMPH = drives.compactMap(\.maxSpeedMPH).max()
        self.longestDriveMiles = drives.compactMap(\.distanceMiles).max()

        let autopilotReadings = drives.compactMap(\.autopilotDistanceMiles)
        if !autopilotReadings.isEmpty && autopilotReadings.count == drives.count {
            let miles = autopilotReadings.reduce(0, +)
            self.autopilotDistanceMiles = miles
            self.autopilotSharePercent = resolvedMiles > 0.05 ? min(100.0, 100.0 * miles / resolvedMiles) : nil
        }

        self.idleEnergySinceChargeKWH = consumption?.idleEnergyUsedKWH
        self.batteryPercentUsedSinceCharge = consumption?.batteryPercentUsed
    }

    public func spokenSummary(period: StatsPeriod) -> String {
        let usesMetric = FleetKitFormatting.prefersMetric()
        if driveCount == 0 && totalDistanceMiles < 0.05 {
            if let idle = idleEnergySinceChargeKWH, idle > 0.05 {
                let kwh = FleetKitFormatting.energyKWH(idle)
                return String(
                    localized: "\(vehicleName) has no recorded drives \(period.spokenLabel), with \(kwh) used while parked.",
                    bundle: .module,
                    comment: "Spoken driving stats when there are no drives but idle energy was used"
                )
            }
            return String(
                localized: "\(vehicleName) has no recorded drives \(period.spokenLabel).",
                bundle: .module,
                comment: "Spoken driving stats when there are no recorded drives in the period"
            )
        }

        var sentences: [String] = []
        let durationPhrase = FleetKitFormatting.durationMinutes(totalDurationMinutes)
        let distancePhrase = FleetKitFormatting.distance(miles: totalDistanceMiles, usesMetric: usesMetric, width: .wide, fractionLength: 1)

        if let totalEnergyUsedKWH {
            let energyText = FleetKitFormatting.energyKWH(totalEnergyUsedKWH)
            sentences.append(
                String(
                    localized: "For \(vehicleName) \(period.spokenLabel): \(driveCount) drives, \(distancePhrase) in \(durationPhrase), using \(energyText).",
                    bundle: .module,
                    comment: "Spoken driving stats headline with energy used"
                )
            )
        } else {
            sentences.append(
                String(
                    localized: "For \(vehicleName) \(period.spokenLabel): \(driveCount) drives, \(distancePhrase) in \(durationPhrase).",
                    bundle: .module,
                    comment: "Spoken driving stats headline without energy used"
                )
            )
        }

        if let whPerMi = averageEfficiencyWhPerMile, let miPerKWH = milesPerKWH {
            if usesMetric {
                let whPerKm = Int((whPerMi / 1.609344).rounded())
                let kmPerKWH = (miPerKWH * 1.609344).formatted(.number.precision(.fractionLength(1)))
                sentences.append(
                    String(
                        localized: "Average efficiency was \(whPerKm) Wh/km (\(kmPerKWH) km/kWh).",
                        bundle: .module,
                        comment: "Spoken average efficiency in metric units"
                    )
                )
            } else {
                let whRounded = Int(whPerMi.rounded())
                let miFormatted = miPerKWH.formatted(.number.precision(.fractionLength(1)))
                sentences.append(
                    String(
                        localized: "Average efficiency was \(whRounded) Wh/mi (\(miFormatted) mi/kWh).",
                        bundle: .module,
                        comment: "Spoken average efficiency in imperial units"
                    )
                )
            }
        }

        if let autopilotDistanceMiles, autopilotDistanceMiles > 0.1, let share = autopilotSharePercent {
            let apDistance = FleetKitFormatting.distance(miles: autopilotDistanceMiles, usesMetric: usesMetric, width: .wide, fractionLength: 1)
            let sharePct = FleetKitFormatting.percent(share)
            sentences.append(
                String(
                    localized: "Autopilot covered \(apDistance) (\(sharePct)).",
                    bundle: .module,
                    comment: "Spoken Autopilot distance and percentage share"
                )
            )
        }

        if period == .sinceLastCharge, let idle = idleEnergySinceChargeKWH, idle >= 0.1 {
            let kwh = FleetKitFormatting.energyKWH(idle)
            sentences.append(
                String(
                    localized: "Parked and idle systems used \(kwh) since the last charge.",
                    bundle: .module,
                    comment: "Spoken idle energy used while parked since last charge"
                )
            )
        }

        return sentences.joined(separator: " ")
    }
}

/// A single completed charging session from Tessie's charging history. Indexed in
/// Spotlight so Siri can find a charge by place or date without launching the app.
public struct ChargeSessionEntity: AppEntity, IndexedEntity, SyncableEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Charging Session")
    public static let defaultQuery = ChargeSessionEntityQuery()

    /// "<VIN>:<Tessie charge id>"
    public let id: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(
        title: "Location",
        description: "Where the car charged: a Supercharger site name, a street address, or a saved place such as Home.",
        indexingKey: \.namedLocation
    )
    public var location: String?

    @Property(title: "Supercharger", description: "Whether this was a Tesla Supercharger (DC fast charging) session rather than AC charging at home or a destination charger.")
    public var isSupercharger: Bool

    @Property(
        title: "Started At",
        description: "When charging started, in the user's time zone.",
        indexingKey: \.contentCreationDate
    )
    public var startedAt: Date

    @Property(title: "Ended At", description: "When charging ended, in the user's time zone.")
    public var endedAt: Date?

    @Property(title: "Duration", description: "How long the car was charging, in minutes.")
    public var durationMinutes: Int?

    @Property(title: "Energy Added", description: "Energy added to the battery, in kilowatt-hours.")
    public var energyAddedKWH: Double?

    @Property(
        title: "Energy Drawn",
        description: "Energy drawn from the charger, in kilowatt-hours. It's higher than Energy Added because of charging losses."
    )
    public var energyDrawnKWH: Double?

    @Property(title: "Charging Efficiency", description: "Energy Added divided by Energy Drawn, as a percent such as 88.")
    public var chargingEfficiencyPercent: Double?

    @Property(title: "Range Added", description: "Driving range added by this charge, in miles.")
    public var milesAdded: Double?

    @Property(title: "Starting Battery", description: "Battery percent when charging started, from 0 to 100.")
    public var startingBatteryPercent: Int?

    @Property(title: "Ending Battery", description: "Battery percent when charging ended, from 0 to 100.")
    public var endingBatteryPercent: Int?

    @Property(
        title: "Cost",
        description: "What the session cost, in the currency recorded by the provider. Empty when no cost was recorded, which doesn't mean it was free."
    )
    public var cost: Double?

    @Property(title: "Currency", description: "Currency code for the recorded cost, when supplied by the provider.")
    public var currency: String?

    public var formattedCost: String? { cost.map { formatChargeCost($0, currency: currency) } }

    @Property(title: "Odometer", description: "The car's odometer when it charged, in miles.")
    public var odometerMiles: Double?

    @Property(title: "Latitude", description: "Charging site GPS latitude in decimal degrees, for map rendering.", visibility: .internal)
    public var latitude: Double?

    @Property(title: "Longitude", description: "Charging site GPS longitude in decimal degrees, for map rendering.", visibility: .internal)
    public var longitude: Double?

    public init(info: FleetChargeInfo) {
        self.id = info.sessionID
        self.vin = info.vin
        self.location = info.location
        self.isSupercharger = info.isSupercharger
        self.startedAt = info.startedAtDate
        self.endedAt = info.endedAtDate
        self.durationMinutes = info.durationMinutes
        self.energyAddedKWH = info.energyAddedKWH
        self.energyDrawnKWH = info.energyUsedKWH
        if let added = info.energyAddedKWH, let drawn = info.energyUsedKWH, drawn > 0.1, added <= drawn {
            self.chargingEfficiencyPercent = (added / drawn * 100).rounded()
        } else {
            self.chargingEfficiencyPercent = nil
        }
        self.milesAdded = info.milesAdded
        self.startingBatteryPercent = info.startingBatteryPercent
        self.endingBatteryPercent = info.endingBatteryPercent
        self.cost = info.cost
        self.currency = info.currency
        self.odometerMiles = info.odometerMiles
        self.latitude = info.latitude
        self.longitude = info.longitude
    }

    public var chargerKindText: String {
        isSupercharger
            ? "Supercharger"
            : String(localized: "AC charging", bundle: .module, comment: "Label for AC / home charging sessions")
    }

    public var energyText: String {
        energyAddedKWH.map { "+\(FleetKitFormatting.energyKWH($0))" } ?? chargerKindText
    }

    public var batterySummaryText: String? {
        guard let start = startingBatteryPercent, let end = endingBatteryPercent else { return nil }
        return "\(FleetKitFormatting.percent(start)) → \(FleetKitFormatting.percent(end))"
    }

    public var appleMapsLocationURL: URL? {
        var components = URLComponents(string: "http://maps.apple.com/")
        var items: [URLQueryItem] = []
        if let lat = latitude, let lon = longitude {
            items.append(URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", lat, lon)))
            items.append(URLQueryItem(name: "q", value: location ?? chargerKindText))
        } else if let location, !location.isEmpty {
            items.append(URLQueryItem(name: "q", value: location))
        } else {
            return nil
        }
        components?.queryItems = items
        return components?.url
    }

    public var displayRepresentation: DisplayRepresentation {
        let place = location ?? chargerKindText
        let subtitleParts: [String] = [
            startedAt.formatted(date: .abbreviated, time: .shortened),
            batterySummaryText,
            milesAdded.map { "+\(FleetKitFormatting.distance(miles: $0))" },
            formattedCost
        ].compactMap { $0 }
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: "\(energyText) • \(place)"),
            subtitle: LocalizedStringResource(stringLiteral: subtitleParts.joined(separator: " • ")),
            image: .init(systemName: isSupercharger ? "bolt.circle" : "powerplug")
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let date = startedAt.formatted(date: .abbreviated, time: .shortened)
        let title = isSupercharger
            ? String(localized: "Supercharger session \(date)", bundle: .module, comment: "Spotlight title for a Tesla Supercharger session")
            : String(localized: "Charging session \(date)", bundle: .module, comment: "Spotlight title for a charging session")
        let description = spokenSummary()
        attributes.title = title
        attributes.displayName = title
        attributes.kind = String(localized: "Tesla Charging Session", bundle: .module, comment: "Spotlight kind for a Tesla charging session")
        attributes.contentCreationDate = startedAt
        attributes.contentModificationDate = endedAt ?? startedAt
        attributes.contentDescription = description
        attributes.textContent = description
        attributes.keywords = [
            "Tesla",
            String(localized: "charge", bundle: .module, comment: "Spotlight keyword for charge"),
            String(localized: "charging", bundle: .module, comment: "Spotlight keyword for charging"),
            String(localized: "charging session", bundle: .module, comment: "Spotlight keyword for charging session"),
            "kWh",
            String(localized: "energy", bundle: .module, comment: "Spotlight keyword for energy"),
            String(localized: "cost", bundle: .module, comment: "Spotlight keyword for cost"),
            isSupercharger ? "Supercharger" : String(localized: "home charging", bundle: .module, comment: "Spotlight keyword for home charging"),
            isSupercharger ? String(localized: "Supercharging", bundle: .module, comment: "Spotlight keyword for Supercharging") : "AC",
            location
        ].compactMap { $0 }
        return attributes
    }

    public func spokenSummary(vehicleName: String? = nil) -> String {
        let whenText = startedAt.formatted(date: .abbreviated, time: .shortened)
        let subject = vehicleName ?? String(localized: "Your Tesla", bundle: .module, comment: "Default vehicle subject in spoken charging summary")
        var sentences: [String] = []

        if isSupercharger {
            if let location, !location.isEmpty {
                sentences.append(String(localized: "On \(whenText), \(subject) Supercharged at \(location).", bundle: .module, comment: "Spoken Supercharger session lead with location"))
            } else {
                sentences.append(String(localized: "On \(whenText), \(subject) Supercharged.", bundle: .module, comment: "Spoken Supercharger session lead without location"))
            }
        } else if let location, !location.isEmpty {
            sentences.append(String(localized: "On \(whenText), \(subject) charged at \(location).", bundle: .module, comment: "Spoken charging session lead with location"))
        } else {
            sentences.append(String(localized: "On \(whenText), \(subject) charged.", bundle: .module, comment: "Spoken charging session lead without location"))
        }

        if let start = startingBatteryPercent, let end = endingBatteryPercent {
            let startPct = FleetKitFormatting.percent(start)
            let endPct = FleetKitFormatting.percent(end)
            if let kwh = energyAddedKWH {
                let energy = FleetKitFormatting.energyKWH(kwh)
                if let miles = milesAdded, miles > 0 {
                    let dist = FleetKitFormatting.distance(miles: miles, width: .wide)
                    sentences.append(String(localized: "Battery went from \(startPct) to \(endPct), adding \(energy) (\(dist)).", bundle: .module, comment: "Spoken battery, energy, and range added during a charge session"))
                } else {
                    sentences.append(String(localized: "Battery went from \(startPct) to \(endPct), adding \(energy).", bundle: .module, comment: "Spoken battery and energy added during a charge session"))
                }
            } else {
                sentences.append(String(localized: "Battery went from \(startPct) to \(endPct).", bundle: .module, comment: "Spoken battery change during a charge session"))
            }
        } else if let kwh = energyAddedKWH {
            let energy = FleetKitFormatting.energyKWH(kwh)
            if let miles = milesAdded, miles > 0 {
                let dist = FleetKitFormatting.distance(miles: miles, width: .wide)
                sentences.append(String(localized: "Added \(energy) (\(dist)).", bundle: .module, comment: "Spoken energy and range added during a charge session"))
            } else {
                sentences.append(String(localized: "Added \(energy).", bundle: .module, comment: "Spoken energy added during a charge session"))
            }
        }

        if let minutes = durationMinutes, minutes > 0 {
            let duration = FleetKitFormatting.durationMinutes(minutes)
            if let formattedCost {
                sentences.append(String(localized: "Charging took \(duration) and cost \(formattedCost).", bundle: .module, comment: "Spoken charging duration and cost"))
            } else {
                sentences.append(String(localized: "Charging took \(duration).", bundle: .module, comment: "Spoken charging duration"))
            }
        } else if let formattedCost {
            sentences.append(String(localized: "Cost was \(formattedCost).", bundle: .module, comment: "Spoken charging cost"))
        }

        return sentences.joined(separator: " ")
    }
}

extension ChargeSessionEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { $0.spokenSummary() })
    }
}

public struct ChargeSessionEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    public init() {}

    public func entities(for identifiers: [ChargeSessionEntity.ID]) async throws -> [ChargeSessionEntity] {
        guard !identifiers.isEmpty else { return [] }
        let service = FleetIntentService.make()
        let vehicles = try await service.vehicles()
        var remaining = Set(identifiers)
        var found: [ChargeSessionEntity] = []

        // Only query the vehicles the identifiers belong to ("<VIN>:<id>").
        let requestedVINs = Set(identifiers.compactMap { $0.split(separator: ":").first.map(String.init) })
        for vehicle in vehicles where !remaining.isEmpty && (requestedVINs.isEmpty || requestedVINs.contains(vehicle.vin)) {
            let charges = try await service.charges(vin: vehicle.vin, limit: 200)
            for charge in charges where remaining.contains(charge.sessionID) {
                found.append(ChargeSessionEntity(info: charge))
                remaining.remove(charge.sessionID)
            }
        }
        FleetKitLog.entities.info("ChargeSessionEntityQuery matched \(found.count, privacy: .public) of \(identifiers.count, privacy: .public) requested charge(s)")
        return found
    }

    public func entities(matching string: String) async throws -> [ChargeSessionEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = FleetIntentService.make()
        var all: [ChargeSessionEntity] = []
        for vehicle in try await service.vehicles() {
            let charges = try await service.charges(vin: vehicle.vin, limit: 50).map(ChargeSessionEntity.init(info:))
            all.append(contentsOf: charges)
        }
        guard !query.isEmpty else { return Array(all.prefix(10)) }
        let asksSupercharger = query.localizedCaseInsensitiveContains("supercharg")
            || query.localizedCaseInsensitiveContains("supercarg")
        return all.filter { session in
            session.location?.localizedCaseInsensitiveContains(query) == true
                || (asksSupercharger && session.isSupercharger)
                || session.startedAt.formatted(date: .abbreviated, time: .shortened).localizedCaseInsensitiveContains(query)
        }
    }

    public func suggestedEntities() async throws -> [ChargeSessionEntity] {
        let service = FleetIntentService.make()
        let vehicle = try await service.resolvedVehicle(nil)
        return try await service.charges(vin: vehicle.vin, limit: 10).map(ChargeSessionEntity.init(info:))
    }

    public func reindexEntities(for identifiers: [ChargeSessionEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(entities(for: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let service = FleetIntentService.make()
        var all: [ChargeSessionEntity] = []
        for vehicle in try await service.vehicles() {
            all.append(contentsOf: try await service.charges(vin: vehicle.vin, limit: FleetSpotlightIndexer.chargesPerVehicle).map(ChargeSessionEntity.init(info:)))
        }
        try await FleetSpotlightIndexer.donate(all)
    }
}

private func formatChargeCost(_ amount: Double, currency: String?) -> String {
    if let currency { return amount.formatted(.currency(code: currency)) }
    return amount.formatted(.number.precision(.fractionLength(2)))
}

/// Aggregated charging energy, Supercharger split, range added, and cost statistics.
public struct ChargingStatsEntity: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Charging Stats")

    @Property(title: "Vehicle Name", description: "The owner's name for the car these numbers are about.")
    public var vehicleName: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(title: "Period", description: "The time window these totals cover, such as Last 7 Days or Since Last Charge.")
    public var periodTitle: String

    @Property(title: "Charging Sessions", description: "Number of charging sessions in the period.")
    public var sessionCount: Int

    @Property(title: "Supercharger Sessions", description: "Number of those sessions at Tesla Superchargers.")
    public var superchargerCount: Int

    @Property(title: "AC / Home Sessions", description: "Number of those sessions on AC charging, such as at home or a destination charger.")
    public var acSessionCount: Int

    @Property(title: "Total Energy Added (kWh)", description: "Total energy added to the battery in the period, in kilowatt-hours.")
    public var totalEnergyAddedKWH: Double

    @Property(title: "Total Miles Added", description: "Total driving range added in the period, in miles.")
    public var totalMilesAdded: Double

    @Property(title: "Total Charging Cost", description: "Sum of recorded charging costs for the period. Empty if there are no recorded costs or the currencies differ.")
    public var totalCost: Double?

    @Property(title: "Currency", description: "Currency code shared by the recorded charging costs, when available.")
    public var currency: String?

    public var formattedCost: String? { totalCost.map { formatChargeCost($0, currency: currency) } }

    @Property(title: "Average Cost per kWh", description: "Total recorded cost divided by energy added, in the same currency per kilowatt-hour.")
    public var averageCostPerKWH: Double?

    @Property(title: "Most Recent Charge Location", description: "Where the most recent charge in the period happened.")
    public var lastChargeLocation: String?

    @Property(title: "Most Recent Charge Date", description: "When the most recent charge in the period ended.")
    public var lastChargeDate: Date?

    public var displayRepresentation: DisplayRepresentation {
        let subtitle = [
            String(localized: "\(sessionCount) sessions", bundle: .module, comment: "Session count in charging stats subtitle"),
            superchargerCount > 0 ? String(localized: "\(superchargerCount) Supercharger", bundle: .module, comment: "Supercharger session count in charging stats subtitle") : nil,
            formattedCost
        ].compactMap { $0 }.joined(separator: " • ")
        let energyText = "+\(FleetKitFormatting.energyKWH(totalEnergyAddedKWH))"
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: "\(energyText) (\(periodTitle))"),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }

    public init() {
        self.vehicleName = ""
        self.vin = ""
        self.periodTitle = ""
        self.sessionCount = 0
        self.superchargerCount = 0
        self.acSessionCount = 0
        self.totalEnergyAddedKWH = 0
        self.totalMilesAdded = 0
        self.totalCost = nil
        self.currency = nil
        self.averageCostPerKWH = nil
        self.lastChargeLocation = nil
        self.lastChargeDate = nil
    }

    public init(vehicle: FleetVehicleInfo, period: StatsPeriod, sessions: [FleetChargeInfo]) {
        self.vehicleName = vehicle.name
        self.vin = vehicle.vin
        self.periodTitle = period.displayTitle
        self.sessionCount = sessions.count
        let scCount = sessions.filter(\.isSupercharger).count
        self.superchargerCount = scCount
        self.acSessionCount = sessions.count - scCount

        let kwh = sessions.compactMap(\.energyAddedKWH).reduce(0, +)
        self.totalEnergyAddedKWH = kwh
        self.totalMilesAdded = sessions.compactMap(\.milesAdded).reduce(0, +)

        let priced = sessions.filter { $0.cost != nil }
        let currencies = Set(priced.compactMap(\.currency))
        // Tessie costs share the account currency. Teslascope can record a different
        // currency per session, so several unlabeled amounts cannot be safely combined.
        let unknownCurrency = priced.filter { $0.currency == nil && $0.cost != 0 }
        let canSum = currencies.count <= 1 && (unknownCurrency.isEmpty || currencies.isEmpty)
            && (unknownCurrency.count < 2 || !unknownCurrency.contains { $0.id.contains(":teslascope:") })
        let cost = canSum && !priced.isEmpty ? priced.compactMap(\.cost).reduce(0, +) : nil
        self.totalCost = cost
        self.currency = currencies.count == 1 ? currencies.first : nil
        self.averageCostPerKWH = kwh > 0.1 ? cost.map { $0 / kwh } : nil

        let latest = sessions.first
        self.lastChargeLocation = latest?.location
        self.lastChargeDate = latest?.endedAtDate ?? latest?.startedAtDate
    }

    public func spokenSummary(period: StatsPeriod) -> String {
        if sessionCount == 0 {
            return String(
                localized: "\(vehicleName) has no recorded charging sessions \(period.spokenLabel).",
                bundle: .module,
                comment: "Spoken charging stats when no charging sessions were recorded"
            )
        }

        let energyText = FleetKitFormatting.energyKWH(totalEnergyAddedKWH)
        let rangeAdded = FleetKitFormatting.distance(miles: totalMilesAdded, width: .wide)
        var sentences: [String] = [
            String(
                localized: "For \(vehicleName) \(period.spokenLabel): \(sessionCount) charging sessions added \(energyText) (about \(rangeAdded)).",
                bundle: .module,
                comment: "Spoken charging stats headline with session count, energy, and range added"
            )
        ]

        if superchargerCount > 0 && acSessionCount > 0 {
            sentences.append(
                String(
                    localized: "\(superchargerCount) Supercharger and \(acSessionCount) AC or home sessions.",
                    bundle: .module,
                    comment: "Spoken breakdown of Supercharger vs AC/home charging sessions"
                )
            )
        } else if superchargerCount > 0 {
            if superchargerCount == 1 {
                sentences.append(
                    String(
                        localized: "The charging session was at a Supercharger.",
                        bundle: .module,
                        comment: "Spoken note when the single charging session was at a Supercharger"
                    )
                )
            } else {
                sentences.append(
                    String(
                        localized: "All \(superchargerCount) sessions were at Superchargers.",
                        bundle: .module,
                        comment: "Spoken note when all charging sessions were at Superchargers"
                    )
                )
            }
        }

        if let formattedCost {
            if let perKWH = averageCostPerKWH {
                let perKWHText = formatChargeCost(perKWH, currency: currency)
                sentences.append(
                    String(
                        localized: "Total recorded cost was \(formattedCost) (\(perKWHText)/kWh).",
                        bundle: .module,
                        comment: "Spoken total charging cost with average cost per kWh"
                    )
                )
            } else {
                sentences.append(
                    String(
                        localized: "Total recorded cost was \(formattedCost).",
                        bundle: .module,
                        comment: "Spoken total charging cost"
                    )
                )
            }
        }

        return sentences.joined(separator: " ")
    }
}

/// Battery pack health, capacity retention, degradation, and pack telemetry summary.
public struct BatteryHealthEntity: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Battery Health & Pack Stats")

    @Property(title: "Vehicle Name", description: "The owner's name for the car these numbers are about.")
    public var vehicleName: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(title: "Battery Health (%)", description: "Usable battery capacity compared with a new pack, as a percent. 100 means like new.")
    public var healthPercent: Double?

    @Property(title: "Estimated Degradation (%)", description: "Capacity lost compared with a new pack, as a percent.")
    public var degradationPercent: Double?

    @Property(title: "Current Usable Capacity (kWh)", description: "How much energy a full charge holds today, in kilowatt-hours.")
    public var usableCapacityKWH: Double?

    @Property(title: "New Pack Capacity (kWh)", description: "How much energy the pack held when new, in kilowatt-hours.")
    public var originalCapacityKWH: Double?

    @Property(title: "Estimated Range at 100% (Miles)", description: "Estimated range on a full charge today, in miles.")
    public var maxRangeMiles: Double?

    @Property(title: "Current Energy Remaining (kWh)", description: "Energy in the battery right now, in kilowatt-hours.")
    public var energyRemainingKWH: Double?

    @Property(title: "Lifetime Energy Used (kWh)", description: "Total energy the car has used over its life, in kilowatt-hours.")
    public var lifetimeEnergyUsedKWH: Double?

    @Property(title: "Phantom Drain (%)", description: "Battery lost per day while parked, as a percent.")
    public var phantomDrainPercent: Double?

    @Property(title: "Pack Voltage (V)", description: "Current battery pack voltage, in volts.")
    public var packVoltage: Double?

    @Property(title: "Pack Current (A)", description: "Current flowing in or out of the pack, in amps. Negative while charging.")
    public var packCurrentAmps: Double?

    @Property(title: "Min Module Temperature (°F)", description: "Coolest battery module temperature, in degrees Fahrenheit.")
    public var moduleTempMinF: Double?

    @Property(title: "Max Module Temperature (°F)", description: "Warmest battery module temperature, in degrees Fahrenheit.")
    public var moduleTempMaxF: Double?

    @Property(title: "Energy Used Since Last Charge (kWh)", description: "Energy used since the last charge, in kilowatt-hours.")
    public var energyUsedSinceChargeKWH: Double?

    public var displayRepresentation: DisplayRepresentation {
        let titleText = healthPercent.map {
            let pct = FleetKitFormatting.percent($0, fractionLength: 1)
            return String(localized: "\(pct) Battery Health", bundle: .module, comment: "Battery health entity title with percentage")
        }
            ?? energyRemainingKWH.map {
                let kwh = FleetKitFormatting.energyKWH($0)
                return String(localized: "\(kwh) Remaining", bundle: .module, comment: "Battery stats entity title with remaining energy")
            }
            ?? String(localized: "\(vehicleName) Battery Stats", bundle: .module, comment: "Fallback battery stats entity title")
        let subtitle = [
            usableCapacityKWH.map {
                let kwh = FleetKitFormatting.energyKWH($0)
                return String(localized: "\(kwh) capacity", bundle: .module, comment: "Usable battery capacity in subtitle")
            },
            maxRangeMiles.map {
                let dist = FleetKitFormatting.distance(miles: $0)
                let fullPct = FleetKitFormatting.percent(100)
                return String(localized: "\(dist) at \(fullPct)", bundle: .module, comment: "Estimated full-charge range in subtitle")
            },
            degradationPercent.map {
                let pct = FleetKitFormatting.percent($0, fractionLength: 1)
                return String(localized: "\(pct) degradation", bundle: .module, comment: "Battery degradation percentage in subtitle")
            }
        ].compactMap { $0 }.joined(separator: " • ")
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: titleText),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }

    public init() {
        self.vehicleName = ""
        self.vin = ""
        self.healthPercent = nil
        self.degradationPercent = nil
        self.usableCapacityKWH = nil
        self.originalCapacityKWH = nil
        self.maxRangeMiles = nil
        self.energyRemainingKWH = nil
        self.lifetimeEnergyUsedKWH = nil
        self.phantomDrainPercent = nil
        self.packVoltage = nil
        self.packCurrentAmps = nil
        self.moduleTempMinF = nil
        self.moduleTempMaxF = nil
        self.energyUsedSinceChargeKWH = nil
    }

    public init(
        vehicle: FleetVehicleInfo,
        health: FleetBatteryHealthInfo,
        consumption: FleetConsumptionInfo? = nil
    ) {
        self.vehicleName = vehicle.name
        self.vin = vehicle.vin
        self.healthPercent = health.healthPercent
        self.degradationPercent = health.degradationPercent
        self.usableCapacityKWH = health.usableCapacityKWH
        self.originalCapacityKWH = health.originalCapacityKWH
        self.maxRangeMiles = health.maxRangeMiles ?? health.maxIdealRangeMiles
        self.energyRemainingKWH = health.energyRemainingKWH
        self.lifetimeEnergyUsedKWH = health.lifetimeEnergyUsedKWH
        self.phantomDrainPercent = health.phantomDrainPercent
        self.packVoltage = health.packVoltage
        self.packCurrentAmps = health.packCurrentAmps
        self.moduleTempMinF = health.moduleTempMinF
        self.moduleTempMaxF = health.moduleTempMaxF
        self.energyUsedSinceChargeKWH = consumption?.energyUsedKWH
    }

    public var spokenSummary: String {
        var sentences: [String] = []
        if let health = healthPercent {
            let healthPct = FleetKitFormatting.percent(health, fractionLength: 1)
            if let deg = degradationPercent {
                let degPct = FleetKitFormatting.percent(deg, fractionLength: 1)
                sentences.append(
                    String(
                        localized: "\(vehicleName)'s battery health is \(healthPct) (\(degPct) estimated degradation).",
                        bundle: .module,
                        comment: "Spoken battery health percentage with estimated degradation"
                    )
                )
            } else {
                sentences.append(
                    String(
                        localized: "\(vehicleName)'s battery health is \(healthPct).",
                        bundle: .module,
                        comment: "Spoken battery health percentage"
                    )
                )
            }
        }

        if let cap = usableCapacityKWH, let orig = originalCapacityKWH {
            let capNum = cap.formatted(.number.precision(.fractionLength(1)))
            let origKWH = FleetKitFormatting.energyKWH(orig)
            if let maxRange = maxRangeMiles {
                let rangeText = FleetKitFormatting.distance(miles: maxRange, width: .wide)
                sentences.append(
                    String(
                        localized: "Usable capacity is \(capNum) of \(origKWH) and estimated full-charge range is \(rangeText).",
                        bundle: .module,
                        comment: "Spoken usable vs original battery capacity and full-charge range"
                    )
                )
            } else {
                sentences.append(
                    String(
                        localized: "Usable capacity is \(capNum) of \(origKWH).",
                        bundle: .module,
                        comment: "Spoken usable vs original battery capacity"
                    )
                )
            }
        } else if let cap = usableCapacityKWH {
            let capKWH = FleetKitFormatting.energyKWH(cap)
            if let maxRange = maxRangeMiles {
                let rangeText = FleetKitFormatting.distance(miles: maxRange, width: .wide)
                sentences.append(
                    String(
                        localized: "Usable capacity is \(capKWH) and estimated full-charge range is \(rangeText).",
                        bundle: .module,
                        comment: "Spoken usable battery capacity and full-charge range"
                    )
                )
            } else {
                sentences.append(
                    String(
                        localized: "Usable capacity is \(capKWH).",
                        bundle: .module,
                        comment: "Spoken usable battery capacity"
                    )
                )
            }
        } else if let maxRange = maxRangeMiles {
            let rangeText = FleetKitFormatting.distance(miles: maxRange, width: .wide)
            sentences.append(
                String(
                    localized: "Estimated full-charge range is \(rangeText).",
                    bundle: .module,
                    comment: "Spoken estimated full-charge range"
                )
            )
        }

        if let remaining = energyRemainingKWH {
            let remKWH = FleetKitFormatting.energyKWH(remaining)
            sentences.append(
                String(
                    localized: "\(remKWH) currently in the pack.",
                    bundle: .module,
                    comment: "Spoken energy currently remaining in the battery pack"
                )
            )
        }
        if let lifetime = lifetimeEnergyUsedKWH {
            let lifeKWH = FleetKitFormatting.energyKWH(lifetime, fractionLength: 0)
            sentences.append(
                String(
                    localized: "\(lifeKWH) lifetime energy used.",
                    bundle: .module,
                    comment: "Spoken lifetime battery energy used"
                )
            )
        }
        if let drain = phantomDrainPercent {
            let drainPct = FleetKitFormatting.percent(drain, fractionLength: 1)
            sentences.append(
                String(
                    localized: "\(drainPct) phantom drain.",
                    bundle: .module,
                    comment: "Spoken phantom battery drain percentage"
                )
            )
        }

        if sentences.isEmpty {
            return String(
                localized: "Battery health measurements are not yet available for \(vehicleName).",
                bundle: .module,
                comment: "Spoken fallback when battery health telemetry is unavailable"
            )
        }
        return sentences.joined(separator: " ")
    }
}
