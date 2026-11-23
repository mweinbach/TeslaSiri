import AppIntents
import Foundation

/// Action for opening/unlocking or closing the motorized charge port door.
public enum ChargePortAction: String, AppEnum, Sendable {
    case open
    case close

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Charge Port Action")
    public static let caseDisplayRepresentations: [ChargePortAction: DisplayRepresentation] = [
        .open: DisplayRepresentation(title: "Open", subtitle: "Open and unlock the charge port"),
        .close: DisplayRepresentation(title: "Close", subtitle: "Close the motorized charge port door")
    ]
}

/// Starts charging a plugged-in Tesla vehicle. Shortcuts intent; Siri AI uses Control Car.
public struct StartChargingIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Start Tesla Charging"
    public static let description = IntentDescription(
        "Begins charging the Tesla's battery when the car is plugged in, up to its charge limit. Use when the user wants the car to charge now. Fails with a clear message if the car isn't plugged in.",
        searchKeywords: ["charge my car", "begin charging", "plug in"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account that should start charging. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Start charging \(\.$vehicle)")
        } otherwise: {
            Summary("Start charging my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Start charging", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(action: "charge_start", vin: resolved.vin, humanName: "starting charging")
            let summary = "Started charging \(resolved.name)."
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "charge_start", summary: summary)
            log.success("started charging \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Stops an active charging session on a Tesla vehicle after confirmation. Shortcuts intent; Siri AI uses Control Car.
public struct StopChargingIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Stop Tesla Charging"
    public static let description = IntentDescription(
        "Ends the battery charging session that's running on a plugged-in Tesla, after asking the user to confirm, so the cable can be unplugged or charging can wait. Doesn't affect climate. To turn off heating or air conditioning, use Turn Off Tesla Climate (or Control Car).",
        searchKeywords: ["stop charging", "end charge", "pause charging"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account that should stop charging. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Stop charging \(\.$vehicle)")
        } otherwise: {
            Summary("Stop charging my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Stop charging", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await confirmWithSafetyGate(dialog: IntentDialog("Stop charging \(resolved.name)?"))
            try await service.runControl(action: "charge_stop", vin: resolved.vin, humanName: "stopping charging")
            let summary = "Stopped charging \(resolved.name)."
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "charge_stop", summary: summary)
            log.success("stopped charging \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Opens/unlocks or closes the motorized charge port door on a Tesla vehicle. Shortcuts intent; Siri AI uses Control Car.
public struct SetChargePortIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Control Tesla Charge Port"
    public static let description = IntentDescription(
        "Opens (and unlocks) or closes the motorized charge port door on a Tesla vehicle. Opening the charge port asks for user confirmation."
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose charge port door should be opened or closed. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Action",
        description: "Choose open to open and unlock the charge port, or close to close the motorized charge port door.",
        default: .open
    )
    public var action: ChargePortAction

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("\(\.$action) charge port on \(\.$vehicle)")
        } otherwise: {
            Summary("\(\.$action) charge port on my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$action)) { vehicle, action in
            let verb = action == .open ? "Open" : "Close"
            return DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: verb, vehicle: vehicle, suffix: "charge port"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            if action == .open {
                try await confirmWithSafetyGate(dialog: IntentDialog("Open the charge port on \(resolved.name)?"))
            }
            let controlAction = action == .open ? "charge_port_door_open" : "charge_port_door_close"
            let humanName = action == .open ? "opening the charge port" : "closing the charge port"
            try await service.runControl(action: controlAction, vin: resolved.vin, humanName: humanName)
            let summary = action == .open
                ? "Opened the charge port on \(resolved.name)."
                : "Closed the charge port on \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: controlAction,
                appliedValue: action.rawValue,
                summary: summary
            )
            log.success("\(action.rawValue) charge port on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Enables or disables Sentry Mode camera security monitoring on a Tesla vehicle. Shortcuts intent; Siri AI uses Control Car.
public struct SetSentryModeIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Sentry Mode"
    public static let description = IntentDescription(
        "Turns Sentry Mode exterior camera security monitoring on or off on a Tesla vehicle. Turning Sentry Mode off prompts the user for confirmation."
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose Sentry Mode setting should change. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "On",
        description: "Set true to enable Sentry Mode security monitoring, or false to disable Sentry Mode (prompts for confirmation).",
        default: true
    )
    public var on: Bool

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Turn Sentry Mode \(\.$on) on \(\.$vehicle)")
        } otherwise: {
            Summary("Turn Sentry Mode \(\.$on) on my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$on)) { vehicle, on in
            let target = vehicle?.name ?? FleetIntentMetadata.myCar
            return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Turn Sentry Mode \(on ? "on" : "off") on \(target)"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            if !on {
                try await confirmWithSafetyGate(dialog: IntentDialog("Turn off Sentry Mode on \(resolved.name)?"))
            }
            try await service.runControl(
                action: "set_sentry_mode",
                vin: resolved.vin,
                params: ["on": .bool(on)],
                humanName: "setting Sentry Mode"
            )
            let summary = on ? "Sentry Mode is on for \(resolved.name)." : "Sentry Mode is off for \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_sentry_mode",
                appliedValue: on ? "on" : "off",
                summary: summary
            )
            log.success("Sentry Mode \(on ? "on" : "off") on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Composite Shortcuts climate intent using `CabinClimateSettings`. Siri AI uses Control Car.
public struct ConfigureCabinClimateIntent: AppIntent, LongRunningIntent {
    public static let title: LocalizedStringResource = "Configure Tesla Cabin Climate"
    public static let description = IntentDescription(
        "Warms up or cools down the user's car (or Tesla) in one step: cabin temperature, max defrost, seat heat, the steering wheel heater, Dog Mode, and Bioweapon Defense Mode. Turns climate on. Use when the user asks for more than one climate change, or to warm up, cool down, or precondition their car before leaving.",
        searchKeywords: ["precondition", "precondition my car", "warm up", "warm up my car", "cool down", "cool down my car", "defrost", "defrost my car", "heat", "AC", "air conditioning"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account to configure. Optional; omit to use the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Climate Settings",
        description: "Only the settings the user asked for; leave the others empty so they stay as they are. For example, \"warm it to 72 and heat my seat\" is 22 °C with driver seat heat 3."
    )
    public var settings: CabinClimateSettings

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Configure cabin climate in \(\.$vehicle) with \(\.$settings)")
        } otherwise: {
            Summary("Configure cabin climate in my car with \(\.$settings)")
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let scope = service.sessionScopeID
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let steps = settings.controlSteps(climateOn: nil, startWhenEmpty: true)
            let available = try await service.controlActions(for: resolved)
            if let unavailable = steps.first(where: { !available.supports($0.action) }) {
                throw FleetKitError.unsupportedAction(unavailable.label)
            }
            if settings.enablePetMode == false {
                try await confirmWithSafetyGate(dialog: IntentDialog("Turn off dog mode in \(resolved.name)?"))
            }

            let plan = await CarControlPlan.make(steps, service: service, vin: resolved.vin)
            let targetCelsius = settings.roundedTargetCelsius
            let outcome = try await performSandboxAwareBackgroundTask(
                description: "Configuring cabin climate in \(resolved.name)"
            ) {
                try await CarControlStepRunner.run(plan, service: service, vin: resolved.vin)
            }

            let detail = outcome.acceptedDetail
            let deliveryState = outcome.deliveryState
            let partialSummary = outcome.partialFailureSummary(vehicleName: resolved.name)
            let summary = partialSummary ?? deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: "apply: \(detail)",
                confirmed: "Configured \(resolved.name) (\(detail))."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "configure_cabin_climate",
                succeeded: outcome.failure == nil,
                deliveryState: deliveryState,
                appliedValue: detail,
                summary: summary
            )
            if let failure = outcome.failure {
                _ = log.failure(failure.error)
            } else {
                log.success("configured cabin climate on \(resolved.name): \(detail) (\(deliveryState.rawValue))")
            }
            let ranClimateStart = outcome.accepted.contains { $0.action == "auto_conditioning_start" }
            let climateRunning = plan.skippedRedundantStart || ranClimateStart
            let appliedTarget = outcome.accepted.contains { $0.action == "set_temps" } ? targetCelsius : nil
            return .result(
                value: result,
                dialog: IntentDialog("\(summary)"),
                snippetIntent: ClimateControlSnippetIntent(
                    vehicle: VehicleEntity(id: resolved.vin, name: resolved.name),
                    appliedSummary: deliveryState == .wakingVehicle || partialSummary != nil ? summary : detail,
                    scope: scope,
                    running: climateRunning ? true : nil,
                    targetCelsius: appliedTarget,
                    deliveryState: deliveryState,
                    confirmedStart: ranClimateStart,
                    existingStartAnchor: plan.existingStartAnchor
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Searches recent drives using synthesized `DriveFilterCriteria` (location substring,
/// minimum distance, and result cap).
@AppIntent(.tool)
public struct FindDrivesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Tesla Drives"
    public static let description = IntentDescription(
        "Lists the user's past Tesla drives by destination or starting place, date, distance, duration, or tag, sorted by most recent, longest, most energy, or most efficient. Searches the connected provider’s drive history, including drives too old for Spotlight. For one drive in detail, use the Get Tesla Drive Details tool.",
        searchKeywords: ["trip", "trips", "drive history", "where did I drive", "when did I go", "commute"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose drives should be searched. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Filter",
        description: "Only the conditions the user gave. For \"when did I last drive to the airport?\", set the destination to Airport and the maximum results to 1."
    )
    public var filter: DriveFilterCriteria

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Find drives for \(\.$vehicle) matching \(\.$filter)")
        } otherwise: {
            Summary("Find drives for my car matching \(\.$filter)")
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[DriveEntity]> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let maxResults = min(max(filter.maximumResults ?? 10, 1), 50)
            let normalizedTag = filter.tagQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDrives = try await service.drives(
                vin: resolved.vin,
                limit: 100,
                from: filter.startDate,
                to: filter.endDate,
                tag: normalizedTag
            )

            let generalLoc = filter.locationQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let startLoc = filter.startLocationQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let endLoc = filter.endLocationQuery?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let tagLower = normalizedTag?.lowercased()

            var matched = rawDrives.filter { drive in
                if let startDate = filter.startDate, drive.startedAtDate < startDate {
                    return false
                }
                if let endDate = filter.endDate, drive.startedAtDate > endDate {
                    return false
                }
                if let minMiles = filter.minimumDistanceMiles {
                    guard let distance = drive.distanceMiles, distance >= minMiles else {
                        return false
                    }
                }
                if let maxMiles = filter.maximumDistanceMiles {
                    guard let distance = drive.distanceMiles, distance <= maxMiles else {
                        return false
                    }
                }
                if let minDuration = filter.minimumDurationMinutes {
                    guard let duration = drive.durationMinutes, duration >= minDuration else {
                        return false
                    }
                }
                if let query = generalLoc, !query.isEmpty {
                    let startMatch = drive.startAddress?.lowercased().contains(query) == true
                    let endMatch = drive.endAddress?.lowercased().contains(query) == true
                    guard startMatch || endMatch else { return false }
                }
                if let startQuery = startLoc, !startQuery.isEmpty {
                    guard drive.startAddress?.lowercased().contains(startQuery) == true else {
                        return false
                    }
                }
                if let endQuery = endLoc, !endQuery.isEmpty {
                    guard drive.endAddress?.lowercased().contains(endQuery) == true else {
                        return false
                    }
                }
                if let tagQuery = tagLower, !tagQuery.isEmpty {
                    guard drive.tag?.lowercased().contains(tagQuery) == true else {
                        return false
                    }
                }
                return true
            }

            switch filter.sortBy ?? .mostRecent {
            case .mostRecent:
                break // Both live and demo history arrive newest first.
            case .longestDistance:
                matched.sort { ($0.distanceMiles ?? -1) > ($1.distanceMiles ?? -1) }
            case .longestDuration:
                matched.sort { ($0.durationMinutes ?? -1) > ($1.durationMinutes ?? -1) }
            case .highestEnergy:
                matched.sort { ($0.energyUsedKWH ?? -1) > ($1.energyUsedKWH ?? -1) }
            case .bestEfficiency:
                matched.sort { ($0.efficiencyWhPerMile ?? .infinity) < ($1.efficiencyWhPerMile ?? .infinity) }
            }

            let results = matched.prefix(maxResults).map(DriveEntity.init(info:))
            log.success("matched \(results.count) drive(s) for \(resolved.name)")

            let dialogText: String
            if results.isEmpty {
                dialogText = "No drives matched those criteria for \(resolved.name)."
            } else if results.count == 1, let only = results.first {
                dialogText = "Found 1 matching drive for \(resolved.name). \(only.spokenSummary(vehicleName: resolved.name))"
            } else if let top = results.first {
                let totalMiles = results.compactMap(\.distanceMiles).reduce(0, +)
                dialogText = String(
                    format: "Found %d matching drives for %@ totaling %.1f miles. Top match: %@",
                    results.count,
                    resolved.name,
                    totalMiles,
                    top.spokenSummary(vehicleName: resolved.name)
                )
            } else {
                dialogText = "Found \(results.count) matching drives for \(resolved.name)."
            }

            return .result(
                value: results,
                dialog: IntentDialog("\(dialogText)"),
                snippetIntent: DriveRouteSnippetIntent(
                    drives: results,
                    vehicleName: resolved.name,
                    sessionKey: "drive-search"
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Fetches and reads aloud software release notes for a Tesla vehicle's pending or installed firmware version.
@AppIntent(.tool)
public struct GetReleaseNotesIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Read Tesla Release Notes"
    public static let description = IntentDescription(
        "Reads aloud Tesla's release notes about what's new in the car's software: the release notes for the update waiting to install, or for the installed version when there's no update. Can read the notes for a specific version, or only the features about one topic, such as FSD or Navigation.",
        searchKeywords: ["what's new", "release notes", "patch notes", "changelog", "new features", "software update"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose release notes should be read. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Software Version",
        description: "A Tesla software version such as 2026.38.1. Leave empty for the pending update, or the installed version when there's no update."
    )
    public var version: String?

    @Parameter(
        title: "Feature Filter",
        description: "A word to keep only matching features, such as FSD, Autopilot, Dashcam, or Navigation. Leave empty to read all the notes."
    )
    public var featureQuery: String?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Read release notes for \(\.$vehicle)") {
                \.$version
                \.$featureQuery
            }
        } otherwise: {
            Summary("Read release notes for my car") {
                \.$version
                \.$featureQuery
            }
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Read release notes for", vehicle: vehicle))
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[ReleaseNoteEntity]> & ShowsSnippetView & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let explicitVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetVersion: String?
            if let explicitVersion, !explicitVersion.isEmpty {
                targetVersion = explicitVersion
            } else {
                let software = try await service.software(vin: resolved.vin)
                targetVersion = software.availableVersion ?? software.currentVersion
            }

            guard let targetVersion, !targetVersion.isEmpty else {
                return .result(
                    value: [],
                    dialog: IntentDialog("No software version was reported for \(resolved.name)."),
                    view: ReleaseNotesSnippetView(vehicleName: resolved.name, version: "Unknown", notes: [])
                )
            }

            let allNotes = try await service.releaseNotes(vin: resolved.vin, version: targetVersion)
                .map { ReleaseNoteEntity(info: $0, vin: resolved.vin, version: targetVersion) }

            let trimmedQuery = featureQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes: [ReleaseNoteEntity]
            if let trimmedQuery, !trimmedQuery.isEmpty {
                let candidateTerms = Self.expandedFeatureTerms(for: trimmedQuery)
                notes = allNotes.filter { note in
                    candidateTerms.contains { term in
                        note.title.localizedCaseInsensitiveContains(term)
                            || note.subtitle?.localizedCaseInsensitiveContains(term) == true
                            || note.details?.localizedCaseInsensitiveContains(term) == true
                    }
                }
            } else {
                notes = allNotes
            }

            log.success("returned \(notes.count) release note(s) for \(resolved.name) \(targetVersion)")
            let dialogText = ReleaseNoteEntity.spokenDigest(
                for: notes,
                version: targetVersion,
                vehicleName: resolved.name,
                featureQuery: trimmedQuery
            )
            return .result(
                value: notes,
                dialog: IntentDialog("\(dialogText)"),
                view: ReleaseNotesSnippetView(vehicleName: resolved.name, version: targetVersion, notes: notes)
            )
        } catch {
            throw log.failure(error)
        }
    }

    static func expandedFeatureTerms(for query: String) -> [String] {
        switch query.lowercased() {
        case "fsd":
            [query, "Full Self-Driving", "Full Self Driving"]
        case "autopilot", "ap":
            [query, "Autopilot", "Autosteer", "Full Self-Driving"]
        case "ac", "hvac":
            [query, "Climate", "Preconditioning", "Air Conditioning"]
        default:
            [query]
        }
    }
}

/// Closes all windows on a parked Tesla vehicle after confirmation. Shortcuts intent; Siri AI uses Control Car.
public struct CloseWindowsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Close Tesla Windows"
    public static let description = IntentDescription(
        "Rolls up all of the car's windows on a parked Tesla, after asking the user to confirm. Use when the car's windows are vented or left open, such as before rain or overnight.",
        searchKeywords: ["roll up windows", "close car windows"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose windows should be closed. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Close windows on \(\.$vehicle)")
        } otherwise: {
            Summary("Close my car windows")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Close", vehicle: vehicle, suffix: "windows"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await confirmWithSafetyGate(dialog: IntentDialog("Close windows on \(resolved.name)?"))
            try await service.runControl(
                action: "window_control",
                vin: resolved.vin,
                params: ["command": .string("close")],
                humanName: "closing windows"
            )
            let summary = "Closed windows on \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "window_control",
                appliedValue: "close",
                summary: summary
            )
            log.success("closed windows on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
