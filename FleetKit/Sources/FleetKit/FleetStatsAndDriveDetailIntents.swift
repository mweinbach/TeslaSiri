import AppIntents
import Foundation
import SwiftUI

/// Inspects a specific completed drive (or the most recent drive when omitted),
/// returning and reading aloud its full route, battery delta, energy efficiency,
/// speed, Autopilot miles, and temperature breakdown.
@AppIntent(.tool)
public struct GetDriveDetailsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Drive Details"
    public static let description = IntentDescription(
        "Gets everything recorded about one past Tesla drive: where it started and ended, when, how long and how far, battery at the start and end, energy used, efficiency, average and top speed, Autopilot miles, and temperatures. Leave the drive empty for the most recent drive, such as \"how was my last drive?\".",
        searchKeywords: ["Tesla", "last drive", "trip details", "how far did I drive", "efficiency", "Wh/mi"]
    )
    public static let isDiscoverable = true
    // Drive and charging history reveals addresses, including home.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account. Optional; omit to use the vehicle associated with the selected drive or the user's selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Drive",
        description: "The drive to describe, such as one the user is looking at or one found with Find Drives. Leave empty for the most recent drive.",
        requestValueDialog: IntentDialog("Which drive would you like details for?")
    )
    public var drive: DriveEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$drive, .hasAnyValue) {
            Summary("Get details for \(\.$drive)")
        } otherwise: {
            When(\.$vehicle, .hasAnyValue) {
                Summary("Get details for \(\.$vehicle)'s latest drive")
            } otherwise: {
                Summary("Get details for my car's latest drive")
            }
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Inspect \(vehicle.name) latest drive",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for inspecting the latest drive of a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Inspect my car latest drive",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for inspecting the latest drive of the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<DriveEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let summary: DriveEntity
            let vehicleName: String

            if let providedDrive = drive {
                let vehicles = try await service.vehicles()
                guard let matchingVehicle = vehicles.first(where: { $0.vin == providedDrive.vin }) else {
                    throw FleetKitError.api(
                        String(
                            localized: "That drive does not belong to an active vehicle on your account.",
                            bundle: .module,
                            comment: "Error message when a referenced drive belongs to an inactive or unknown vehicle."
                        )
                    )
                }
                vehicleName = matchingVehicle.name
                summary = providedDrive
            } else {
                let resolved = try await service.resolvedVehicle(vehicle?.id)
                vehicleName = resolved.name
                guard let latest = try await service.drives(vin: resolved.vin, limit: 1).first else {
                    throw FleetKitError.api(
                        String(
                            localized: "No completed drives were found for \(resolved.name).",
                            bundle: .module,
                            comment: "Error message when a vehicle has no completed drives."
                        )
                    )
                }
                let knownPlaces = FleetSharedPlaceStore(appGroup: service.appGroupIdentifier).places(forVIN: resolved.vin)
                summary = DriveEntity(info: latest, vehicleName: resolved.name, knownPlaces: knownPlaces)
            }

            let targetEntity = try await service.driveDetails(summary)
            let spoken = targetEntity.spokenSummary(vehicleName: vehicleName)
            log.success("inspected drive \(targetEntity.id) for \(vehicleName)")
            return .result(
                value: targetEntity,
                dialog: IntentDialog(stringLiteral: spoken),
                snippetIntent: DriveRouteSnippetIntent(
                    drives: [targetEntity],
                    vehicleName: vehicleName,
                    sessionKey: "drive-detail"
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Summarizes driving distance, duration, energy used, Wh/mi efficiency, Autopilot miles,
/// and since-last-charge consumption for a selectable time window.
@AppIntent(.tool)
public struct GetDrivingStatsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Driving Stats"
    public static let description = IntentDescription(
        "Summarizes Tesla road trips and driving efficiency: trip count, total miles, time behind the wheel, Wh/mi and mi/kWh efficiency, Autopilot distance, top speed, and parked energy drain.",
        searchKeywords: ["Tesla", "driving stats", "efficiency", "Wh/mi", "miles driven", "Autopilot miles", "how much did I drive"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose driving statistics should be calculated. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Period",
        description: "Time window to summarize: Since Last Charge, Today, Last 7 Days (default), Last 30 Days, or Last 90 Days.",
        default: .last7Days
    )
    public var period: StatsPeriod

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Get \(\.$period) driving stats for \(\.$vehicle)")
        } otherwise: {
            Summary("Get \(\.$period) driving stats for my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$period)) { vehicle, period in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Show \(period.displayTitle) driving stats for \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing driving stats over a period for a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Show \(period.displayTitle) driving stats for my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing driving stats over a period for the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<DrivingStatsEntity> & ShowsSnippetView & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let consumption: FleetConsumptionInfo?
            let effectiveStart: Date?
            if period == .sinceLastCharge {
                let fetched = try await service.consumptionSinceCharge(vin: resolved.vin)
                guard let lastCharge = fetched.lastChargeDate else {
                    throw FleetKitError.api(
                        String(
                            localized: "No completed charge was found to start this period.",
                            bundle: .module,
                            comment: "Error message when 'since last charge' stats are requested with no prior charge."
                        )
                    )
                }
                consumption = fetched
                effectiveStart = lastCharge
            } else {
                consumption = nil
                effectiveStart = period.startDate()
            }

            let rawDrives: [FleetDriveInfo]
            if service.usesTeslascope {
                rawDrives = try await service.drives(
                    vin: resolved.vin,
                    limit: .max,
                    from: effectiveStart,
                    requireCompleteRows: true
                )
            } else {
                // A single capped response undercounts a busy period, so walk the whole window.
                rawDrives = try await service.driveHistory(vin: resolved.vin, from: effectiveStart, maxPages: 10)
            }
            let filteredDrives: [FleetDriveInfo]
            if let effectiveStart {
                filteredDrives = rawDrives.filter { $0.startedAtDate >= effectiveStart }
            } else {
                filteredDrives = rawDrives
            }

            let stats = DrivingStatsEntity(
                vehicle: resolved,
                period: period,
                drives: filteredDrives,
                consumption: consumption
            )
            let spoken = stats.spokenSummary(period: period)
            log.success("driving stats (\(period.rawValue)) for \(resolved.name): \(stats.driveCount) drives")
            return .result(
                value: stats,
                dialog: IntentDialog(stringLiteral: spoken),
                view: DrivingStatsSnippetView(stats: stats)
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Summarizes charging sessions, kWh added, miles added, Supercharger vs home/AC split,
/// and total charging cost over a selectable period.
@AppIntent(.tool)
public struct GetChargingStatsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Charging Stats"
    public static let description = IntentDescription(
        "Summarizes Tesla plug-in electricity totals and costs: Supercharger versus home AC sessions, kWh added, range gained, recorded spend, and average price per kWh.",
        searchKeywords: ["Tesla", "charging stats", "charging cost", "how much did I spend charging", "Supercharger spending", "kWh added"]
    )
    public static let isDiscoverable = true
    // The card names the most recent charging location and totals what was spent.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose charging statistics should be calculated. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Period",
        description: "Time window to summarize: Since Last Charge (summarizes the most recent charge), Today, Last 7 Days, Last 30 Days (default), or Last 90 Days.",
        default: .last30Days
    )
    public var period: StatsPeriod

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Get \(\.$period) charging stats for \(\.$vehicle)")
        } otherwise: {
            Summary("Get \(\.$period) charging stats for my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$period)) { vehicle, period in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Show \(period.displayTitle) charging stats for \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing charging stats over a period for a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Show \(period.displayTitle) charging stats for my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing charging stats over a period for the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<ChargingStatsEntity> & ShowsSnippetView & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let sessions: [FleetChargeInfo]
            if period == .sinceLastCharge {
                sessions = try await service.charges(vin: resolved.vin, limit: 1)
            } else {
                let start = period.startDate()
                let raw: [FleetChargeInfo]
                if service.usesTeslascope {
                    raw = try await service.charges(
                        vin: resolved.vin, limit: .max, from: start,
                        requireCompleteRows: true
                    )
                } else {
                    // A single capped response undercounts a busy period, so walk the whole window.
                    raw = try await service.chargeHistory(vin: resolved.vin, from: start, maxPages: 10)
                }
                if let start {
                    sessions = raw.filter { $0.startedAtDate >= start }
                } else {
                    sessions = raw
                }
            }

            let stats = ChargingStatsEntity(vehicle: resolved, period: period, sessions: sessions)
            let spoken = stats.spokenSummary(period: period)
            log.success("charging stats (\(period.rawValue)) for \(resolved.name): \(stats.sessionCount) sessions")
            return .result(
                value: stats,
                dialog: IntentDialog(stringLiteral: spoken),
                view: ChargingStatsSnippetView(stats: stats)
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Lists and filters recent completed charging sessions (for example Supercharger stops
/// or charges at a specific location).
@AppIntent(.tool)
public struct GetRecentChargesIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Charging History"
    public static let description = IntentDescription(
        "Lists the user's past Tesla charging sessions, newest first, optionally only Superchargers or only AC, at a place (including saved nicknames), or within dates. Add a date range for older history. For one session in detail, use the Get Charge Details tool; for totals, the Get Charging Stats tool.",
        searchKeywords: ["Tesla", "charges", "charging sessions", "Supercharger stops", "home charging", "charging log"]
    )
    public static let isDiscoverable = true
    // Drive and charging history reveals addresses, including home.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose charging history should be searched. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Location Filter",
        description: "Text to match against where the car charged, such as Kettleman, Home, or Mountain View. Leave empty for every location."
    )
    public var locationQuery: String?

    @Parameter(
        title: "From",
        description: "Earliest charge start to include, in the user's time zone. For \"last week\" use 7 days ago. Leave empty for no lower limit."
    )
    public var startDate: Date?

    @Parameter(
        title: "To",
        description: "Latest charge start to include, in the user's time zone. Leave empty for up to now."
    )
    public var endDate: Date?

    @Parameter(
        title: "Superchargers Only",
        description: "true for Supercharger sessions only, false for AC sessions only (home or destination chargers). Leave empty for both."
    )
    public var superchargersOnly: Bool?

    @Parameter(
        title: "Count",
        description: "How many sessions to return, from 1 to 25. \"My last charge\" is 1.",
        default: 5,
        inclusiveRange: (1, 25)
    )
    public var count: Int

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Show \(\.$count) recent charges for \(\.$vehicle)") {
                \.$locationQuery
                \.$superchargersOnly
                \.$startDate
                \.$endDate
            }
        } otherwise: {
            Summary("Show \(\.$count) recent charges for my car") {
                \.$locationQuery
                \.$superchargersOnly
                \.$startDate
                \.$endDate
            }
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Show recent charges for \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing recent charging sessions for a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Show recent charges for my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing recent charging sessions for the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[ChargeSessionEntity]> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let knownPlaces = FleetSharedPlaceStore(appGroup: service.appGroupIdentifier).places(forVIN: resolved.vin)
            let clamped = min(max(count, 1), 25)
            let trimmedLoc = locationQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasFilter = superchargersOnly != nil || !(trimmedLoc ?? "").isEmpty

            let matches: (FleetChargeInfo) -> Bool = { session in
                if let scOnly = self.superchargersOnly, session.isSupercharger != scOnly { return false }
                if let startDate = self.startDate, session.startedAtDate < startDate { return false }
                if let endDate = self.endDate, session.startedAtDate > endDate { return false }
                if let loc = trimmedLoc, !loc.isEmpty {
                    guard FleetSharedPlaceStore.matches(
                        query: loc, address: session.location,
                        latitude: session.latitude, longitude: session.longitude, in: knownPlaces
                    ) else { return false }
                }
                return true
            }

            let raw: [FleetChargeInfo]
            if hasFilter {
                raw = try await service.chargeHistory(
                    vin: resolved.vin,
                    from: startDate,
                    to: endDate,
                    maxPages: FleetIntentService.chargeHistoryMaxPages
                ) { collected in
                    collected.lazy.filter(matches).prefix(clamped).count >= clamped
                }
            } else {
                raw = try await service.charges(
                    vin: resolved.vin,
                    limit: max(clamped, 25),
                    from: startDate,
                    to: endDate
                )
            }
            let results: [ChargeSessionEntity] = raw.lazy.filter(matches).prefix(clamped).map {
                ChargeSessionEntity(info: $0, vehicleName: resolved.name, knownPlaces: knownPlaces)
            }
            log.success("returned \(results.count) charge session(s) for \(resolved.name)")

            let dialogText: String
            if results.isEmpty {
                dialogText = String(
                    localized: "No matching charging sessions were found for \(resolved.name).",
                    bundle: .module,
                    comment: "Siri answer when a charging history search returns no sessions."
                )
            } else if results.count == 1, let only = results.first {
                dialogText = only.spokenSummary(vehicleName: resolved.name)
            } else if let latest = results.first {
                let totalKWH = results.compactMap(\.energyAddedKWH).reduce(0, +)
                let energyText = FleetKitFormatting.energyKWH(totalKWH, fractionLength: 1)
                let latestSummary = latest.spokenSummary(vehicleName: resolved.name)
                dialogText = String(
                    localized: "Found \(results.count) charging sessions for \(resolved.name) adding \(energyText) total. Most recent: \(latestSummary)",
                    bundle: .module,
                    comment: "Siri answer summarizing multiple charging sessions, total energy added, and most recent session."
                )
            } else {
                dialogText = String(
                    localized: "Found \(results.count) charging sessions for \(resolved.name).",
                    bundle: .module,
                    comment: "Fallback Siri answer reporting charging session count."
                )
            }

            return .result(
                value: results,
                dialog: IntentDialog(stringLiteral: dialogText),
                snippetIntent: ChargeSessionSnippetIntent(
                    sessions: results,
                    vehicleName: resolved.name,
                    sessionKey: "charge-list"
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Reads battery pack health %, degradation %, usable vs original kWh capacity,
/// estimated 100% range, lifetime energy used, phantom drain, and pack voltage/temp.
@AppIntent(.tool)
public struct GetBatteryHealthIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Battery Health & Stats"
    public static let description = IntentDescription(
        "Reads a Tesla vehicle's battery health percentage, estimated degradation percentage, current usable capacity vs original new-pack capacity in kWh, estimated full-charge range at 100%, current energy remaining in kWh, lifetime energy used, phantom drain percentage, and pack voltage and module temperatures.",
        searchKeywords: ["Tesla", "battery health", "battery degradation", "battery capacity", "phantom drain", "pack health", "full charge range"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose battery health and pack statistics should be checked. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Check battery health for \(\.$vehicle)")
        } otherwise: {
            Summary("Check my car battery health")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Check \(vehicle.name) battery health",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking battery health on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Check my car battery health",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking battery health on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<BatteryHealthEntity> & ShowsSnippetView & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let health = try await service.batteryHealth(vin: resolved.vin)
            let consumption = try? await service.consumptionSinceCharge(vin: resolved.vin)
            let entity = BatteryHealthEntity(vehicle: resolved, health: health, consumption: consumption)
            let spoken = entity.spokenSummary
            log.success("battery health for \(resolved.name): \(entity.healthPercent.map { String(format: "%.1f%%", $0) } ?? "n/a")")
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: spoken),
                view: BatteryHealthSnippetView(battery: entity)
            )
        } catch {
            throw log.failure(error)
        }
    }
}
