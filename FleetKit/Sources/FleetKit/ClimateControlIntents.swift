import AppIntents
import Foundation

// Climate controls from the Fleet controls registry: `auto_conditioning_stop`,
// `set_temps`, `remote_defrost`, `set_pet_mode`, and `set_bioweapon_mode`.
//
// Confirmation policy: climate changes run immediately, except turning dog
// mode OFF, which prompts because a pet may be relying on it.

/// Shortcuts and App Shortcuts intent. Siri AI uses the Control Car tool.
public struct StopClimateIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Turn Off Tesla Climate"
    public static let description = IntentDescription(
        "Turns off cabin heating and air conditioning in the user's car (or Tesla), such as after preconditioning. Doesn't affect charging. Use Stop Tesla Charging (or Control Car) to end a charging session.",
        searchKeywords: ["turn off AC", "turn off heat", "stop preconditioning", "stop car climate", "turn off car climate"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Stop climate in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for stopping climate in a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Stop climate in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for stopping climate in the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let scope = service.sessionScopeID
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: String(
                    localized: "Turning off climate in \(resolved.name)",
                    bundle: .module,
                    comment: "Progress label while stopping cabin climate."
                )
            ) {
                try await service.runControl(
                    action: "auto_conditioning_stop",
                    vin: resolved.vin,
                    humanName: String(localized: "stopping climate", bundle: .module, comment: "Action name used in vehicle command error messages for stopping climate."),
                    allowAsyncWake: true
                )
            }
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: String(localized: "turn off climate", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off climate."),
                confirmed: String(
                    localized: "Climate is turning off in \(resolved.name).",
                    bundle: .module,
                    comment: "Siri confirmation after turning off cabin climate."
                )
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "auto_conditioning_stop",
                deliveryState: deliveryState,
                summary: summary
            )
            log.success("stopped climate in \(resolved.name) (\(deliveryState.rawValue))")
            return .result(
                value: result,
                dialog: IntentDialog(stringLiteral: summary),
                snippetIntent: ClimateControlSnippetIntent(
                    vehicle: VehicleEntity(id: resolved.vin, name: resolved.name),
                    appliedSummary: summary,
                    scope: scope,
                    running: false,
                    deliveryState: deliveryState,
                    confirmedStart: false
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

@AppIntent(.tool)
public struct SetCabinTemperatureIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Car Temperature"
    public static let description = IntentDescription(
        "Starts cabin climate and sets a specific target temperature (15°C–28°C / 59°F–82.4°F), showing an interactive temperature card. Use only when the user names a temperature like \"set my car to 72\". For \"warm up my car\", \"cool down my car\", or multi-control requests, use Control Car instead.",
        searchKeywords: [
            "set temperature", "set car temperature", "cabin temperature",
            "warm car to", "cool car to", "heat car to", "AC", "air conditioning"
        ]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Set cabin temperature in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for setting cabin temperature in a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Set cabin temperature in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for setting cabin temperature in the user's selected car."
                )
            }
            return DisplayRepresentation(title: title)
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let scope = service.sessionScopeID
            let resolved = try await service.resolvedVehicle(vehicle?.id)

            let targetCelsius = Self.targetCelsius(for: temperature)
            let runningAnchor = await service.climateRunningAnchor(vin: resolved.vin)
            let shouldStartClimate = runningAnchor == nil

            // Keep this two-step sequence synchronous (under `LongRunningIntent` + `commandTimeout`)
            // rather than firing two `wait_for_completion=false` requests at a sleeping car,
            // which could race or drop `set_temps` before HVAC starts.
            try await performSandboxAwareBackgroundTask(
                description: String(
                    localized: "Setting cabin temperature in \(resolved.name)",
                    bundle: .module,
                    comment: "Progress label while setting cabin temperature."
                )
            ) {
                if shouldStartClimate {
                    try await service.runControl(
                        action: "auto_conditioning_start",
                        vin: resolved.vin,
                        humanName: String(localized: "starting climate", bundle: .module, comment: "Action name used in vehicle command error messages for starting climate.")
                    )
                }
                try await service.runControl(
                    action: "set_temps",
                    vin: resolved.vin,
                    params: [
                        "driver_temp": .double(targetCelsius),
                        "passenger_temp": .double(targetCelsius)
                    ],
                    humanName: String(localized: "setting the cabin temperature", bundle: .module, comment: "Action name used in vehicle command error messages for setting cabin temperature.")
                )
            }

            let applied = Measurement(value: targetCelsius, unit: UnitTemperature.celsius)
                .converted(to: temperature.unit)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
            let summary = shouldStartClimate
                ? String(localized: "Started climate and set \(resolved.name)'s cabin to \(applied).", bundle: .module, comment: "Siri confirmation after starting climate and setting a target temperature.")
                : String(localized: "Set \(resolved.name)'s cabin to \(applied).", bundle: .module, comment: "Siri confirmation after changing the cabin target temperature.")
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_temps",
                appliedValue: applied,
                summary: summary
            )
            log.success("\(shouldStartClimate ? "started climate and " : "")set \(resolved.name) cabin to \(targetCelsius)°C")
            return .result(
                value: result,
                dialog: IntentDialog(stringLiteral: summary),
                snippetIntent: ClimateControlSnippetIntent(
                    vehicle: VehicleEntity(id: resolved.vin, name: resolved.name),
                    appliedSummary: summary,
                    scope: scope,
                    running: true,
                    targetCelsius: targetCelsius,
                    confirmedStart: shouldStartClimate,
                    existingStartAnchor: runningAnchor
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetMaxDefrostIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Max Defrost"
    public static let description = IntentDescription(
        "Turns maximum windshield and cabin defrost on or off in the user's car (or Tesla). Omit the vehicle parameter to target the user's selected car.",
        searchKeywords: ["defrost my car", "defrost windshield", "max defrost", "melt ice"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            let title: LocalizedStringResource = switch (vehicle, on) {
            case let (vehicle?, true):
                LocalizedStringResource(
                    "Turn max defrost on in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on max defrost in a specific vehicle."
                )
            case let (vehicle?, false):
                LocalizedStringResource(
                    "Turn max defrost off in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off max defrost in a specific vehicle."
                )
            case (nil, true):
                LocalizedStringResource(
                    "Turn max defrost on in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on max defrost in the user's selected car."
                )
            case (nil, false):
                LocalizedStringResource(
                    "Turn max defrost off in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off max defrost in the user's selected car."
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
            let enable = on
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: enable
                    ? String(localized: "Turning on max defrost in \(resolved.name)", bundle: .module, comment: "Progress label while turning on max defrost.")
                    : String(localized: "Turning off max defrost in \(resolved.name)", bundle: .module, comment: "Progress label while turning off max defrost.")
            ) {
                try await service.runControl(
                    action: "remote_defrost",
                    vin: resolved.vin,
                    params: ["on": .bool(enable)],
                    humanName: String(localized: "setting max defrost", bundle: .module, comment: "Action name used in vehicle command error messages for setting max defrost."),
                    allowAsyncWake: true
                )
            }
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: enable
                    ? String(localized: "turn on max defrost", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning on max defrost.")
                    : String(localized: "turn off max defrost", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off max defrost."),
                confirmed: enable
                    ? String(localized: "Max defrost is on in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning on max defrost.")
                    : String(localized: "Max defrost is off in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning off max defrost.")
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "remote_defrost",
                deliveryState: deliveryState,
                appliedValue: enable ? "on" : "off",
                summary: summary
            )
            log.success("max defrost \(enable ? "on" : "off") in \(resolved.name) (\(deliveryState.rawValue))")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetPetModeIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Dog Mode"
    public static let description = IntentDescription(
        "Turns Dog Mode (pet climate keeper) on or off in a Tesla vehicle. Turning Dog Mode off requires user confirmation so a pet inside is not inadvertently left without climate control."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            let title: LocalizedStringResource = switch (vehicle, on) {
            case let (vehicle?, true):
                LocalizedStringResource(
                    "Turn Dog Mode on in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on Dog Mode in a specific vehicle."
                )
            case let (vehicle?, false):
                LocalizedStringResource(
                    "Turn Dog Mode off in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off Dog Mode in a specific vehicle."
                )
            case (nil, true):
                LocalizedStringResource(
                    "Turn Dog Mode on in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on Dog Mode in the user's selected car."
                )
            case (nil, false):
                LocalizedStringResource(
                    "Turn Dog Mode off in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off Dog Mode in the user's selected car."
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
            let enable = on
            if !enable {
                // Turning dog mode off remotely could leave a pet without climate.
                try await confirmWithSafetyGate(
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Turn off dog mode in \(resolved.name)?",
                            bundle: FleetKitLocalization.bundleDescription,
                            comment: "Confirmation prompt before disabling Dog Mode."
                        )
                    )
                )
            }
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: enable
                    ? String(localized: "Turning on Dog Mode in \(resolved.name)", bundle: .module, comment: "Progress label while turning on Dog Mode.")
                    : String(localized: "Turning off Dog Mode in \(resolved.name)", bundle: .module, comment: "Progress label while turning off Dog Mode.")
            ) {
                try await service.runControl(
                    action: "set_pet_mode",
                    vin: resolved.vin,
                    params: ["on": .bool(enable)],
                    humanName: String(localized: "setting dog mode", bundle: .module, comment: "Action name used in vehicle command error messages for Dog Mode."),
                    allowAsyncWake: true
                )
            }
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: enable
                    ? String(localized: "turn on Dog Mode", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning on Dog Mode.")
                    : String(localized: "turn off Dog Mode", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off Dog Mode."),
                confirmed: enable
                    ? String(localized: "Dog mode is on in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning on Dog Mode.")
                    : String(localized: "Dog mode is off in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning off Dog Mode.")
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_pet_mode",
                deliveryState: deliveryState,
                appliedValue: enable ? "on" : "off",
                summary: summary
            )
            log.success("dog mode \(enable ? "on" : "off") in \(resolved.name) (\(deliveryState.rawValue))")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetBioweaponModeIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Bioweapon Defense"
    public static let description = IntentDescription(
        "Turns Bioweapon Defense Mode positive-pressure HEPA cabin filtration on or off on supported Tesla vehicles. Omit the vehicle parameter to target the user's selected car."
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            let title: LocalizedStringResource = switch (vehicle, on) {
            case let (vehicle?, true):
                LocalizedStringResource(
                    "Turn Bioweapon Defense on in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on Bioweapon Defense Mode in a specific vehicle."
                )
            case let (vehicle?, false):
                LocalizedStringResource(
                    "Turn Bioweapon Defense off in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off Bioweapon Defense Mode in a specific vehicle."
                )
            case (nil, true):
                LocalizedStringResource(
                    "Turn Bioweapon Defense on in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on Bioweapon Defense Mode in the user's selected car."
                )
            case (nil, false):
                LocalizedStringResource(
                    "Turn Bioweapon Defense off in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off Bioweapon Defense Mode in the user's selected car."
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
            let enable = on
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: enable
                    ? String(localized: "Turning on Bioweapon Defense in \(resolved.name)", bundle: .module, comment: "Progress label while turning on Bioweapon Defense Mode.")
                    : String(localized: "Turning off Bioweapon Defense in \(resolved.name)", bundle: .module, comment: "Progress label while turning off Bioweapon Defense Mode.")
            ) {
                try await service.runControl(
                    action: "set_bioweapon_mode",
                    vin: resolved.vin,
                    params: ["on": .bool(enable), "manual_override": .bool(false)],
                    humanName: String(localized: "setting Bioweapon Defense Mode", bundle: .module, comment: "Action name used in vehicle command error messages for Bioweapon Defense Mode."),
                    allowAsyncWake: true
                )
            }
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: enable
                    ? String(localized: "turn on Bioweapon Defense Mode", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning on Bioweapon Defense Mode.")
                    : String(localized: "turn off Bioweapon Defense Mode", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off Bioweapon Defense Mode."),
                confirmed: enable
                    ? String(localized: "Bioweapon Defense Mode is on in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning on Bioweapon Defense Mode.")
                    : String(localized: "Bioweapon Defense Mode is off in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning off Bioweapon Defense Mode.")
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_bioweapon_mode",
                deliveryState: deliveryState,
                appliedValue: enable ? "on" : "off",
                summary: summary
            )
            log.success("Bioweapon Defense \(enable ? "on" : "off") in \(resolved.name) (\(deliveryState.rawValue))")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}
