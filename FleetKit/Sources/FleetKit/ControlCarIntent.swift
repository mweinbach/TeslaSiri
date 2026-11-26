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
    @Property(title: "Locked", description: "True to lock doors or false to unlock. Unlocking requires confirmation.")
    public var locked: Bool?
    @Property(title: "Sentry Mode", description: "True to enable or false to disable Sentry Mode. Disabling requires confirmation.")
    public var sentryOn: Bool?
    @Property(title: "Charging", description: "True to start a charging session, false to stop it. Stopping requires confirmation.")
    public var charging: Bool?
    @Property(title: "Charge Limit", description: "The requested battery charge limit from 50 to 100 percent. Changes require confirmation.")
    public var chargeLimitPercent: Int?
    @Property(title: "Charging Current", description: "The requested current from 5 to 48 amps.")
    public var chargingAmps: Int?
    @Property(title: "Charge Port", description: "Open or close the charge port door. Opening requires confirmation.")
    public var chargePort: ChargePortAction?
    @Property(title: "Windows", description: "Vent or close the windows. Closing requires confirmation.")
    public var windows: CarWindowAction?
    @Property(title: "Open Trunk", description: "Actuate the rear trunk or front trunk with confirmation. A powered rear trunk can close if already open.")
    public var openTrunk: TrunkPosition?
    @Property(title: "Destination", description: "An address, coordinates, or map URL the user wants sent to the car's navigation.")
    public var destination: String?
    @Property(title: "Flash Lights", description: "True only when the user wants the vehicle lights flashed once.")
    public var flashLights: Bool?
    @Property(title: "Honk Horn", description: "True only when the user wants the horn sounded once.")
    public var honkHorn: Bool?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Car Control Settings")
    }

    public init() {}
}

@AppIntent(.tool)
public struct ControlCarIntent: AppIntent, LongRunningIntent {
    public static let title: LocalizedStringResource = "Control Car"
    public static let description = IntentDescription(
        "Applies Tesla controls in one call: climate power, target temperature (°F or °C), defrost, front seat heat, steering wheel, Dog/Bioweapon Mode, locks, Sentry, charging, limit/amps, charge port, windows, trunk/frunk, lights, horn, or destination. Orders steps and confirms sensitive actions. Omit Vehicle for default car; seat cooling and updates use dedicated tools.",
        searchKeywords: [
            "control my car", "lock my car", "unlock my car", "warm up my car", "cool down my car",
            "precondition", "turn off climate", "defrost", "dog mode", "bioweapon defense",
            "sentry mode", "start charging", "stop charging", "charge limit", "charging amps",
            "charge port", "vent windows", "close windows", "open trunk", "open frunk",
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
            let available = try await service.controlActions(for: resolved)
            if let unavailable = steps.first(where: { !available.supports($0.action) }) {
                throw FleetKitError.unsupportedAction(unavailable.label)
            }
            let sensitive = steps.filter(\.needsConfirmation).map(\.label)
            if !sensitive.isEmpty {
                let description = sensitive.formatted(.list(type: .and))
                try await confirmWithSafetyGate(dialog: IntentDialog("Confirm these changes to \(resolved.name): \(description)?"))
            }

            let plan = await CarControlPlan.make(steps, service: service, vin: resolved.vin)
            let outcome = try await performSandboxAwareBackgroundTask(
                description: "Controlling \(resolved.name)"
            ) {
                try await CarControlStepRunner.run(plan, service: service, vin: resolved.vin)
            }

            let detail = outcome.acceptedDetail
            if let failure = outcome.failure, let summary = outcome.partialFailureSummary(vehicleName: resolved.name) {
                let result = VehicleCommandResultEntity(
                    vehicle: resolved,
                    action: "control_car",
                    succeeded: false,
                    appliedValue: detail,
                    summary: summary
                )
                _ = log.failure(failure.error)
                return .result(value: result, dialog: IntentDialog("\(summary)"))
            }
            let summary = outcome.deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: "apply: \(detail)",
                confirmed: "\(resolved.name) accepted: \(detail)."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "control_car",
                deliveryState: outcome.deliveryState,
                appliedValue: detail,
                summary: summary
            )
            log.success("completed \(outcome.accepted.count) requested car controls (\(outcome.deliveryState.rawValue))")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
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
            target: roundedTargetCelsius.map { ($0, String(format: "%.1f°C", $0)) },
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
            steps.append(.init("remote_defrost", defrost ? "max defrost on" : "max defrost off", ["on": .bool(defrost)]))
        }
        for (seat, name, requested) in [("front_left", "driver seat", driverSeatHeat), ("front_right", "passenger seat", passengerSeatHeat)] {
            if let requested {
                let level = min(max(requested, 0), 3)
                steps.append(.init("set_seat_heat", level > 0 ? "\(name) heat \(level)" : "\(name) heat off", ["seat": .string(seat), "level": .int(level)]))
            }
        }
        if let on = steeringWheelHeat {
            steps.append(.init("steering_wheel_heater", on ? "steering wheel heat on" : "steering wheel heat off", ["on": .bool(on)]))
        }
        if let on = dogMode {
            steps.append(.init("set_pet_mode", on ? "Dog Mode on" : "Dog Mode off", ["on": .bool(on)], confirm: !on))
        }
        if let on = bioweaponDefense {
            steps.append(.init("set_bioweapon_mode", on ? "Bioweapon Defense on" : "Bioweapon Defense off", ["on": .bool(on), "manual_override": .bool(false)]))
        }

