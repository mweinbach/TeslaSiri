import Foundation

public struct FleetWidgetActionFeedback: Codable, Sendable, Equatable, Hashable {
    public enum Outcome: String, Codable, Sendable, Equatable, Hashable {
        case confirmed
        case waking
        case failed
    }

    public static let confirmationDuration: TimeInterval = 8
    public static let refreshConfirmationDuration: TimeInterval = 6
    public static let failureDuration: TimeInterval = 10
    public static let wakingDuration: TimeInterval = FleetWidgetSnapshot.climateStartWindow

    public var action: FleetWidgetAction
    public var outcome: Outcome
    public var message: String
    public var timestamp: Date
    public var expiresAt: Date

    public init(
        action: FleetWidgetAction,
        outcome: Outcome,
        message: String,
        timestamp: Date = .now,
        duration: TimeInterval? = nil
    ) {
        self.action = action
        self.outcome = outcome
        self.message = message
        self.timestamp = timestamp
        let resolvedDuration: TimeInterval
        if let duration {
            resolvedDuration = duration
        } else {
            switch outcome {
            case .confirmed:
                resolvedDuration = action == .refresh ? Self.refreshConfirmationDuration : Self.confirmationDuration
            case .waking:
                resolvedDuration = Self.wakingDuration
            case .failed:
                resolvedDuration = Self.failureDuration
            }
        }
        self.expiresAt = timestamp.addingTimeInterval(max(1, resolvedDuration))
    }

    public func isActive(at now: Date = .now) -> Bool {
        now >= timestamp.addingTimeInterval(-1) && now < expiresAt
    }

    public var symbolName: String {
        switch outcome {
        case .confirmed: "checkmark.circle.fill"
        case .waking: "moon.zzz.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    public static func confirmed(
        action: FleetWidgetAction,
        message: String? = nil,
        at now: Date = .now
    ) -> FleetWidgetActionFeedback {
        FleetWidgetActionFeedback(
            action: action,
            outcome: .confirmed,
            message: message ?? action.confirmedMessage,
            timestamp: now
        )
    }

    public static func waking(
        action: FleetWidgetAction,
        message: String? = nil,
        at now: Date = .now
    ) -> FleetWidgetActionFeedback {
        FleetWidgetActionFeedback(
            action: action,
            outcome: .waking,
            message: message ?? action.wakingMessage,
            timestamp: now
        )
    }

    public static func failed(
        action: FleetWidgetAction,
        error: any Error,
        at now: Date = .now
    ) -> FleetWidgetActionFeedback {
        FleetWidgetActionFeedback(
            action: action,
            outcome: .failed,
            message: failureMessage(for: error, action: action),
            timestamp: now
        )
    }

    public static func failureMessage(for error: any Error, action: FleetWidgetAction) -> String {
        if let fleetError = error as? FleetKitError {
            switch fleetError {
            case .notSignedIn:
                return String(localized: "Sign in in Wattie", bundle: .module, comment: "Widget failure banner when the shared session has no access token.")
            case .sessionExpired:
                return String(localized: "Reconnect in Wattie", bundle: .module, comment: "Widget failure banner when the provider rejected the saved token.")
            case .unsupportedAction:
                return String(localized: "Action unavailable", bundle: .module, comment: "Widget failure banner when the car cannot run the requested command.")
            case .badResponse:
                return action.failureFallbackMessage
            case .api(let detail):
                if let concise = conciseReason(from: detail) {
                    return concise
                }
                return action.failureFallbackMessage
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return String(localized: "No connection", bundle: .module, comment: "Widget failure banner when the device is offline.")
            case .timedOut:
                return String(localized: "Car timed out", bundle: .module, comment: "Widget failure banner when the car did not answer in time.")
            default:
                break
            }
        }
        return action.failureFallbackMessage
    }

    private static func conciseReason(from detail: String?) -> String? {
        guard let detail else { return nil }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.contains("not_plugged_in") || lower.contains("not plugged in") || lower.contains("unplugged") {
            return String(localized: "Plug in to charge", bundle: .module, comment: "Widget failure banner when charging fails because the car is unplugged.")
        }
        if lower.contains("complete") && lower.contains("charg") {
            return String(localized: "Already charged", bundle: .module, comment: "Widget failure banner when charging fails because the battery is complete.")
        }
        if lower.contains("asleep") || lower.contains("offline") || lower.contains("vehicle unavailable") {
            return String(localized: "Car is asleep", bundle: .module, comment: "Widget failure banner when the car is asleep or offline.")
        }
        if lower.contains("timeout") || lower.contains("timed out") {
            return String(localized: "Car timed out", bundle: .module, comment: "Widget failure banner when the car did not answer in time.")
        }
        if trimmed.count <= 26 {
            return trimmed
        }
        return nil
    }
}

public struct FleetWidgetSnapshot: Codable, Sendable, Equatable {
    public var vin: String
    public var name: String
    public var batteryLevel: Double?
    public var rangeMiles: Double?
    public var chargeLimit: Double?
    public var chargingState: String?
    public var chargerPowerKW: Double?
    public var hoursToCharge: Double?
    public var insideTemperature: Double?
    public var targetTemperature: Double?
    public var temperatureInFahrenheit: Bool
    public var usesMetric: Bool
    public var climateOn: Bool?
    public var allowsVehicleCommands: Bool?
    public var allowsChargingCommands: Bool?
    public var locked: Bool?
    public var sentryOn: Bool?
    public var openClosures: [String]?
    public var updatedAt: Date?
    public var fetchedAt: Date
    public var mode: FleetSandboxMode
    /// When a climate start was sent to a sleeping car that has not reported HVAC on yet.
    public var climateStartRequestedAt: Date?
    /// Short-lived activation feedback shown right after a user taps an interactive widget button.
    public var actionFeedback: FleetWidgetActionFeedback?

