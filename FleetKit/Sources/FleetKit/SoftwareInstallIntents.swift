import AppIntents

/// Schedules the available software update. Conforms to `LongRunningIntent`
/// since kicking off and confirming the install can take a while.
@AppIntent(.tool)
public struct InstallSoftwareUpdateIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Install Tesla Software Update"
    public static let description = IntentDescription(
        "Installs the software update that has finished downloading to the user's Tesla, now or at a time the user picks, after asking the user to confirm. The car can't be driven while it installs, usually 20 to 40 minutes. If the update is still downloading or already installing, this tool says so instead of installing.",
        searchKeywords: ["update my car", "install update", "firmware", "schedule update"]
    )
    public static let isDiscoverable = true

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
        When(\.$vehicle, .hasAnyValue) {
            Summary("Update \(\.$vehicle) at \(\.$startTime)")
        } otherwise: {
            Summary("Update my car at \(\.$startTime)")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Update", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let info = try await service.software(vin: resolved.vin)
            guard info.updateAvailable || info.installable else {
                let summary = "\(resolved.name) is already up to date."
                let result = VehicleCommandResultEntity(
                    vehicle: resolved,
                    action: "schedule_software_update",
                    succeeded: false,
                    appliedValue: info.currentVersion,
                    summary: summary
                )
                log.success("\(resolved.name) already up to date")
                return .result(value: result, dialog: IntentDialog("\(summary)"))
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
                return .result(value: result, dialog: IntentDialog("\(status)"))
            }

            let offsetSec = startTime.map { max(Int($0.timeIntervalSinceNow.rounded()), 0) } ?? 0
            try service.checkSoftwareCommand(for: resolved, installAfter: offsetSec)
            let whenText = offsetSec > 60
                ? " at \((startTime ?? .now).formatted(date: .omitted, time: .shortened))"
                : " now"
            let version = info.availableVersion.map { " \($0)" } ?? ""
            try await confirmWithSafetyGate(
                dialog: IntentDialog("Install software update\(version) on \(resolved.name)\(whenText)? The car can't be driven while it installs.")
            )

            try await performSandboxAwareBackgroundTask {
                try await service.installSoftwareUpdate(vin: resolved.vin, offsetSec: offsetSec)
            }
            let summary = offsetSec > 60
                ? "\(resolved.name) will install the update\(whenText)."
                : "Starting the software update on \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "schedule_software_update",
                appliedValue: info.availableVersion,
                summary: summary
            )
            log.success("started software update on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Cancels a scheduled software update.
@AppIntent(.tool)
public struct CancelSoftwareUpdateIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Cancel Tesla Software Update"
    public static let description = IntentDescription(
        "Cancels a scheduled software update on the user's Tesla before it starts installing, after asking the user to confirm. It can't stop an install that's already running."
    )
    public static let isDiscoverable = true

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
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Cancel update on", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try service.checkSoftwareCommand(for: resolved, installAfter: nil)
            try await confirmWithSafetyGate(dialog: IntentDialog("Cancel the software update on \(resolved.name)?"))
            try await service.cancelSoftwareUpdate(vin: resolved.vin)
            let summary = "Canceled the software update on \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "cancel_software_update",
                summary: summary
            )
            log.success("canceled software update on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
