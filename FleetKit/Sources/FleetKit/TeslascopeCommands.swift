import Foundation

extension TeslascopeClient {
    public static let controlActions = FleetControlActionsInfo(
        actions: (Array(TeslascopeCommand.direct.keys) + Array(TeslascopeCommand.schemas.keys)).sorted(),
        chargeActions: ["charge_port_door_close", "charge_port_door_open", "charge_start", "charge_stop", "set_charge_limit"],
        schemas: TeslascopeCommand.schemas
    )

    public static func controlActions(for vehicle: FleetVehicleInfo) -> FleetControlActionsInfo {
        let catalog = Self.controlActions
        let actions = catalog.actions.filter { action in
            catalog.chargeActions.contains(action) ? vehicle.allowsChargingCommands != false : vehicle.allowsVehicleCommands != false
        }
        return FleetControlActionsInfo(
            actions: actions,
            chargeActions: vehicle.allowsChargingCommands == false ? [] : catalog.chargeActions,
            schemas: catalog.schemas.filter { actions.contains($0.key) }
        )
    }

    public func runControl(action: String, vin: String, params: [String: FleetControlValue]) async throws {
        let command = try TeslascopeCommand(action: action, params: params)
        let target = try await entry(vin: vin)
        guard Self.controlActions(for: target.vehicle).supports(action) else {
            let category = Self.controlActions.chargeActions.contains(action) ? "charging" : "vehicle"
            throw FleetKitError.api("The linked Tesla account hasn’t granted \(category) command access for this car.")
        }
        try await sendCommand(command.name, params: command.params, publicID: target.publicID)
    }

    public func installSoftwareUpdate(vin: String, offsetSec: Int) async throws {
        guard offsetSec == 0 else {
            throw FleetKitError.api("Teslascope can only start a software update immediately.")
        }
        let target = try await entry(vin: vin)
        guard target.vehicle.allowsVehicleCommands != false else {
            throw FleetKitError.api("The linked Tesla account hasn’t granted vehicle command access for this car.")
        }
        try await sendCommand("scheduleSoftwareUpdate", params: [:], publicID: target.publicID)
    }

    private func sendCommand(_ name: String, params: [String: FleetControlValue], publicID: String) async throws {
        let body = params.isEmpty ? nil : try JSONEncoder().encode(params)
        let data = try await request(
            ["vehicle", publicID, "command", name],
            method: "POST",
            body: body,
            timeout: FleetKitConfig.vehicleCommandTimeout
        )
        struct Acknowledgement: Decodable {
            let code: Int
            let response: String
        }
        guard let acknowledgement = try? JSONDecoder().decode(Acknowledgement.self, from: data),
              acknowledgement.code == 200,
              !acknowledgement.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FleetKitError.api("Teslascope did not acknowledge the vehicle command.")
        }
    }
}

private struct TeslascopeCommand {
    let name: String
    let params: [String: FleetControlValue]

    static let direct = [
        "auto_conditioning_start": "startAC",
        "auto_conditioning_stop": "stopAC",
        "charge_port_door_close": "closeChargeDoor",
        "charge_port_door_open": "openChargeDoor",
        "charge_start": "startCharging",
        "charge_stop": "stopCharging",
        "door_lock": "lock",
        "door_unlock": "unlock",
        "flash_lights": "flashLights",
        "honk_horn": "honkHorn"
    ]
    static let schemas = [
        "actuate_trunk": ["which_trunk"],
        "navigation_request": ["value"],
        "remote_defrost": ["on"],
        "set_charge_limit": ["percent"],
        "set_pet_mode": ["on"],
        "set_seat_heat": ["seat", "level"],
        "set_sentry_mode": ["on"],
        "set_temps": ["driver_temp", "passenger_temp"],
        "window_control": ["command"]
    ]

    init(action: String, params: [String: FleetControlValue]) throws {
        if let direct = Self.direct[action] {
            self.name = direct
            self.params = [:]
            return
        }

        let invalidParameters = FleetKitError.api("The parameters for \(action) are invalid.")
        var body = [String: FleetControlValue]()
        switch action {
        case "actuate_trunk":
            switch (params["which_trunk"]?.stringValue, params["command"]?.stringValue ?? "open") {
            case ("front", "open"): name = "openFrunk"
            case ("rear", "open"): name = "openTrunk"
            case ("rear", "close"): name = "closeTrunk"
            default: throw invalidParameters
            }
        case "window_control":
            switch params["command"]?.stringValue {
            case "vent": name = "ventWindows"
            case "close": name = "closeWindows"
            default: throw invalidParameters
            }
        case "remote_defrost":
            guard let on = params["on"]?.booleanValue else { throw invalidParameters }
            name = on ? "startDefrost" : "stopDefrost"
        case "set_pet_mode":
            guard let on = params["on"]?.booleanValue else { throw invalidParameters }
            name = on ? "startDogMode" : "stopDogMode"
        case "set_sentry_mode":
            guard let on = params["on"]?.booleanValue else { throw invalidParameters }
            name = on ? "enableSentryMode" : "disableSentryMode"
        case "set_charge_limit":
            guard let value = params["percent"]?.numericValue, let percent = Int(exactly: value) else {
                throw invalidParameters
            }
            name = "setChargeLimit"
            body["limit"] = .int(percent)
        case "set_temps":
            let driver = params["driver_temp"]?.numericValue
            let passenger = params["passenger_temp"]?.numericValue
            guard driver != nil || passenger != nil else { throw invalidParameters }
            name = "setTemps"
            body["driver"] = driver.map(FleetControlValue.double)
            body["passenger"] = passenger.map(FleetControlValue.double)
        case "set_seat_heat":
            // Tesla's Fleet API reserves index 3 for the second-row left backrest.
            let seats = ["front_left": 0, "front_right": 1, "rear_left": 2, "rear_center": 4, "rear_right": 5]
            guard let seat = params["seat"]?.stringValue.flatMap({ seats[$0] }),
                  let value = params["level"]?.numericValue, let level = Int(exactly: value),
                  (0...3).contains(level) else { throw invalidParameters }
            name = "setSeatHeater"
            body = ["seat": .int(seat), "level": .int(level)]
        case "navigation_request":
            guard case let .string(location) = params["value"],
                  !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalidParameters }
            name = "sendNavigation"
            body["location"] = .string(location)
        default:
            throw FleetKitError.unsupportedAction(action)
        }
        self.params = body
    }
}
