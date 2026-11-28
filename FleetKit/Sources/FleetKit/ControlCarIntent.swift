import AppIntents
import Foundation

public enum CarWindowAction: String, AppEnum {
    case vent, close

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Window Action")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .vent: DisplayRepresentation(title: "Vent", subtitle: "Crack all four windows slightly to air out the cabin"),
        .close: DisplayRepresentation(title: "Close", subtitle: "Roll all windows fully up (asks for confirmation)")
    ]
}

public enum CabinTemperatureUnit: String, AppEnum, Sendable {
    case fahrenheit
    case celsius

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Temperature Unit")
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fahrenheit: DisplayRepresentation(title: "Fahrenheit", subtitle: "Degrees Fahrenheit (°F), 59 to 82.4"),
        .celsius: DisplayRepresentation(title: "Celsius", subtitle: "Degrees Celsius (°C), 15 to 28")
    ]
}

@AppEntity(.generable)
public struct CarControlSettings: TransientAppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Car Control Settings")

    @Property(title: "Climate Power", description: "True to warm up, cool down, precondition, or start cabin climate; false to turn off heat or AC. Setting a target temperature also starts climate.")
    public var climateOn: Bool?
    @Property(title: "Target Temperature", description: "Requested cabin temperature in °F (59 to 82.4) or °C (15 to 28). Pass the exact number the user said without converting. Also starts climate.")
    public var targetTemperature: Double?
    @Property(title: "Temperature Unit", description: "Fahrenheit or Celsius for Target Temperature. Optional; values 59 to 82.4 default to Fahrenheit and 15 to 28 default to Celsius.")
    public var temperatureUnit: CabinTemperatureUnit?
    @Property(title: "Max Defrost", description: "True to turn on max windshield defrost, false to turn it off.")
    public var maxDefrost: Bool?
    @Property(title: "Driver Seat Heat", description: "Driver seat heater level from 0 (off) to 3 (high).")
    public var driverSeatHeat: Int?
    @Property(title: "Passenger Seat Heat", description: "Front passenger seat heater level from 0 (off) to 3 (high).")
    public var passengerSeatHeat: Int?
    @Property(title: "Steering Wheel Heater", description: "True to turn on the heated steering wheel, false to turn it off.")
    public var steeringWheelHeat: Bool?
    @Property(title: "Dog Mode", description: "True to turn on Dog Mode, false to turn it off (requires confirmation).")
    public var dogMode: Bool?
    @Property(title: "Bioweapon Defense Mode", description: "True to turn on HEPA cabin filtration, false to turn it off.")
    public var bioweaponDefense: Bool?
    @Property(title: "Lock Doors", description: "True to lock the doors. Leave empty otherwise; unlocking uses the Unlock or Open Car tool.")
    public var locked: Bool?
    @Property(title: "Turn On Sentry Mode", description: "True to turn Sentry Mode on. Leave empty otherwise; turning it off uses the Unlock or Open Car tool.")
    public var sentryOn: Bool?
    @Property(title: "Charging", description: "True to start a charging session, false to stop it. Stopping requires confirmation.")
    public var charging: Bool?
    @Property(title: "Charge Limit", description: "The requested battery charge limit from 50 to 100 percent. Changes require confirmation.")
    public var chargeLimitPercent: Int?
    @Property(title: "Charging Current", description: "The requested current from 5 to 48 amps.")
    public var chargingAmps: Int?
    @Property(title: "Close Charge Port", description: "True to close the charge port door. Leave empty otherwise; opening it uses the Unlock or Open Car tool.")
    public var closeChargePort: Bool?
    @Property(title: "Close Trunk", description: "True to close a powered rear trunk (requires confirmation). Leave empty otherwise; opening the trunk uses the Unlock or Open Car tool.")
    public var closeTrunk: Bool?
    @Property(title: "Windows", description: "Vent or close the windows. Closing requires confirmation.")
    public var windows: CarWindowAction?
    @Property(title: "Destination", description: "An address, coordinates, or map URL the user wants sent to the car's navigation.")
    public var destination: String?
    @Property(title: "Flash Lights", description: "True only when the user wants the vehicle lights flashed once.")
    public var flashLights: Bool?
    @Property(title: "Honk Horn", description: "True only when the user wants the horn sounded once.")
    public var honkHorn: Bool?

    /// Names the requested changes, such as "climate on, 72°F, and lock doors", so Shortcuts
    /// and Siri show what a Control Car request will do instead of the type name.
    public var displayRepresentation: DisplayRepresentation {
        guard let labels = try? steps(for: nil).map(\.label), !labels.isEmpty else {
            return DisplayRepresentation(title: "Car Control Settings")
        }
        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: labels.formatted(.list(type: .and))))
    }

    public init() {}
}

