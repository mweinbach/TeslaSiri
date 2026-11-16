import AppIntents

/// Shared copy and helpers for vehicle-scoped App Intent metadata.
enum FleetIntentMetadata {
    static let vehicleParameterTitle: LocalizedStringResource = "Vehicle"
    static let vehicleParameterDescription: LocalizedStringResource =
        "The Tesla vehicle from the user's fleet account to target. Optional; omit to target the user's currently selected vehicle (or the first active vehicle on the account)."
    static let vehicleRequestDialog = IntentDialog("Which vehicle?")
    static let vehicleDisambiguationDialog = IntentDialog("Which vehicle?")
    static let myCar = "my car"
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

extension VehicleEntity {
    /// Siri/Shortcuts label for proactive suggestions when a vehicle is optional.
    static func predictionTitle(verb: String, vehicle: VehicleEntity?) -> LocalizedStringResource {
        if let vehicle {
            return LocalizedStringResource(stringLiteral: "\(verb) \(vehicle.name)")
        }
        return LocalizedStringResource(stringLiteral: "\(verb) \(FleetIntentMetadata.myCar)")
    }

    static func predictionTitle(verb: String, vehicle: VehicleEntity?, suffix: String) -> LocalizedStringResource {
        if let vehicle {
            return LocalizedStringResource(stringLiteral: "\(verb) \(vehicle.name) \(suffix)")
        }
        return LocalizedStringResource(stringLiteral: "\(verb) my car \(suffix)")
    }
}
