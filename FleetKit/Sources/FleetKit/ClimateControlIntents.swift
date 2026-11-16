import AppIntents
import Foundation

// Climate controls from the Fleet controls registry: `auto_conditioning_stop`,
// `set_temps`, `remote_defrost`, `set_pet_mode`, and `set_bioweapon_mode`.
//
// Confirmation policy: climate changes run immediately, except turning dog
// mode OFF, which prompts because a pet may be relying on it.

@AppIntent(.tool)
public struct StopClimateIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Turn Off Tesla Climate"
    public static let description = IntentDescription(
        "Turns off cabin heating and air conditioning in the user's car (or Tesla), such as after preconditioning. Doesn't affect charging. Use the Stop Tesla Charging tool to end a charging session.",
        searchKeywords: ["turn off AC", "turn off heat", "stop preconditioning", "stop car climate", "turn off car climate"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account whose climate control should be turned off. Optional; omit to use the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Stop climate in \(\.$vehicle)")
        } otherwise: {
            Summary("Stop climate in my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Stop climate in", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let scope = service.sessionScopeID
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(action: "auto_conditioning_stop", vin: resolved.vin, humanName: "stopping climate")
            let summary = "Climate is turning off in \(resolved.name)."
            let result = VehicleCommandResultEntity(vehicle: resolved, action: "auto_conditioning_stop", summary: summary)
            log.success("stopped climate in \(resolved.name)")
            return .result(
                value: result,
                dialog: IntentDialog("\(summary)"),
                snippetIntent: ClimateControlSnippetIntent(
                    vehicle: VehicleEntity(id: resolved.vin, name: resolved.name),
                    appliedSummary: summary, scope: scope, running: false
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

@AppIntent(.tool)
public struct SetCabinTemperatureIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Car Temperature"
    public static let description = IntentDescription(
        "Starts cabin climate and sets the driver and passenger HVAC temperature in the user's car or Tesla (15°C–28°C / 59°F–82.4°F). Use when warming up or cooling down the car to a specific temperature; use Configure Tesla Cabin Climate when combining temperature with seat heat, defrost, or Dog Mode.",
        searchKeywords: [
            "warm up", "warm up my car", "cool down", "cool down my car",
            "set temperature", "set car temperature", "heat car", "cool car", "AC", "air conditioning"
        ]
    )
    public static let isDiscoverable = true

    /// Tesla accepts roughly 15–28 °C; values outside are clamped.
    static let minCelsius = 15.0
    static let maxCelsius = 28.0

    static func targetCelsius(for measurement: Measurement<UnitTemperature>) -> Double {
        let requestedCelsius = measurement.converted(to: .celsius).value
        let clampedCelsius = min(max(requestedCelsius, Self.minCelsius), Self.maxCelsius)
        return (clampedCelsius * 2).rounded() / 2
    }

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account whose cabin temperature should be updated. Optional; omit to use the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Temperature",
        description: "Target cabin temperature for both front seats, expressed in the user's preferred temperature unit (°F or °C, valid range 15°C to 28°C / 59°F to 82°F).",
        unit: .celsius,
        unitAdjustForLocale: true,
        supportsNegativeNumbers: false,
        requestValueDialog: IntentDialog("What temperature?")
    )
    public var temperature: Measurement<UnitTemperature>

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Set \(\.$vehicle) cabin to \(\.$temperature)")
        } otherwise: {
            Summary("Set my car cabin to \(\.$temperature)")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Set cabin temperature in", vehicle: vehicle))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let scope = service.sessionScopeID
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let targetCelsius = Self.targetCelsius(for: temperature)

            try await service.runControl(
                action: "auto_conditioning_start",
                vin: resolved.vin,
                humanName: "starting climate"
            )
            try await service.runControl(
                action: "set_temps",
                vin: resolved.vin,
                params: [
                    "driver_temp": .double(targetCelsius),
                    "passenger_temp": .double(targetCelsius)
                ],
                humanName: "setting the cabin temperature"
            )

            let applied = Measurement(value: targetCelsius, unit: UnitTemperature.celsius)
                .converted(to: temperature.unit)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
            let summary = "Started climate and set \(resolved.name)'s cabin to \(applied)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_temps",
                appliedValue: applied,
                summary: summary
            )
            log.success("started climate and set \(resolved.name) cabin to \(targetCelsius)°C")
            return .result(
                value: result,
                dialog: IntentDialog("\(summary)"),
                snippetIntent: ClimateControlSnippetIntent(
                    vehicle: VehicleEntity(id: resolved.vin, name: resolved.name),
                    appliedSummary: summary, scope: scope, running: true, targetCelsius: targetCelsius
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

@AppIntent(.tool)
public struct SetMaxDefrostIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Max Defrost"
    public static let description = IntentDescription(
        "Turns maximum windshield and cabin defrost on or off in the user's car (or Tesla). Omit the vehicle parameter to target the user's selected car.",
        searchKeywords: ["defrost my car", "defrost windshield", "max defrost", "melt ice"]
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The car from the user's fleet account whose max defrost state should change. Optional; omit to use the user's currently selected car.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "On",
        description: "Set true to turn max defrost on, or false to turn max defrost off.",
        default: true
    )
    public var on: Bool

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Turn max defrost \(\.$on) in \(\.$vehicle)")
        } otherwise: {
            Summary("Turn max defrost \(\.$on) in my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$on)) { vehicle, on in
            let target = vehicle?.name ?? FleetIntentMetadata.myCar
            return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Turn max defrost \(on ? "on" : "off") in \(target)"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(
                action: "remote_defrost",
                vin: resolved.vin,
                params: ["on": .bool(on)],
                humanName: "setting max defrost"
            )
            let summary = on ? "Max defrost is on in \(resolved.name)." : "Max defrost is off in \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "remote_defrost",
                appliedValue: on ? "on" : "off",
                summary: summary
            )
            log.success("max defrost \(on ? "on" : "off") in \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

@AppIntent(.tool)
public struct SetPetModeIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Dog Mode"
    public static let description = IntentDescription(
        "Turns Dog Mode (pet climate keeper) on or off in a Tesla vehicle. Turning Dog Mode off requires user confirmation so a pet inside is not inadvertently left without climate control."
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose Dog Mode state should change. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "On",
        description: "Set true to enable Dog Mode, or false to disable Dog Mode (prompts for confirmation).",
        default: true
    )
    public var on: Bool

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Turn dog mode \(\.$on) in \(\.$vehicle)")
        } otherwise: {
            Summary("Turn dog mode \(\.$on) in my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$on)) { vehicle, on in
            let target = vehicle?.name ?? FleetIntentMetadata.myCar
            return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Turn dog mode \(on ? "on" : "off") in \(target)"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            if !on {
                // Turning dog mode off remotely could leave a pet without climate.
                try await confirmWithSafetyGate(dialog: IntentDialog("Turn off dog mode in \(resolved.name)?"))
            }
            try await service.runControl(
                action: "set_pet_mode",
                vin: resolved.vin,
                params: ["on": .bool(on)],
                humanName: "setting dog mode"
            )
            let summary = on ? "Dog mode is on in \(resolved.name)." : "Dog mode is off in \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_pet_mode",
                appliedValue: on ? "on" : "off",
                summary: summary
            )
            log.success("dog mode \(on ? "on" : "off") in \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

@AppIntent(.tool)
public struct SetBioweaponModeIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Bioweapon Defense"
    public static let description = IntentDescription(
        "Turns Bioweapon Defense Mode positive-pressure HEPA cabin filtration on or off on supported Tesla vehicles. Omit the vehicle parameter to target the user's selected car."
    )
    public static let isDiscoverable = true

    @Parameter(
        title: "Vehicle",
        description: "The Tesla vehicle from the user's fleet account whose Bioweapon Defense Mode state should change. Optional; omit to use the user's currently selected vehicle.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "On",
        description: "Set true to turn Bioweapon Defense Mode on, or false to turn it off.",
        default: true
    )
    public var on: Bool

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Turn Bioweapon Defense \(\.$on) in \(\.$vehicle)")
        } otherwise: {
            Summary("Turn Bioweapon Defense \(\.$on) in my car")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$on)) { vehicle, on in
            let target = vehicle?.name ?? FleetIntentMetadata.myCar
            return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Turn Bioweapon Defense \(on ? "on" : "off") in \(target)"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            try await service.runControl(
                action: "set_bioweapon_mode",
                vin: resolved.vin,
                params: ["on": .bool(on), "manual_override": .bool(false)],
                humanName: "setting Bioweapon Defense Mode"
            )
            let summary = on ? "Bioweapon Defense Mode is on in \(resolved.name)." : "Bioweapon Defense Mode is off in \(resolved.name)."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_bioweapon_mode",
                appliedValue: on ? "on" : "off",
                summary: summary
            )
            log.success("Bioweapon Defense \(on ? "on" : "off") in \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
