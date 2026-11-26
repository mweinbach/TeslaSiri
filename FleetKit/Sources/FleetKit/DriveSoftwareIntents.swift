import AppIntents
import SwiftUI

/// Returns a list of recent drives.
/// Shortcuts only. Siri uses the Find Drives tool for drive lists.
public struct GetRecentDrivesIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Recent Drives"
    public static let description = IntentDescription(
        "Lists the most recent completed drives for a Tesla vehicle, including start/end addresses, distance in miles, duration in minutes, average and max speed, and energy consumed in kWh. To filter drives by place, date, or distance, use Find Drives."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose drive history should be listed. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Count",
        description: "Maximum number of recent completed drives to return, from 1 to 25 (defaults to 5).",
        default: 5,
        inclusiveRange: (1, 25)
    )
    public var count: Int

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Show \(\.$count) recent drives for \(\.$vehicle)")
        } otherwise: {
            Summary("Show \(\.$count) recent drives for my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$count)) { vehicle, count in
            let target = vehicle?.name ?? FleetIntentMetadata.myCar
            return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Show \(count) recent drives for \(target)"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[DriveEntity]> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let clampedCount = min(max(count, 1), 25)
            let drives = try await service.drives(vin: resolved.vin, limit: clampedCount).map(DriveEntity.init(info:))
            log.success("returned \(drives.count) drive(s) for \(resolved.name)")
            let dialogText = drives.isEmpty
                ? "No recent drives were found for \(resolved.name)."
                : "Found \(drives.count) recent drive\(drives.count == 1 ? "" : "s") for \(resolved.name)."
            return .result(
                value: drives,
                dialog: IntentDialog("\(dialogText)"),
                snippetIntent: DriveRouteSnippetIntent(
                    drives: drives,
                    vehicleName: resolved.name,
                    sessionKey: "recent-drives"
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shows the most recent drive with a snippet. Shortcuts only;
/// Siri uses the Get Drive Details tool, which defaults to the latest drive.
public struct GetLastDriveIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Last Drive"
    public static let description = IntentDescription(
        "Fetches the single most recent completed drive for a Tesla vehicle, returning its distance, duration, route addresses, speed, energy used, and a rich visual summary."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose most recent drive should be fetched. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Show \(\.$vehicle) last drive")
        } otherwise: {
            Summary("Show my car last drive")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Show", vehicle: vehicle, suffix: "last drive"))
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<DriveEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            guard let last = try await service.drives(vin: resolved.vin, limit: 1).first else {
                throw FleetKitError.api("No recent drives were found.")
            }
            let entity = DriveEntity(info: last)
            log.success("last drive for \(resolved.name): \(entity.distanceText)")
            let spoken = entity.spokenSummary(vehicleName: resolved.name)
            return .result(
                value: entity,
                dialog: IntentDialog("\(spoken)"),
                snippetIntent: DriveRouteSnippetIntent(
                    drives: [entity],
                    vehicleName: resolved.name,
                    sessionKey: "last-drive"
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shows the software update status with a snippet. Doubles as the
/// "check install status" intent (reports download/install progress).
@AppIntent(.tool)
public struct GetSoftwareStatusIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Check Software Update"
    public static let description = IntentDescription(
        "Checks whether the car's Tesla firmware has a software update (read-only): the installed version, any newer version, and whether it's downloading (with progress), ready to install, scheduled, or installing, plus how long the install takes. To hear what's new, use the Read Release Notes tool. To install, use the Install Software Update tool.",
        searchKeywords: ["Tesla", "firmware", "update", "new version", "software version", "is there an update"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose software status should be checked. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Check software on \(\.$vehicle)")
        } otherwise: {
            Summary("Check software on my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Check software on", vehicle: vehicle))
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<SoftwareUpdateEntity> & ShowsSnippetView & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let info = try await service.software(vin: resolved.vin)
            let entity = SoftwareUpdateEntity(info: info, vin: resolved.vin, vehicleName: resolved.name)
            log.success("\(resolved.name): \(entity.headline)")
            return .result(
                value: entity,
                dialog: IntentDialog("\(entity.spokenStatus)"),
                view: SoftwareSnippetView(software: entity)
            )
        } catch {
            throw log.failure(error)
        }
    }
}
