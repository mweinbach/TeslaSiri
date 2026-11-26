import Foundation

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
