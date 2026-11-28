import AppIntents
import Foundation

/// A seat in the car for seat heating and cooling commands.
public enum SeatPosition: String, AppEnum, Sendable {
    case driver
    case passenger
    case frontSeats
    case rearLeft
    case rearCenter
    case rearRight

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Seat")
    public static let caseDisplayRepresentations: [SeatPosition: DisplayRepresentation] = [
        .driver: DisplayRepresentation(title: "Driver Seat", subtitle: "Front left in left-hand-drive cars; \"my seat\""),
        .passenger: DisplayRepresentation(title: "Passenger Seat", subtitle: "Front passenger seat"),
        .frontSeats: DisplayRepresentation(title: "Both Front Seats", subtitle: "Driver and front passenger"),
        .rearLeft: DisplayRepresentation(title: "Rear Left Seat", subtitle: "Second row, behind the driver"),
        .rearCenter: DisplayRepresentation(title: "Rear Middle Seat", subtitle: "Second row, center"),
        .rearRight: DisplayRepresentation(title: "Rear Right Seat", subtitle: "Second row, behind the passenger")
    ]

    /// Tessie `seat` values this position maps to.
    var tessieSeats: [String] {
        switch self {
        case .driver: ["front_left"]
        case .passenger: ["front_right"]
        case .frontSeats: ["front_left", "front_right"]
        case .rearLeft: ["rear_left"]
        case .rearCenter: ["rear_center"]
        case .rearRight: ["rear_right"]
        }
    }

    var spokenName: String {
        switch self {
        case .driver:
            String(localized: "driver seat", bundle: .module, comment: "Spoken name for the driver's seat.")
        case .passenger:
            String(localized: "passenger seat", bundle: .module, comment: "Spoken name for the front passenger seat.")
        case .frontSeats:
            String(localized: "front seats", bundle: .module, comment: "Spoken name for both front seats.")
        case .rearLeft:
            String(localized: "rear left seat", bundle: .module, comment: "Spoken name for the rear left seat.")
        case .rearCenter:
            String(localized: "rear middle seat", bundle: .module, comment: "Spoken name for the rear center seat.")
        case .rearRight:
            String(localized: "rear right seat", bundle: .module, comment: "Spoken name for the rear right seat.")
        }
    }
}

/// Whether a seat command heats or cools (ventilates) the seat.
public enum SeatClimateMode: String, AppEnum, Sendable {
    case heat
    case cool

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Seat Climate Mode")
    public static let caseDisplayRepresentations: [SeatClimateMode: DisplayRepresentation] = [
        .heat: DisplayRepresentation(title: "Heat", subtitle: "Seat heater; every Tesla seat that has one"),
        .cool: DisplayRepresentation(title: "Cool", subtitle: "Ventilated (cooled) front seats; only on cars that have them")
    ]
}