@AppIntent(.tool)
public struct ControlCarIntent: AppIntent, LongRunningIntent {
    public static let title: LocalizedStringResource = "Control Car"
    public static let description = IntentDescription(
        "Applies Tesla controls in one call: warm up or cool down, target temperature (°F/°C), defrost, front seat heat, steering wheel, Dog/Bioweapon Mode, lock, Sentry on, charging, limit/amps, close trunk or charge port, windows, lights, horn, or destination. Confirms sensitive actions. Unlocking, opening, or Sentry off needs Unlock or Open Car; seat cooling and updates use other tools.",
        searchKeywords: [
            "control my car", "lock my car", "warm up my car", "heat up my car", "cool down my car",
            "precondition", "turn off climate", "defrost", "dog mode", "bioweapon defense",
            "turn on sentry mode", "start charging", "stop charging", "charge limit", "charging amps",
            "close charge port", "close trunk", "vent windows", "close windows",
            "flash lights", "honk horn", "steering wheel heater", "prepare my Tesla"
        ]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car to change. Omit for the selected or default car; pass a vehicle from List Cars if the user specifies another one.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?
    @Parameter(title: "Changes", description: "Only the controls explicitly requested for this car. A target temperature starts climate automatically even if Climate Power is omitted.")
    public var changes: CarControlSettings

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Control \(\.$vehicle) with \(\.$changes)")
        } otherwise: {
            Summary("Control my car with \(\.$changes)")
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let steps = try changes.steps(for: resolved)
            let result = try await runCarControl(steps, on: resolved, action: "control_car", service: service, log: log)
            return .result(value: result, dialog: IntentDialog(stringLiteral: result.summary))
        } catch {
            throw log.failure(error)
        }
    }
}

struct CarControlStep: Sendable {
    let action: String
    let label: String
    let params: [String: FleetControlValue]
    let needsConfirmation: Bool
    /// `true` when `auto_conditioning_start` was inserted automatically as a prerequisite
    /// for another cabin setting rather than explicitly requested via `climateOn = true`.
    let isImplicitHVACStart: Bool

    init(
        _ action: String,
        _ label: String,
        _ params: [String: FleetControlValue] = [:],
        confirm: Bool = false,
        isImplicitHVACStart: Bool = false
    ) {
        self.action = action
        self.label = label
        self.params = params
        self.needsConfirmation = confirm
        self.isImplicitHVACStart = isImplicitHVACStart
    }

    /// Commands safe to dispatch with `wait_for_completion=false` when Tessie reports the car is
    /// asleep and the command is the only one being sent. A lone seat or steering wheel heat
    /// step only happens when turning it off (turning one on also starts HVAC) or when HVAC is
    /// already running, in which case the car is awake and the command goes out synchronously.
    var isAsyncWakeEligible: Bool {
        switch action {
        case "auto_conditioning_start", "auto_conditioning_stop", "remote_defrost", "set_pet_mode",
             "set_bioweapon_mode", "set_seat_heat", "set_seat_cool", "steering_wheel_heater":
            true
        default:
            false
        }
    }

    @discardableResult
    func run(
        service: FleetIntentService,
        vin: String,
        allowAsyncWake: Bool = false
    ) async throws -> VehicleCommandDeliveryState {
        try await service.runControl(
            action: action,
            vin: vin,
            params: params,
            humanName: label,
            allowAsyncWake: allowAsyncWake
        )
    }
}

extension CabinClimateSettings {
    var roundedTargetCelsius: Double? {
        targetTemperatureCelsius.map { SetCabinTemperatureIntent.targetCelsius(for: Measurement(value: $0, unit: .celsius)) }
    }

