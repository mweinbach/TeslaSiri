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
    // Drive and charging history reveals addresses, including home.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Show \(count) recent drives for \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing recent drives for a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Show \(count) recent drives for my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing recent drives for the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[DriveEntity]> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let clampedCount = min(max(count, 1), 25)
            let drives = try await service.drives(vin: resolved.vin, limit: clampedCount).map { DriveEntity(info: $0, vehicleName: resolved.name) }
            log.success("returned \(drives.count) drive(s) for \(resolved.name)")
            let dialogText = drives.isEmpty
                ? String(localized: "No recent drives were found for \(resolved.name).", bundle: .module, comment: "Siri answer when a vehicle has no recent drives.")
                : String(localized: "Found \(drives.count) recent drives for \(resolved.name).", bundle: .module, comment: "Siri answer reporting how many recent drives were found.")
            return .result(
                value: drives,
                dialog: IntentDialog(stringLiteral: dialogText),
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
    // Drive and charging history reveals addresses, including home.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Show \(vehicle.name) last drive",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing the last drive for a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Show my car last drive",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for showing the last drive for the user's selected car."
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
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            guard let last = try await service.drives(vin: resolved.vin, limit: 1).first else {
                throw FleetKitError.api(
                    String(
                        localized: "No recent drives were found.",
                        bundle: .module,
                        comment: "Error message when no completed drives exist."
                    )
                )
            }
            let entity = DriveEntity(info: last, vehicleName: resolved.name)
            log.success("last drive for \(resolved.name): \(entity.distanceText)")
            let spoken = entity.spokenSummary(vehicleName: resolved.name)
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: spoken),
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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Check software on \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking software updates on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Check software on my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for checking software updates on the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
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
                dialog: IntentDialog(stringLiteral: entity.spokenStatus),
                view: SoftwareSnippetView(software: entity)
            )
        } catch {
            throw log.failure(error)
        }
    }
}