        let seatHeatRequested = (driverSeatHeat ?? 0) > 0 || (passengerSeatHeat ?? 0) > 0
        let requiresHVAC = target != nil || seatHeatRequested || steeringWheelHeat == true
        if climateOn == true || requiresHVAC || (startWhenEmpty && steps.isEmpty) {
            let isImplicit = climateOn != true && !steps.isEmpty
            steps.insert(.init("auto_conditioning_start", "climate on", isImplicitHVACStart: isImplicit), at: 0)
        } else if climateOn == false {
            steps.append(.init("auto_conditioning_stop", "climate off"))
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
            throw FleetKitError.api("Choose a cabin temperature between 59 and 82.4°F (15 to 28°C).")
        }

        switch unit {
        case .celsius:
            guard (15.0...28.0).contains(value) else {
                throw FleetKitError.api("Choose a cabin temperature between 15 and 28°C (59 to 82.4°F).")
            }
            let target = SetCabinTemperatureIntent.targetCelsius(for: Measurement(value: value, unit: .celsius))
            return (target, String(format: "%.1f°C", target))
        case .fahrenheit:
            guard (59.0...82.4).contains(value) else {
                throw FleetKitError.api("Choose a cabin temperature between 59 and 82.4°F (15 to 28°C).")
            }
            let target = SetCabinTemperatureIntent.targetCelsius(for: Measurement(value: value, unit: .fahrenheit))
            let display = value.formatted(.number.precision(.fractionLength(0...1)))
            return (target, "\(display)°F")
        }
    }

    func steps(for vehicle: FleetVehicleInfo) throws -> [CarControlStep] {
        let resolvedTarget = try resolvedTargetTemperature()
        for level in [driverSeatHeat, passengerSeatHeat].compactMap({ $0 }) where !(0...3).contains(level) {
            throw FleetKitError.api("Choose a seat heater level between 0 and 3.")
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
            if activatesClimate { throw FleetKitError.api("Turning off climate conflicts with the requested cabin settings.") }
        }
        if charging == true && chargePort == .close {
            throw FleetKitError.api("Starting charging conflicts with closing the charge port.")
        }
        if charging == false { steps.append(.init("charge_stop", "stop charging", confirm: true)) }
        if let chargePort {
            let open = chargePort == .open
            steps.append(.init(open ? "charge_port_door_open" : "charge_port_door_close", open ? "open charge port" : "close charge port", confirm: open))
        }
        if let percent = chargeLimitPercent {
            guard (50...100).contains(percent) else { throw FleetKitError.api("Choose a charge limit between 50 and 100 percent.") }
            steps.append(.init("set_charge_limit", "charge limit \(percent)%", ["percent": .int(percent)], confirm: true))
        }
        if let amps = chargingAmps {
            guard (5...48).contains(amps) else { throw FleetKitError.api("Choose a charging current between 5 and 48 amps.") }
            steps.append(.init("set_charging_amps", "charging current \(amps) amps", ["amps": .int(amps)]))
        }
        if charging == true { steps.append(.init("charge_start", "start charging")) }
        if locked == false { steps.append(.init("door_unlock", "unlock doors", confirm: true)) }
        if let windows {
            steps.append(.init("window_control", "\(windows.rawValue) windows", ["command": .string(windows.rawValue)], confirm: windows == .close))
        }
        if let openTrunk {
            guard vehicle.canActuateTrunks != false else { throw FleetKitError.unsupportedAction("actuating the trunk") }
            steps.append(.init("actuate_trunk", "actuate \(openTrunk.spokenName)", ["which_trunk": .string(openTrunk.rawValue)], confirm: true))
        }
        if locked == true { steps.append(.init("door_lock", "lock doors")) }
        if let sentryOn {
            steps.append(.init("set_sentry_mode", sentryOn ? "Sentry Mode on" : "Sentry Mode off", ["on": .bool(sentryOn)], confirm: !sentryOn))
        }
        if let destination {
            guard vehicle.canAcceptNavigationRequests != false else { throw FleetKitError.unsupportedAction("sending a destination") }
            let address = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw FleetKitError.api("Give a destination to send to the car.") }
            steps.append(.init("navigation_request", "send destination \(address)", ["value": .string(address), "locale": .string(Locale.current.identifier(.bcp47))]))
        }
        if flashLights == true { steps.append(.init("flash_lights", "flash lights")) }
        if honkHorn == true { steps.append(.init("honk_horn", "honk horn")) }
        guard !steps.isEmpty else { throw FleetKitError.api("Tell me which car controls to change.") }
        return steps
    }
}
