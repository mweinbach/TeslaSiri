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
        case .driver: "driver seat"
        case .passenger: "passenger seat"
        case .frontSeats: "front seats"
        case .rearLeft: "rear left seat"
        case .rearCenter: "rear middle seat"
        case .rearRight: "rear right seat"
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
    public static let title: LocalizedStringResource = "Set Tesla Seat Climate"
    public static let description = IntentDescription(
        "Heats any physical seat (front or rear) or cools the ventilated front seats on supported cars, from 0 (off) to 3 (high). Starts climate automatically when turning seat climate on. Use for seat cooling, rear-row seat heaters, or a standalone seat adjustment; when combining front seat heat with other vehicle controls, use the Control Car tool instead.",
        searchKeywords: ["seat warmer", "heated seat", "seat heat", "cooled seat", "ventilated seat", "seat cooling", "rear seat heat", "butt warmer"]
    )
    public static let isDiscoverable = true

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
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Heat the \(seat.spokenName) in", vehicle: vehicle))
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
                throw FleetKitError.api("Only the front seats can be cooled. Try the driver or passenger seat.")
            }
            let action = targetMode == .heat ? "set_seat_heat" : "set_seat_cool"
            let humanName = targetMode == .heat ? "the seat heater" : "seat cooling"

            let available = try await service.controlActions(for: resolved)
            guard available.supports(action) else {
                throw FleetKitError.unsupportedAction(humanName)
            }
            let verb = targetMode == .heat ? "heat" : "cooling"
            var steps: [CarControlStep] = []
            if clamped > 0 {
                // Seat heat and cooling only run while HVAC is on.
                steps.append(.init("auto_conditioning_start", "climate on", isImplicitHVACStart: true))
            }
            for tessieSeat in targetSeat.tessieSeats {
                let seatName = switch tessieSeat {
                case "front_left": "driver seat"
                case "front_right": "passenger seat"
                default: tessieSeat.replacingOccurrences(of: "_", with: " ") + " seat"
                }
                steps.append(.init(
                    action,
                    clamped > 0 ? "\(seatName) \(verb) \(clamped)" : "\(seatName) \(verb) off",
                    ["seat": .string(tessieSeat), "level": .int(clamped)]
                ))
            }
            let plan = await CarControlPlan.make(steps, service: service, vin: resolved.vin)

            let outcome = try await performSandboxAwareBackgroundTask(
                description: "Setting seat climate in \(resolved.name)"
            ) {
                try await CarControlStepRunner.run(plan, service: service, vin: resolved.vin)
            }

            let summary = outcome.partialFailureSummary(vehicleName: resolved.name)
                ?? outcome.deliveryState.summary(
                    vehicleName: resolved.name,
                    wakingAction: "turn off \(targetSeat.spokenName) \(verb)",
                    confirmed: clamped == 0
                        ? "Turned off \(targetSeat.spokenName) \(verb) in \(resolved.name)."
                        : "Set \(targetSeat.spokenName) \(verb) to \(clamped) in \(resolved.name)."
                )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: action,
                succeeded: outcome.failure == nil,
                deliveryState: outcome.deliveryState,
                appliedValue: outcome.failure == nil ? "\(targetSeat.spokenName) \(clamped)" : outcome.acceptedDetail,
                summary: summary
            )
            if let failure = outcome.failure {
                _ = log.failure(failure.error)
            } else {
                log.success("\(action) \(targetSeat.rawValue)=\(clamped) on \(resolved.name) (\(outcome.deliveryState.rawValue))")
            }
            return .result(value: result, dialog: IntentDialog("\(summary)"))
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
            let target = vehicle?.name ?? FleetIntentMetadata.myCar
            return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: "Turn steering wheel heater \(on ? "on" : "off") in \(target)"))
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let enable = on
            let available = try await service.controlActions(for: resolved)
            guard available.supports("steering_wheel_heater") else {
                throw FleetKitError.unsupportedAction("the steering wheel heater")
            }
            let shouldStartClimate: Bool
            if enable {
                shouldStartClimate = !(await service.isClimateLikelyRunning(vin: resolved.vin))
            } else {
                shouldStartClimate = false
            }
            let deliveryState = try await performSandboxAwareBackgroundTask(
                description: enable
                    ? "Turning on steering wheel heater in \(resolved.name)"
                    : "Turning off steering wheel heater in \(resolved.name)"
            ) {
                if shouldStartClimate {
                    try await service.runControl(action: "auto_conditioning_start", vin: resolved.vin, humanName: "starting climate")
                }
                return try await service.runControl(
                    action: "steering_wheel_heater",
                    vin: resolved.vin,
                    params: ["on": .bool(enable)],
                    humanName: "the steering wheel heater",
                    allowAsyncWake: !enable
                )
            }
            let summary = deliveryState.summary(
                vehicleName: resolved.name,
                wakingAction: "turn off the steering wheel heater",
                confirmed: "The steering wheel heater is \(enable ? "on" : "off") in \(resolved.name)."
            )
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "steering_wheel_heater",
                deliveryState: deliveryState,
                appliedValue: enable ? "on" : "off",
                summary: summary
            )
            log.success("steering wheel heater \(enable ? "on" : "off") on \(resolved.name) (\(deliveryState.rawValue))")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}

/// Shortcuts intent. Siri AI uses the Control Car tool.
public struct SetChargingAmpsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Set Tesla Charging Amps"
    public static let description = IntentDescription(
        "Sets the maximum current the car draws while AC charging, in amps, to charge more slowly or share a circuit. It doesn't change the charge limit; use the Set Tesla Charge Limit tool for that. Doesn't affect Supercharging.",
        searchKeywords: ["charge speed", "charging current", "amperage", "slow charge"]
    )
    public static let isDiscoverable = true

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
            DisplayRepresentation(title: VehicleEntity.predictionTitle(verb: "Set charging amps for", vehicle: vehicle))
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
                humanName: "setting charging amps"
            )
            let summary = "\(resolved.name) will charge at up to \(clamped) amps."
            let result = VehicleCommandResultEntity(
                vehicle: resolved,
                action: "set_charging_amps",
                appliedValue: "\(clamped) A",
                summary: summary
            )
            log.success("set charging amps \(clamped) on \(resolved.name)")
            return .result(value: result, dialog: IntentDialog("\(summary)"))
        } catch {
            throw log.failure(error)
        }
    }
}
