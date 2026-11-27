import AppIntents
import Foundation

/// A request that opens the car up or lowers its security.
public enum CarAccessAction: String, AppEnum, Sendable {
    case unlockDoors
    case openTrunk
    case openFrunk
    case openChargePort
    case turnOffSentry

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Car Access Action")
    public static let caseDisplayRepresentations: [CarAccessAction: DisplayRepresentation] = [
        .unlockDoors: DisplayRepresentation(title: "Unlock Doors", subtitle: "Unlock all of the car's doors"),
        .openTrunk: DisplayRepresentation(title: "Open Trunk", subtitle: "Open the rear trunk; a powered trunk that is already open closes instead"),
        .openFrunk: DisplayRepresentation(title: "Open Frunk", subtitle: "Pop the front trunk under the hood; it has to be closed by hand"),
        .openChargePort: DisplayRepresentation(title: "Open Charge Port", subtitle: "Open and unlock the charge port door"),
        .turnOffSentry: DisplayRepresentation(title: "Turn Off Sentry Mode", subtitle: "Stop Sentry Mode camera monitoring while the car is parked")
    ]
}

/// The authenticated counterpart to Control Car. Everything that gives physical access to the
/// car or stops it guarding itself lives here, so Control Car can run from the Lock Screen
/// while these actions require Face ID, Touch ID, or the passcode, then a confirmation.
@AppIntent(.tool)
public struct UnlockOrOpenCarIntent: AppIntent, LongRunningIntent {
    public static let title: LocalizedStringResource = "Unlock or Open Car"
    public static let description = IntentDescription(
        "Unlocks the doors, opens the trunk, frunk, or charge port, or turns off Sentry Mode on the user's car (or Tesla), after asking the user to confirm. Pass every action the user asked for in one call. For locking, climate, charging, and other changes, use the Control Car tool.",
        searchKeywords: [
            "unlock my car", "unlock doors", "open trunk", "pop the trunk", "open frunk",
            "open charge port", "turn off sentry mode", "disable sentry"
        ]
    )
    public static let isDiscoverable = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The car to unlock or open. Omit for the selected or default car; pass a vehicle from List Cars if the user specifies another one.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Actions",
        description: "Every action the user asked for, such as Unlock Doors and Open Trunk for \"unlock my car and pop the trunk\". Include each action once.",
        requestValueDialog: IntentDialog("What would you like to unlock or open?")
    )
    public var actions: [CarAccessAction]

    public init() {}

    public init(vehicle: VehicleEntity? = nil, actions: [CarAccessAction]) {
        self.vehicle = vehicle
        self.actions = actions
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$vehicle, .hasAnyValue) {
            Summary("Perform \(\.$actions) on \(\.$vehicle)")
        } otherwise: {
            Summary("Perform \(\.$actions) on my car")
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            let steps = try Self.steps(for: actions, vehicle: resolved)
            let result = try await runCarControl(steps, on: resolved, action: "unlock_or_open_car", service: service, log: log)
            return .result(value: result, dialog: IntentDialog(stringLiteral: result.summary))
        } catch {
            throw log.failure(error)
        }
    }

    /// The commands for `actions`, each of which is confirmed. The doors unlock first, and
    /// Sentry Mode turns off last so it keeps recording until everything else is done.
    static func steps(for actions: [CarAccessAction], vehicle: FleetVehicleInfo) throws -> [CarControlStep] {
        let requested = Set(actions)
        guard !requested.isEmpty else {
            throw FleetKitError.api(
                String(
                    localized: "Tell me what to unlock or open.",
                    bundle: .module,
                    comment: "Validation error when the Unlock or Open Car tool is called with no actions."
                )
            )
        }
        if !requested.isDisjoint(with: [.openTrunk, .openFrunk]), vehicle.canActuateTrunks == false {
            throw FleetKitError.unsupportedAction(
                String(localized: "actuating the trunk", bundle: .module, comment: "Action name used in unsupported-action errors for trunk actuation.")
            )
        }

        var steps: [CarControlStep] = []
        if requested.contains(.unlockDoors) {
            steps.append(.init(
                "door_unlock",
                String(localized: "unlock doors", bundle: .module, comment: "Short step label for unlocking doors."),
                confirm: true
            ))
        }
        if requested.contains(.openChargePort) {
            steps.append(.init(
                "charge_port_door_open",
                String(localized: "open charge port", bundle: .module, comment: "Short step label for opening the charge port."),
                confirm: true
            ))
        }
        if requested.contains(.openTrunk) {
            steps.append(.init(
                "actuate_trunk",
                String(localized: "open trunk", bundle: .module, comment: "Short step label for opening the rear trunk."),
                ["which_trunk": .string(TrunkPosition.rear.rawValue)],
                confirm: true
            ))
        }
        if requested.contains(.openFrunk) {
            steps.append(.init(
                "actuate_trunk",
                String(localized: "open frunk", bundle: .module, comment: "Short step label for opening the front trunk (frunk)."),
                ["which_trunk": .string(TrunkPosition.front.rawValue)],
                confirm: true
            ))
        }
        if requested.contains(.turnOffSentry) {
            steps.append(.init(
                "set_sentry_mode",
                String(localized: "Sentry Mode off", bundle: .module, comment: "Short step label for disabling Sentry Mode."),
                ["on": .bool(false)],
                confirm: true
            ))
        }
        return steps
    }
}
