import AppIntents
import Foundation

// Convenience controls from the Fleet controls registry: `flash_lights`,
// `honk_horn`, and `navigation_request`. All run immediately.

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct FlashLightsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Flash Tesla Lights"
    public static let description = IntentDescription(
        "Briefly flashes the exterior headlights on a Tesla vehicle to help locate it in a parking lot or garage. Omit the vehicle parameter to target the user's selected car."
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose headlights should flash. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Flash \(\.$vehicle) lights")
        } otherwise: {
            Summary("Flash my car lights")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Flash", vehicle: vehicle, suffix: "lights"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(action: "flash_lights", vin: resolved.vin, humanName: "flashing the lights")
            let summary = "Flashing \(resolved.name)'s lights."
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "flash_lights", summary: summary)
            log.success("flashed lights on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts and snippet button intent. Siri AI uses the Control Car tool.
public struct HonkHornIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Honk Tesla Horn"
    public static let description = IntentDescription(
        "Briefly honks the horn on a Tesla vehicle to help locate it audibly. Omit the vehicle parameter to target the user's selected car."
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose horn should honk. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Honk \(\.$vehicle) horn")
        } otherwise: {
            Summary("Honk my car horn")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Honk", vehicle: vehicle, suffix: "horn"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(action: "honk_horn", vin: resolved.vin, humanName: "honking the horn")
            let summary = "Honking \(resolved.name)'s horn."
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "honk_horn", summary: summary)
            log.success("honked horn on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

@AppIntent(.tool)
public struct SendNavigationIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Send Destination to Tesla"
    public static let description = IntentDescription(
        "Sends a street address, place name with city, map link, or coordinates to the car's touchscreen navigation. Doesn't open Maps on this device. Use for standalone navigation; use Control Car when combining a destination with climate or other vehicle changes.",
        searchKeywords: ["navigate", "directions", "send address", "route", "take me to", "drive to"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account that should receive the navigation destination. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Destination",
        description: "Where to go, as specific as possible: a full street address, a place name with its city such as \"Blue Bottle Coffee, Oakland\", a map link, or \"37.7749,-122.4194\".",
        requestValueDialog: IntentDialog("Where to?"),
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    public var destination: String

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Send \(\.$destination) to \(\.$vehicle)")
        } otherwise: {
            Summary("Send \(\.$destination) to my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Send navigation to", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw FleetKitError.api("Tell me where to send \(resolved.name).")
            }
            // Tessie's share command accepts an address, coordinates, or URL as a
            // plain value. The locale (e.g. "en-US") helps it resolve addresses.
            let locale = Locale.current.identifier(.bcp47)
            try await service.runControl(
                action: "navigation_request",
                vin: resolved.vin,
                params: ["value": .string(trimmed), "locale": .string(locale)],
                humanName: "sending the destination"
            )
            let summary = "Sent \(trimmed) to \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "navigation_request",
                appliedValue: trimmed,
                summary: summary
            )
            log.success("sent destination to \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
