import AppIntents
import Foundation

/// Says and shows where the car is. This is the only tool that reports the car's location,
/// and it requires authentication, so the tools that run from the Lock Screen never reveal it.
@AppIntent(.tool)
public struct LocateCarIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Locate Car"
    public static let description = IntentDescription(
        "Finds where the user's car (or Tesla) is right now: the address or place it's parked near, shown on a map, or where it is and how fast it's going if someone is driving it. Use for \"where's my car?\" or \"where did I park?\". For past trips, use the Find Drives tool.",
        searchKeywords: ["where is my car", "where did I park", "find my car", "car location", "locate my Tesla", "parked", "map"]
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car to locate. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Locate \(\.$vehicle)")
        } otherwise: {
            Summary("Locate my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Locate \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for finding where a specific vehicle is."
                )
            } else {
                LocalizedStringResource(
                    "Locate my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for finding where the user's selected car is."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleStatusEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            // Lock state travels with the position so the card can show both.
            let snapshot = try await service.snapshot(for: resolved, topics: [.security], includesLocation: true)
            let allowNetwork = FleetIntentService.testingOverride == nil
            let address: String? = allowNetwork
                ? await FleetLocationNamer.address(latitude: snapshot.latitude, longitude: snapshot.longitude)
                : nil
            let entity = VehicleStatusEntity(snapshot: snapshot, vehicleName: resolved.name, locationAddress: address)
            let answer = entity.spokenAnswer(for: [], includingLocation: true)
            log.success("located \(resolved.name)")
            return .result(
                value: entity,
                dialog: IntentDialog(stringLiteral: answer),
                snippetIntent: VehicleStatusSnippetIntent(status: entity, topics: [.security], showsLocation: true)
            )
        } catch {
            throw log.failure(error)
        }
    }
}
