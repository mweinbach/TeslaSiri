import AppIntents

/// Shared copy and helpers for vehicle-scoped App Intent metadata.
enum FleetIntentMetadata {
    static let vehicleParameterTitle = LocalizedStringResource(
        "Vehicle",
        bundle: FleetKitLocalization.bundleDescription,
        comment: "Title for the vehicle parameter across Siri intents."
    )
    static let vehicleParameterDescription = LocalizedStringResource(
        "The Tesla vehicle from the user's fleet account to target. Optional; omit to target the user's currently selected vehicle (or the first active vehicle on the account).",
        bundle: FleetKitLocalization.bundleDescription,
        comment: "Description for the optional vehicle parameter across Siri intents."
    )
    static let vehicleRequestDialog = IntentDialog(
        LocalizedStringResource(
            "Which vehicle?",
            bundle: FleetKitLocalization.bundleDescription,
            comment: "Prompt asking the user to choose a vehicle."
        )
    )
    static let vehicleDisambiguationDialog = IntentDialog(
        LocalizedStringResource(
            "Which vehicle?",
            bundle: FleetKitLocalization.bundleDescription,
            comment: "Disambiguation prompt asking the user to pick among multiple vehicles."
        )
    )
}

/// Loads vehicles from the Fleet API for App Shortcut parameter pickers and
/// defaults to the app’s currently selected VIN.
public struct SelectedVehicleOptionsProvider: DynamicOptionsProvider {
    public init() {}

    public func results() async throws -> [VehicleEntity] {
        try await VehicleEntity.defaultQuery.allEntities()
    }

    public func defaultResult() async -> VehicleEntity? {
        try? await results().first
    }
}