@AppIntent(.tool)
public struct SetSeatClimateIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Seat Climate"
    public static let description = IntentDescription(
        "Heats any seat or cools ventilated front seats on supported Teslas from 0 (off) to 3 (high), starting climate automatically. Use for seat cooling, rear seat heat, or standalone seat changes; use Control Car when combining front seat heat with other controls.",
        searchKeywords: ["Tesla", "seat warmer", "heated seat", "seat heat", "cooled seat", "ventilated seat", "seat cooling", "rear seat heat", "butt warmer"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla to change. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Seat",
        description: "Which seat to change. \"My seat\" means the driver seat.",
        default: .driver
    )
    public var seat: SeatPosition

    @Parameter(
        title: "Level",
        description: "0 turns it off, 1 is low, 2 is medium, and 3 is high. \"Turn on my seat heater\" means 3.",
        default: 3,
        inclusiveRange: (0, 3)
    )
    public var level: Int

    @Parameter(
        title: "Mode",
        description: "Heat for the seat heater, or Cool for seat ventilation.",
        default: .heat
    )
    public var mode: SeatClimateMode

    public init() {}

    public init(vehicle: VehicleEntity? = nil, seat: SeatPosition, level: Int, mode: SeatClimateMode = .heat) {
        self.vehicle = vehicle
        self.seat = seat
        self.level = level
        self.mode = mode
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Set \(\.$seat) \(\.$mode) to \(\.$level) in \(\.$vehicle)")
        } otherwise: {
            Summary("Set \(\.$seat) \(\.$mode) to \(\.$level)")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$seat)) { vehicle, seat in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Heat the \(seat.spokenName) in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for heating a seat in a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Heat the \(seat.spokenName) in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for heating a seat in the user's selected car."
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
            let clamped = min(max(level, 0), 3)
            let targetSeat = seat
            let targetMode = mode
            if targetMode == .cool, ![SeatPosition.driver, .passenger, .frontSeats].contains(targetSeat) {
                throw FleetKitError.api(
                    String(
                        localized: "Only the front seats can be cooled. Try the driver or passenger seat.",
                        bundle: .module,
                        comment: "Error message when attempting to cool rear seats."
                    )
                )
            }
            let action = targetMode == .heat ? "set_seat_heat" : "set_seat_cool"
            let humanName = targetMode == .heat
                ? String(localized: "the seat heater", bundle: .module, comment: "Feature name in unsupported-action errors for seat heating.")
                : String(localized: "seat cooling", bundle: .module, comment: "Feature name in unsupported-action errors for seat cooling.")

            if targetMode == .cool, resolved.hasSeatCooling == false {
                throw FleetKitError.unsupportedAction(humanName)
            }
            let available = try await service.controlActions(for: resolved)
            guard available.supports(action) else {
                throw FleetKitError.unsupportedAction(humanName)
            }
            let verb = targetMode == .heat
                ? String(localized: "heat", bundle: .module, comment: "Short noun for seat heating in status labels.")
                : String(localized: "cooling", bundle: .module, comment: "Short noun for seat cooling in status labels.")
            var steps: [CarControlStep] = []
            if clamped > 0 {
                // Seat heat and cooling only run while HVAC is on.
                steps.append(.init(
                    "auto_conditioning_start",
                    String(localized: "climate on", bundle: .module, comment: "Short step label for turning cabin climate on."),
                    isImplicitHVACStart: true
                ))
            }
            for tessieSeat in targetSeat.tessieSeats {
                let seatName: String = switch tessieSeat {
                case "front_left":
                    String(localized: "driver seat", bundle: .module, comment: "Spoken name for the driver's seat.")
                case "front_right":
                    String(localized: "passenger seat", bundle: .module, comment: "Spoken name for the front passenger seat.")
                case "rear_left":
                    String(localized: "rear left seat", bundle: .module, comment: "Spoken name for the rear left seat.")
                case "rear_center":
                    String(localized: "rear middle seat", bundle: .module, comment: "Spoken name for the rear center seat.")
                case "rear_right":
                    String(localized: "rear right seat", bundle: .module, comment: "Spoken name for the rear right seat.")
                default:
                    tessieSeat.replacingOccurrences(of: "_", with: " ")
                }
                let stepLabel = clamped > 0
                    ? String(localized: "\(seatName) \(verb) \(clamped)", bundle: .module, comment: "Short step label for setting a seat heater or cooler to a numeric level.")
                    : String(localized: "\(seatName) \(verb) off", bundle: .module, comment: "Short step label for turning a seat heater or cooler off.")
                steps.append(.init(
                    action,
                    stepLabel,
                    ["seat": .string(tessieSeat), "level": .int(clamped)]
                ))
            }
            let plan = await CarControlPlan.make(steps, service: service, vin: resolved.vin)

            let outcome = try await performSandboxAwareBackgroundTask(
                description: String(
                    localized: "Setting seat climate in \(resolved.name)",
                    bundle: .module,
                    comment: "Progress label while adjusting seat heating or cooling."
                )
            ) {
                try await CarControlStepRunner.run(plan, service: service, vin: resolved.vin)
            }

            let confirmedSummary = if clamped == 0 {
                targetMode == .heat
                    ? String(localized: "Turned off \(targetSeat.spokenName) heat in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning off seat heating.")
                    : String(localized: "Turned off \(targetSeat.spokenName) cooling in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning off seat cooling.")
            } else {
                targetMode == .heat
                    ? String(localized: "Set \(targetSeat.spokenName) heat to \(clamped) in \(resolved.name).", bundle: .module, comment: "Siri confirmation after setting seat heating level.")
                    : String(localized: "Set \(targetSeat.spokenName) cooling to \(clamped) in \(resolved.name).", bundle: .module, comment: "Siri confirmation after setting seat cooling level.")
            }
            let wakingAction = targetMode == .heat
                ? String(localized: "turn off \(targetSeat.spokenName) heat", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off seat heat.")
                : String(localized: "turn off \(targetSeat.spokenName) cooling", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off seat cooling.")
            let summary = outcome.partialFailureSummary(vehicleName: resolved.name)
                ?? outcome.deliveryState.summary(
                    vehicleName: resolved.name,
                    wakingAction: wakingAction,
                    confirmed: confirmedSummary
                )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: action,
                succeeded: outcome.failure == nil,
                deliveryState: outcome.deliveryState,
                appliedValue: outcome.failure == nil
                    ? String(localized: "\(targetSeat.spokenName) \(clamped)", bundle: .module, comment: "Applied value summarizing seat name and climate level.")
                    : outcome.acceptedDetail,
                summary: summary
            )
            if let failure = outcome.failure {
                _ = log.failure(failure.error)
            } else {
                log.success("\(action) \(targetSeat.rawValue)=\(clamped) on \(resolved.name) (\(outcome.deliveryState.rawValue))")
            }
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetSteeringWheelHeaterIntent: AppIntent, LongRunningIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Steering Wheel Heater"
    public static let description = IntentDescription(
        "Turns the heated steering wheel on or off. Turning it on also turns on the car's climate. Not every Tesla has a heated steering wheel.",
        searchKeywords: ["heated steering wheel", "wheel warmer", "heat the wheel"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla to change. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(title: "On", description: "true to turn the heater on, false to turn it off.", default: true)
    public var on: Bool

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Turn steering wheel heater \(\.$on) in \(\.$vehicle)")
        } otherwise: {
            Summary("Turn steering wheel heater \(\.$on)")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle, \.$on)) { vehicle, on in
            let title: LocalizedStringResource = switch (vehicle, on) {
            case let (vehicle?, true):
                LocalizedStringResource(
                    "Turn steering wheel heater on in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on the steering wheel heater in a specific vehicle."
                )
            case let (vehicle?, false):
                LocalizedStringResource(
                    "Turn steering wheel heater off in \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off the steering wheel heater in a specific vehicle."
                )
            case (nil, true):
                LocalizedStringResource(
                    "Turn steering wheel heater on in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning on the steering wheel heater in the user's selected car."
                )
            case (nil, false):
                LocalizedStringResource(
                    "Turn steering wheel heater off in my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for turning off the steering wheel heater in the user's selected car."
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
            let available = try await service.controlActions(for: resolved)
            let featureName = String(localized: "the steering wheel heater", bundle: .module, comment: "Feature name for the heated steering wheel in error messages.")
            guard available.supports("steering_wheel_heater") else {
                throw FleetKitError.unsupportedAction(featureName)
            }
            let shouldStartClimate: Bool
            if enable {
                shouldStartClimate = !(await service.isClimateLikelyRunning(vin: resolved.vin))
            } else {
                shouldStartClimate = false
            }
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: enable
                    ? String(localized: "Turning on steering wheel heater in \(resolved.name)", bundle: .module, comment: "Progress label while turning on the steering wheel heater.")
                    : String(localized: "Turning off steering wheel heater in \(resolved.name)", bundle: .module, comment: "Progress label while turning off the steering wheel heater.")
            ) {
                if shouldStartClimate {
                    try await service.runControl(
                        action: "auto_conditioning_start",
                        vin: resolved.vin,
                        humanName: String(localized: "starting climate", bundle: .module, comment: "Action name used in vehicle command error messages for starting climate.")
                    )
                }
                return try await service.runControl(
                    action: "steering_wheel_heater",
                    vin: resolved.vin,
                    params: ["on": .bool(enable)],
                    humanName: featureName,
                    allowAsyncWake: !enable
                )
            }
            let confirmedSummary = enable
                ? String(localized: "The steering wheel heater is on in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning on the steering wheel heater.")
                : String(localized: "The steering wheel heater is off in \(resolved.name).", bundle: .module, comment: "Siri confirmation after turning off the steering wheel heater.")
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: String(localized: "turn off the steering wheel heater", bundle: .module, comment: "Infinitive action phrase in wake-up message for turning off the steering wheel heater."),
                confirmed: confirmedSummary
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "steering_wheel_heater",
                deliveryState: deliveryState,
                appliedValue: enable ? "on" : "off",
                summary: summary
            )
            log.success("steering wheel heater \(enable ? "on" : "off") on \(resolved.name) (\(deliveryState.rawValue))")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetChargingAmpsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Charging Amps"
    public static let description = IntentDescription(
        "Sets the maximum current the car draws while AC charging, in amps, to charge more slowly or share a circuit. It doesn't change the charge limit; use Set Tesla Charge Limit (or Control Car) for that. Doesn't affect Supercharging.",
        searchKeywords: ["charge speed", "charging current", "amperage", "slow charge"]
    )
    public static let isDiscoverable = true
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla to change. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Amps",
        description: "Charging current in amps, from 5 to 48, such as 16. The car won't exceed what the charger allows.",
        inclusiveRange: (5, 48),
        requestValueDialog: IntentDialog("How many amps?")
    )
    public var amps: Int

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Set \(\.$vehicle) charging current to \(\.$amps) A")
        } otherwise: {
            Summary("Set my car charging current to \(\.$amps) A")
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            let title: LocalizedStringResource = if let vehicle {
                LocalizedStringResource(
                    "Set charging amps for \(vehicle.name)",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for setting charging amps on a specific vehicle."
                )
            } else {
                LocalizedStringResource(
                    "Set charging amps for my car",
                    bundle: FleetKitLocalization.bundleDescription,
                    comment: "Siri prediction title for setting charging amps on the user's selected car."
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
            let clamped = min(max(amps, 5), 48)
            try await service.runControl(
                action: "set_charging_amps",
                vin: resolved.vin,
                params: ["amps": .int(clamped)],
                humanName: String(localized: "setting charging amps", bundle: .module, comment: "Action name used in vehicle command error messages for setting charging amps.")
            )
            let summary = String(
                localized: "\(resolved.name) will charge at up to \(clamped) amps.",
                bundle: .module,
                comment: "Siri confirmation after setting charging current in amps."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_charging_amps",
                appliedValue: FleetKitFormatting.amps(clamped),
                summary: summary
            )
            log.success("set charging amps \(clamped) on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog(stringLiteral: summary))
        } catch {
            throw log.failure(error)
        }
    }
}