    public init(vehicle: FleetVehicleInfo, snapshot: FleetSnapshotInfo, usesMetric: Bool, mode: FleetSandboxMode, fetchedAt: Date = .now) {
        vin = vehicle.vin
        name = vehicle.name
        batteryLevel = snapshot.batteryLevel
        rangeMiles = snapshot.batteryRangeMiles
        chargeLimit = snapshot.chargeLimitSOC
        chargingState = snapshot.chargingState
        chargerPowerKW = snapshot.chargerPowerKW
        hoursToCharge = snapshot.timeToFullCharge
        insideTemperature = snapshot.insideTemp
        targetTemperature = snapshot.targetTemp
        temperatureInFahrenheit = snapshot.temperatureInFahrenheit ?? !usesMetric
        self.usesMetric = usesMetric
        allowsVehicleCommands = vehicle.allowsVehicleCommands
        allowsChargingCommands = vehicle.allowsChargingCommands
        climateOn = snapshot.hvacOn
        locked = snapshot.locked
        sentryOn = snapshot.sentryModeOn
        openClosures = snapshot.openClosures
        updatedAt = snapshot.updatedAtDate
        self.fetchedAt = fetchedAt
        self.mode = mode
    }

    public var isCharging: Bool { chargingState?.lowercased() == "charging" }

    /// How long a climate start sent to a sleeping car is shown as in progress.
    public static let climateStartWindow: TimeInterval = 120

    /// `true` while a climate start is waiting on the car to wake, so the widget doesn't
    /// show "Climate off" right after the user tapped Start Climate.
    public func isClimateStarting(at now: Date = .now) -> Bool {
        guard climateOn != true, let climateStartRequestedAt else { return false }
        return (0..<Self.climateStartWindow).contains(now.timeIntervalSince(climateStartRequestedAt))
    }

    public func activeFeedback(at now: Date = .now) -> FleetWidgetActionFeedback? {
        guard let actionFeedback, actionFeedback.isActive(at: now) else { return nil }
        if actionFeedback.outcome == .waking, actionFeedback.action == .startClimate, climateOn == true {
            return nil
        }
        return actionFeedback
    }

    public func withoutFeedback() -> FleetWidgetSnapshot {
        var copy = self
        copy.actionFeedback = nil
        return copy
    }

    public var climateDescription: String {
        if isClimateStarting() {
            return String(localized: "Climate starting…", bundle: .module, comment: "Widget climate caption while a sleeping car is waking to start HVAC.")
        }
        guard let climateOn else {
            return String(localized: "Climate status unavailable", bundle: .module, comment: "Widget climate caption when HVAC state is missing.")
        }
        return climateOn
            ? String(localized: "Climate on", bundle: .module, comment: "Widget climate caption when HVAC is running.")
            : String(localized: "Climate off", bundle: .module, comment: "Widget climate caption when HVAC is off.")
    }

    public var canStartCharging: Bool {
        guard allowsChargingCommands != false, let state = chargingState?.lowercased() else { return false }
        return ["stopped", "nopower", "no_power", "connected"].contains(state)
    }

    public var chargingDescription: String {
        guard let chargingState else {
            return String(localized: "Charge status unavailable", bundle: .module, comment: "Widget charging caption when charging state is missing.")
        }
        switch chargingState.lowercased() {
        case "charging":
            return String(localized: "Charging", bundle: .module, comment: "Widget charging status while actively charging.")
        case "complete":
            return String(localized: "Charge complete", bundle: .module, comment: "Widget charging status when charge reached its limit.")
        case "disconnected":
            return String(localized: "Unplugged", bundle: .module, comment: "Widget charging status when charge cable is disconnected.")
        case "stopped":
            return String(localized: "Charging paused", bundle: .module, comment: "Widget charging status when plugged in but paused.")
        case "nopower", "no_power":
            return String(localized: "Waiting for power", bundle: .module, comment: "Widget charging status when plugged in without power.")
        case "connected":
            return String(localized: "Plugged in", bundle: .module, comment: "Widget charging status when cable is connected.")
        default:
            return chargingState.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public var lockDescription: String {
        switch locked {
        case true:
            String(localized: "Locked", bundle: .module, comment: "Widget security status when doors are locked.")
        case false:
            String(localized: "Unlocked", bundle: .module, comment: "Widget security status when doors are unlocked.")
        default:
            String(localized: "Lock status unavailable", bundle: .module, comment: "Widget security status when lock state is missing.")
        }
    }

    public var rangeDescription: String {
        guard let rangeMiles else {
            return String(localized: "Range unavailable", bundle: .module, comment: "Widget range caption when battery range is missing.")
        }
        return FleetKitFormatting.distance(miles: rangeMiles, usesMetric: usesMetric, width: .abbreviated, fractionLength: 0)
    }

    public func temperatureDescription(_ value: Double?) -> String {
        guard let value else { return "—" }
        return FleetKitFormatting.temperature(value, inFahrenheit: temperatureInFahrenheit, width: .abbreviated, fractionLength: 0)
    }

    public var vehicleURL: URL? {
        var components = URLComponents()
        components.scheme = "wattie"
        components.host = "vehicle"
        components.queryItems = [URLQueryItem(name: "vin", value: vin)]
        return components.url
    }

    public static var sample: FleetWidgetSnapshot {
        let demo = FleetDemoVehicleState.make(preset: .mildCommute)
        return FleetWidgetSnapshot(vehicle: demo.vehicleInfo, snapshot: demo.snapshotInfo, usesMetric: false, mode: .demoVehicle)
    }
}