    func controlSteps(climateOn: Bool?, startWhenEmpty: Bool) -> [CarControlStep] {
        Self.makeControlSteps(
            climateOn: climateOn,
            target: roundedTargetCelsius.map { ($0, FleetKitFormatting.temperature($0, inFahrenheit: false, fractionLength: 1)) },
            maxDefrost: enableMaxDefrost,
            driverSeatHeat: driverSeatHeatLevel,
            passengerSeatHeat: passengerSeatHeatLevel,
            steeringWheelHeat: steeringWheelHeat,
            dogMode: enablePetMode,
            bioweaponDefense: enableBioweaponDefenseMode,
            startWhenEmpty: startWhenEmpty
        )
    }

    static func makeControlSteps(
        climateOn: Bool?,
        target: (celsius: Double, label: String)?,
        maxDefrost: Bool?,
        driverSeatHeat: Int?,
        passengerSeatHeat: Int?,
        steeringWheelHeat: Bool?,
        dogMode: Bool?,
        bioweaponDefense: Bool?,
        startWhenEmpty: Bool
    ) -> [CarControlStep] {
        var steps: [CarControlStep] = []
        if let target {
            steps.append(.init("set_temps", target.label, ["driver_temp": .double(target.celsius), "passenger_temp": .double(target.celsius)]))
        }
        if let defrost = maxDefrost {
            let label = defrost
                ? String(localized: "max defrost on", bundle: .module, comment: "Short step label for turning max defrost on.")
                : String(localized: "max defrost off", bundle: .module, comment: "Short step label for turning max defrost off.")
            steps.append(.init("remote_defrost", label, ["on": .bool(defrost)]))
        }
        let seatEntries: [(String, String, Int?)] = [
            ("front_left", String(localized: "driver seat", bundle: .module, comment: "Spoken name for the driver's seat."), driverSeatHeat),
            ("front_right", String(localized: "passenger seat", bundle: .module, comment: "Spoken name for the front passenger seat."), passengerSeatHeat)
        ]
        for (seat, name, requested) in seatEntries {
            if let requested {
                let level = min(max(requested, 0), 3)
                let label = level > 0
                    ? String(localized: "\(name) heat \(level)", bundle: .module, comment: "Short step label for setting a seat heater level.")
                    : String(localized: "\(name) heat off", bundle: .module, comment: "Short step label for turning a seat heater off.")
                steps.append(.init("set_seat_heat", label, ["seat": .string(seat), "level": .int(level)]))
            }
        }
        if let on = steeringWheelHeat {
            let label = on
                ? String(localized: "steering wheel heat on", bundle: .module, comment: "Short step label for turning steering wheel heat on.")
                : String(localized: "steering wheel heat off", bundle: .module, comment: "Short step label for turning steering wheel heat off.")
            steps.append(.init("steering_wheel_heater", label, ["on": .bool(on)]))
        }
        if let on = dogMode {
            let label = on
                ? String(localized: "Dog Mode on", bundle: .module, comment: "Short step label for turning Dog Mode on.")
                : String(localized: "Dog Mode off", bundle: .module, comment: "Short step label for turning Dog Mode off.")
            steps.append(.init("set_pet_mode", label, ["on": .bool(on)], confirm: !on))
        }
        if let on = bioweaponDefense {
            let label = on
                ? String(localized: "Bioweapon Defense on", bundle: .module, comment: "Short step label for turning Bioweapon Defense Mode on.")
                : String(localized: "Bioweapon Defense off", bundle: .module, comment: "Short step label for turning Bioweapon Defense Mode off.")
            steps.append(.init("set_bioweapon_mode", label, ["on": .bool(on), "manual_override": .bool(false)]))
        }

        let seatHeatRequested = (driverSeatHeat ?? 0) > 0 || (passengerSeatHeat ?? 0) > 0
        let requiresHVAC = target != nil || seatHeatRequested || steeringWheelHeat == true
        if climateOn == true || requiresHVAC || (startWhenEmpty && steps.isEmpty) {
            let isImplicit = climateOn != true && !steps.isEmpty
            steps.insert(
                .init(
                    "auto_conditioning_start",
                    String(localized: "climate on", bundle: .module, comment: "Short step label for turning cabin climate on."),
                    isImplicitHVACStart: isImplicit
                ),
                at: 0
            )
        } else if climateOn == false {
            steps.append(
                .init(
                    "auto_conditioning_stop",
                    String(localized: "climate off", bundle: .module, comment: "Short step label for turning cabin climate off.")
                )
            )
        }
        return steps
    }
}

