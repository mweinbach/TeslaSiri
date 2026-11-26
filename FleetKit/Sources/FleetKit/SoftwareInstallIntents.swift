import AppIntents

/// Schedules the available software update. Conforms to `LongRunningIntent`
/// since kicking off and confirming the install can take a while.
@AppIntent(.tool)
public struct InstallSoftwareUpdateIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Install Software Update"
    public static let description = IntentDescription(
        "Installs the software update that has finished downloading to the user's Tesla, now or at a time the user picks, after asking the user to confirm. The car can't be driven while it installs, usually 20 to 40 minutes. If the update is still downloading or already installing, this tool says so instead of installing.",
        searchKeywords: ["Tesla", "update my car", "install update", "firmware", "schedule update"]
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account on which to install the available software update. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Start Time",
        description: "When to start installing, such as tonight at 2 AM, in the user's time zone. Leave empty to start right away."
    )
    public var startTime: Date?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$startTime, .hasAnyValue) {
            When(\.$vehicle, .hasAnyValue) {
                Summary("Update \(\.$vehicle) at \(\.$startTime)")
            } otherwise: {
                Summary("Update my car at \(\.$startTime)")
            }
        } otherwise: {
            When(\.$vehicle, .hasAnyValue) {
                Summary("Update \(\.$vehicle)") {
                    \.$startTime
                }
            } otherwise: {
                Summary("Update my car") {
                    \.$startTime
                }
            }
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Update \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for installing a software update on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Update my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for installing a software update on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let info = try await service.software(vin: resolved.vin)
            guard info.updateAvailable || info.installable else {
                let summary = String(
                    localized: "\(resolved.name) is already up to date.",
                    bundle: .module,
                    comment: "Siri response when no software update is available."
                )
                let result = VehicleCommandResultEntity(
                    vehicle: resolved,
                    action: "schedule_software_update",
                    succeeded: false,
                    appliedValue: info.currentVersion,
                    summary: summary
                )
                log.success("\(resolved.name) already up to date")
                return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
            }

            guard info.installable else {
                // Downloading, waiting for Wi-Fi, or already installing: report instead of failing.
                let status = SoftwareUpdateEntity(info: info, vin: resolved.vin, vehicleName: resolved.name).spokenStatus
                let result = VehicleCommandResultEntity(
                    vehicle: resolved,
                    action: "schedule_software_update",
                    succeeded: false,
                    appliedValue: info.availableVersion,
                    summary: status
                )
                log.success("\(resolved.name) update not installable yet (\(info.status ?? "unknown"))")
                return .result(value: result, dialog: IntentDialog(stringLiteral: status))
            }

            let offsetSec = startTime.map { max(Int($0.timeIntervalSinceNow.rounded()), 0) } ?? 0
            try service.checkSoftwareCommand(for: resolved, installAfter: offsetSec)
            let isScheduled = offsetSec > 60
            let scheduledTime = (startTime ?? .now).formatted(date: .omitted, time: .shortened)
            let confirmResource: LocalizedStringResource = switch (info.availableVersion, isScheduled) {
            case let (version?, true):
                LocalizedStringResource(
                    "Install software update \(version) on \(resolved.name) at \(scheduledTime)? The car can't be driven while it installs.",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Confirmation prompt before scheduling a named software update version for a future time."
                )
            case let (version?, false):
                LocalizedStringResource(
                    "Install software update \(version) on \(resolved.name) now? The car can't be driven while it installs.",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Confirmation prompt before installing a named software update version immediately."
                )
            case (nil, true):
                LocalizedStringResource(
                    "Install software update on \(resolved.name) at \(scheduledTime)? The car can't be driven while it installs.",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Confirmation prompt before scheduling a software update for a future time."
                )
            case (nil, false):
                LocalizedStringResource(
                    "Install software update on \(resolved.name) now? The car can't be driven while it installs.",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Confirmation prompt before installing a software update immediately."
                )
            }
            try await confirmWithSafetyGate(dialog: IntentDialog(confirmResource))

            try await performSandboxAwareBackgroundTask(
                description: String(
                    localized: "Scheduling software update on \(resolved.name)",
                    bundle: .module,
                    comment: "Progress label while scheduling a software update."
                )
            ) {
                try await service.installSoftwareUpdate(vin: resolved.vin, offsetSec: offsetSec)
            }
            let summary = isScheduled
                ? String(
                    localized: "\(resolved.name) will install the update at \(scheduledTime).",
                    bundle: .module,
                    comment: "Siri confirmation after scheduling a software update for a later time."
                )
                : String(
                    localized: "Starting the software update on \(resolved.name).",
                    bundle: .module,
                    comment: "Siri confirmation after starting a software update immediately."
                )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "schedule_software_update",
                appliedValue: info.availableVersion,
                summary: summary
            )
            log.success("started software update on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Cancels a scheduled software update.
@AppIntent(.tool)
public struct CancelSoftwareUpdateIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Cancel Software Update"
    public static let description = IntentDescription(
        "Cancels a scheduled software update on the user's Tesla before it starts installing, after asking the user to confirm. It can't stop an install that's already running.",
        searchKeywords: ["Tesla", "cancel update", "stop update", "abort software update", "cancel firmware update"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose scheduled software update should be canceled. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Cancel update on \(\.$vehicle)")
        } otherwise: {
            Summary("Cancel update on my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Cancel update on \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for canceling a software update on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Cancel update on my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for canceling a software update on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try service.checkSoftwareCommand(for: resolved, installAfter: nil)
            try await confirmWithSafetyGate(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Cancel the software update on \(resolved.name)?",
                        bundle: FleetKitLocalization.bundleDescription,
                        comment: "Confirmation prompt before canceling a scheduled software update."
                    )
                )
            )
            try await service.cancelSoftwareUpdate(vin: resolved.vin)
            let summary = String(
                localized: "Canceled the software update on \(resolved.name).",
                bundle: .module,
                comment: "Siri confirmation after canceling a scheduled software update."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "cancel_software_update",
                summary: summary
            )
            log.success("canceled software update on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}
