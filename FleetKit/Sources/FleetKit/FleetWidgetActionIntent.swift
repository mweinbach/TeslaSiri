import AppIntents

public struct FleetWidgetActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Vehicle Widget Action"
    public static let isDiscoverable = false
    public static var allowedExecutionTargets: IntentExecutionTargets { [.widgetKitExtension, .appIntentsExtension, .main] }

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
        let service = FleetIntentService.make()
        let store = FleetWidgetStore(appGroup: service.appGroupIdentifier)
        let mode = service.sandboxMode
        var resolvedVIN: String?
        defer { FleetWidgetStore.reload() }
        do {
            let resolved = try await service.resolvedVehicle(vehicle?.id)
            resolvedVIN = resolved.vin
            if let command = action.command {
                let delivery = try await service.runControl(
                    action: command,
                    vin: resolved.vin,
                    humanName: action.title,
                    allowAsyncWake: action == .startClimate
                )
                let feedback: FleetWidgetActionFeedback = switch delivery {
                case .wakingVehicle:
                    .waking(action: action, message: action.wakingMessage)
                case .confirmed:
                    .confirmed(action: action)
                }
                store.recordFeedback(feedback, vin: resolved.vin, mode: mode)
                _ = try? await store.load(vin: resolved.vin, service: service)
            } else {
                _ = try await store.load(vin: resolved.vin, service: service)
                store.recordFeedback(.confirmed(action: .refresh), vin: resolved.vin, mode: mode)
            }
            log.success(action.rawValue)
            return .result()
        } catch {
            let fallbackVIN = resolvedVIN
                ?? vehicle?.id
                ?? (mode == .demoVehicle ? FleetDemoVehicleState.demoVIN : FleetSharedTokenStore(appGroup: service.appGroupIdentifier).selectedVIN())
            if let fallbackVIN {
                store.recordFeedback(.failed(action: action, error: error), vin: fallbackVIN, mode: mode)
            }
            throw log.failure(error)
        }
    }
}

public enum FleetWidgetAction: String, AppEnum, Codable, Hashable, Sendable {
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
        case .lock:
            String(localized: "Lock car", bundle: .module, comment: "Widget quick action label to lock the vehicle.")
        case .startClimate:
            String(localized: "Start climate", bundle: .module, comment: "Widget quick action label to start cabin climate.")
        case .startCharging:
            String(localized: "Start charging", bundle: .module, comment: "Widget quick action label to start charging.")
        case .refresh:
            String(localized: "Refresh vehicle", bundle: .module, comment: "Widget quick action label to refresh vehicle telemetry.")
        }
    }

    public var confirmedMessage: String {
        switch self {
        case .lock:
            String(localized: "Locked", bundle: .module, comment: "Widget confirmation banner shown after the car reports locked.")
        case .startClimate:
            String(localized: "Climate on", bundle: .module, comment: "Widget confirmation banner shown after cabin climate starts.")
        case .startCharging:
            String(localized: "Charging started", bundle: .module, comment: "Widget confirmation banner shown after a charge starts.")
        case .refresh:
            String(localized: "Updated", bundle: .module, comment: "Widget confirmation banner shown after vehicle status refreshes.")
        }
    }

    public var wakingMessage: String {
        switch self {
        case .startClimate:
            String(localized: "Waking car…", bundle: .module, comment: "Widget banner shown while a sleeping car wakes to start climate.")
        default:
            confirmedMessage
        }
    }

    public var failureFallbackMessage: String {
        switch self {
        case .lock:
            String(localized: "Couldn't lock", bundle: .module, comment: "Widget failure banner when locking fails without a clearer reason.")
        case .startClimate:
            String(localized: "Couldn't start climate", bundle: .module, comment: "Widget failure banner when climate start fails without a clearer reason.")
        case .startCharging:
            String(localized: "Couldn't start charge", bundle: .module, comment: "Widget failure banner when a charge start fails without a clearer reason.")
        case .refresh:
            String(localized: "Couldn't refresh", bundle: .module, comment: "Widget failure banner when a status refresh fails without a clearer reason.")
        }
    }
}