private extension CarControlSettings {
    func resolvedTargetTemperature() throws -> (celsius: Double, label: String)? {
        guard let value = targetTemperature else { return nil }
        let unit: CabinTemperatureUnit
        if let explicitUnit = temperatureUnit {
            unit = explicitUnit
        } else if (15.0...28.0).contains(value) {
            unit = .celsius
        } else if (59.0...82.4).contains(value) {
            unit = .fahrenheit
        } else {
            throw FleetKitError.api(
                String(
                    localized: "Choose a cabin temperature between 59 and 82.4°F (15 to 28°C).",
                    bundle: .module,
                    comment: "Validation error when cabin temperature is out of range."
                )
            )
        }

        switch unit {
        case .celsius:
            guard (15.0...28.0).contains(value) else {
                throw FleetKitError.api(
                    String(
                        localized: "Choose a cabin temperature between 15 and 28°C (59 to 82.4°F).",
                        bundle: .module,
                        comment: "Validation error when Celsius cabin temperature is out of range."
                    )
                )
            }
            let target = SetCabinTemperatureIntent.targetCelsius(for: Measurement(value: value, unit: .celsius))
            return (target, FleetKitFormatting.temperature(target, inFahrenheit: false, fractionLength: 1))
        case .fahrenheit:
            guard (59.0...82.4).contains(value) else {
                throw FleetKitError.api(
                    String(
                        localized: "Choose a cabin temperature between 59 and 82.4°F (15 to 28°C).",
                        bundle: .module,
                        comment: "Validation error when Fahrenheit cabin temperature is out of range."
                    )
                )
            }
            let target = SetCabinTemperatureIntent.targetCelsius(for: Measurement(value: value, unit: .fahrenheit))
            let formatted = Measurement(value: value, unit: UnitTemperature.fahrenheit).formatted(
                .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
            )
            return (target, formatted)
        }
    }

