import AppIntents

public struct FleetWidgetActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Vehicle Widget Action"
    public static let isDiscoverable = false

    @Parameter(title: "Vehicle")
    public var vehicle: VehicleEntity?

    @Parameter(title: "Action")
    public var action: FleetWidgetAction

    public init() {}

    public init(action: FleetWidgetAction, vehicle: VehicleEntity? = nil) {
        self.action = action
        self.vehicle = vehicle
    }

    public func perform() async throws -> some IntentResult {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        defer { FleetWidgetStore.reload() }
        do {
            let service = FleetIntentService.make()
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            if let command = action.command {
                try await service.runControl(action: command, vin: resolved.vin, humanName: action.title)
                _ = try? await FleetWidgetStore.shared.load(vin: resolved.vin, service: service)
            } else {
                _ = try await FleetWidgetStore.shared.load(vin: resolved.vin, service: service)
            }
            log.success(action.rawValue)
            return .result()
        } catch {
            throw log.failure(error)
        }
    }
}

public enum FleetWidgetAction: String, AppEnum, Sendable {
    case lock
    case startClimate
    case startCharging
    case refresh

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget Action")
    public static let caseDisplayRepresentations: [FleetWidgetAction: DisplayRepresentation] = [
        .lock: "Lock car",
        .startClimate: "Start climate",
        .startCharging: "Start charging",
        .refresh: "Refresh status"
    ]

    var command: String? {
        switch self {
        case .lock: "door_lock"
        case .startClimate: "auto_conditioning_start"
        case .startCharging: "charge_start"
        case .refresh: nil
        }
    }

    public var title: String {
        switch self {
        case .lock: "Lock car"
        case .startClimate: "Start climate"
        case .startCharging: "Start charging"
        case .refresh: "Refresh vehicle"
        }
    }
}