    /// The commands these settings turn into, in the order they are sent. Pass `nil` to
    /// describe the settings before a car is known; equipment checks are skipped.
    func steps(for vehicle: FleetVehicleInfo?) throws -> [CarControlStep] {
        // This tool runs from the Lock Screen. Anything that opens the car or lowers its
        // security belongs to Unlock or Open Car, which requires authentication; naming that
        // tool in the error lets Siri send the request there.
        if locked == false {
            throw FleetKitError.api(
                String(
                    localized: "Unlocking the doors needs the Unlock or Open Car tool.",
                    bundle: .module,
                    comment: "Error from the Control Car tool when asked to unlock; names the Siri tool that unlocks."
                )
            )
        }
        if sentryOn == false {
            throw FleetKitError.api(
                String(
                    localized: "Turning off Sentry Mode needs the Unlock or Open Car tool.",
                    bundle: .module,
                    comment: "Error from the Control Car tool when asked to turn Sentry Mode off; names the Siri tool that does."
                )
            )
        }
        let resolvedTarget = try resolvedTargetTemperature()
        for level in [driverSeatHeat, passengerSeatHeat].compactMap({ $0 }) where !(0...3).contains(level) {
            throw FleetKitError.api(
                String(
                    localized: "Choose a seat heater level between 0 and 3.",
                    bundle: .module,
                    comment: "Validation error when seat heater level is outside 0 to 3."
                )
            )
        }
        var steps = CabinClimateSettings.makeControlSteps(
            climateOn: climateOn,
            target: resolvedTarget,
            maxDefrost: maxDefrost,
            driverSeatHeat: driverSeatHeat,
            passengerSeatHeat: passengerSeatHeat,
            steeringWheelHeat: steeringWheelHeat,
            dogMode: dogMode,
            bioweaponDefense: bioweaponDefense,
            startWhenEmpty: false
        )
        if climateOn == false {
            let activatesClimate = steps.contains { $0.action == "auto_conditioning_start" }
                || maxDefrost == true || dogMode == true || bioweaponDefense == true
            if activatesClimate {
                throw FleetKitError.api(
                    String(
                        localized: "Turning off climate conflicts with the requested cabin settings.",
                        bundle: .module,
                        comment: "Validation error when turning off climate conflicts with another requested cabin setting."
                    )
                )
            }
        }
        if charging == true && closeChargePort == true {
            throw FleetKitError.api(
                String(
                    localized: "Starting charging conflicts with closing the charge port.",
                    bundle: .module,
                    comment: "Validation error when both starting charging and closing the charge port are requested."
                )
            )
        }
        if charging == false {
            steps.append(.init("charge_stop", String(localized: "stop charging", bundle: .module, comment: "Short step label for stopping charging."), confirm: true))
        }
        if closeChargePort == true {
            steps.append(.init(
                "charge_port_door_close",
                String(localized: "close charge port", bundle: .module, comment: "Short step label for closing the charge port.")
            ))
        }
        if let percent = chargeLimitPercent {
            guard (50...100).contains(percent) else {
                throw FleetKitError.api(
                    String(
                        localized: "Choose a charge limit between 50 and 100 percent.",
                        bundle: .module,
                        comment: "Validation error when charge limit is outside 50 to 100 percent."
                    )
                )
            }
            let percentText = FleetKitFormatting.percent(percent)
            steps.append(.init(
                "set_charge_limit",
                String(localized: "charge limit \(percentText)", bundle: .module, comment: "Short step label for setting battery charge limit."),
                ["percent": .int(percent)],
                confirm: true
            ))
        }
        if let amps = chargingAmps {
            guard (5...48).contains(amps) else {
                throw FleetKitError.api(
                    String(
                        localized: "Choose a charging current between 5 and 48 amps.",
                        bundle: .module,
                        comment: "Validation error when charging current is outside 5 to 48 amps."
                    )
                )
            }
            steps.append(.init(
                "set_charging_amps",
                String(localized: "charging current \(amps) amps", bundle: .module, comment: "Short step label for setting charging current in amps."),
                ["amps": .int(amps)]
            ))
        }
        if charging == true {
            steps.append(.init("charge_start", String(localized: "start charging", bundle: .module, comment: "Short step label for starting charging.")))
        }
        if closeTrunk == true {
            guard vehicle?.canActuateTrunks != false else {
                throw FleetKitError.unsupportedAction(
                    String(localized: "actuating the trunk", bundle: .module, comment: "Action name used in unsupported-action errors for trunk actuation.")
                )
            }
            steps.append(.init(
                "actuate_trunk",
                String(localized: "close trunk", bundle: .module, comment: "Short step label for closing a powered rear trunk."),
                ["which_trunk": .string(TrunkPosition.rear.rawValue), "command": .string("close")],
                confirm: true
            ))
        }
        if let windows {
            let label = windows == .vent
                ? String(localized: "vent windows", bundle: .module, comment: "Short step label for venting windows.")
                : String(localized: "close windows", bundle: .module, comment: "Short step label for closing windows.")
            steps.append(.init("window_control", label, ["command": .string(windows.rawValue)], confirm: windows == .close))
        }
        if locked == true {
            steps.append(.init("door_lock", String(localized: "lock doors", bundle: .module, comment: "Short step label for locking doors.")))
        }
        if sentryOn == true {
            steps.append(.init(
                "set_sentry_mode",
                String(localized: "Sentry Mode on", bundle: .module, comment: "Short step label for enabling Sentry Mode."),
                ["on": .bool(true)]
            ))
        }
        if let destination {
            guard vehicle?.canAcceptNavigationRequests != false else {
                throw FleetKitError.unsupportedAction(
                    String(localized: "sending a destination", bundle: .module, comment: "Action name used in unsupported-action errors for sending navigation destinations.")
                )
            }
            let address = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else {
                throw FleetKitError.api(
                    String(
                        localized: "Give a destination to send to the car.",
                        bundle: .module,
                        comment: "Validation error when destination is blank."
                    )
                )
            }
            steps.append(.init(
                "navigation_request",
                String(localized: "send destination \(address)", bundle: .module, comment: "Short step label for sending a navigation destination."),
                ["value": .string(address), "locale": .string(Locale.current.identifier(.bcp47))]
            ))
        }
        if flashLights == true {
            steps.append(.init("flash_lights", String(localized: "flash lights", bundle: .module, comment: "Short step label for flashing headlights.")))
        }
        if honkHorn == true {
            steps.append(.init("honk_horn", String(localized: "honk horn", bundle: .module, comment: "Short step label for honking the horn.")))
        }
        guard !steps.isEmpty else {
            throw FleetKitError.api(
                String(
                    localized: "Tell me which car controls to change.",
                    bundle: .module,
                    comment: "Validation error when no car controls were specified."
                )
            )
        }
        return steps
    }
}
