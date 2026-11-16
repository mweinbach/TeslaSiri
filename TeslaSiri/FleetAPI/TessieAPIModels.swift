import Foundation

typealias TessieJSONObject = [String: JSONValue]

nonisolated struct TessieResults<Value: Decodable & Sendable>: Decodable, Sendable {
    var results: [Value]
}

/// Retains only the wire fields a given adapter consumes, with Tessie's original JSON scalar types.
nonisolated struct TessieSelectedObject<Field: CodingKey>: Decodable, Sendable {
    let fields: TessieJSONObject

    init(from decoder: Decoder) throws {
        try self.init(decoder.container(keyedBy: Field.self))
    }

    fileprivate init(_ container: KeyedDecodingContainer<Field>) throws {
        var fields: TessieJSONObject = [:]
        let keys = container.allKeys
        fields.reserveCapacity(keys.count)
        for key in keys {
            fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.fields = fields
    }
}

nonisolated enum TessieDriveField: String, CodingKey {
    case id
    case startedAt = "started_at", endedAt = "ended_at"
    case averageSpeed = "average_speed", maxSpeed = "max_speed"
    case odometerDistance = "odometer_distance", energyUsed = "energy_used"
    case startingLocation = "starting_location", endingLocation = "ending_location"
    case startingLatitude = "starting_latitude", startingLongitude = "starting_longitude"
    case endingLatitude = "ending_latitude", endingLongitude = "ending_longitude"
}

nonisolated enum TessieChargeField: String, CodingKey {
    case id, cost
    case startedAt = "started_at", endedAt = "ended_at"
    case startingBattery = "starting_battery", endingBattery = "ending_battery"
    case energyAdded = "energy_added"
}

nonisolated struct TessieVehicleState: Decodable, Sendable {
    let fields: TessieJSONObject

    private enum Section: String, CodingKey {
        case displayName = "display_name", charge = "charge_state", climate = "climate_state"
        case drive = "drive_state", vehicle = "vehicle_state", configuration = "vehicle_config", gui = "gui_settings"
    }

    private enum ChargeField: String, CodingKey {
        case timestamp, batteryLevel = "battery_level", range = "battery_range", limit = "charge_limit_soc"
        case rate = "charge_rate", power = "charger_power", portOpen = "charge_port_door_open"
        case state = "charging_state", timeToFull = "time_to_full_charge", energy = "charge_energy_added"
    }

    private enum ClimateField: String, CodingKey {
        case timestamp, climateOn = "is_climate_on", inside = "inside_temp", outside = "outside_temp"
        case driverTarget = "driver_temp_setting"
    }

    private enum DriveField: String, CodingKey {
        case timestamp, speed, latitude, longitude, heading, shiftState = "shift_state"
    }

    private enum VehicleField: String, CodingKey {
        case timestamp, locked, odometer, df, pf, dr, pr, ft, rt
        case driverWindow = "fd_window", passengerWindow = "fp_window"
        case rearDriverWindow = "rd_window", rearPassengerWindow = "rp_window"
        case sentry = "sentry_mode", vehicleName = "vehicle_name", carVersion = "car_version"
        case softwareUpdate = "software_update", frontLeft = "tpms_pressure_fl", frontRight = "tpms_pressure_fr"
        case rearLeft = "tpms_pressure_rl", rearRight = "tpms_pressure_rr"
    }

    private enum ConfigurationField: String, CodingKey {
        case carType = "car_type", chassisType = "chassis_type", exteriorColor = "exterior_color"
        case canActuateTrunks = "can_actuate_trunks", canAcceptNavigationRequests = "can_accept_navigation_requests"
        case hasSeatCooling = "has_seat_cooling"
        case fascia = "fascia_type", interiorTrim = "interior_trim_type", paintOverride = "paint_color_override"
        case rhd, trimBadging, snakeCaseTrimBadging = "trim_badging", wheelType = "wheel_type"
    }

    private enum GUIField: String, CodingKey {
        case temperature = "gui_temperature_units", distance = "gui_distance_units"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Section.self)
        var fields: TessieJSONObject = [:]
        fields[Section.displayName.rawValue] = try container.decodeIfPresent(JSONValue.self, forKey: .displayName)

        func read<Field: CodingKey>(_ section: Section, keys: Field.Type) throws {
            // Tessie's adapter treats a missing, null or non-object section as empty.
            guard let nested = try? container.nestedContainer(keyedBy: keys, forKey: section) else { return }
            fields[section.rawValue] = .object(try TessieSelectedObject(nested).fields)
        }
        try read(.charge, keys: ChargeField.self)
        try read(.climate, keys: ClimateField.self)
        try read(.drive, keys: DriveField.self)
        try read(.vehicle, keys: VehicleField.self)
        try read(.configuration, keys: ConfigurationField.self)
        try read(.gui, keys: GUIField.self)
        self.fields = fields
    }
}

nonisolated struct TessieVehicleRecord: Decodable {
    var vin: String
    var isActive: Bool
    var lastState: TessieJSONObject?

    enum CodingKeys: String, CodingKey {
        case vin
        case isActive = "is_active"
        case lastState = "last_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vin = try container.decode(String.self, forKey: .vin)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        lastState = try container.decodeIfPresent(TessieVehicleState.self, forKey: .lastState)?.fields
    }
}

/// Tessie's detailed path can include telemetry fields that the route never displays.
nonisolated struct TessiePathSample: Decodable, Sendable {
    let latitude: JSONValue?
    let longitude: JSONValue?
    let odometer: JSONValue?
    let speed: JSONValue?
    let timestamp: JSONValue?
    let heading: JSONValue?
    let autopilot: JSONValue?

    var routePoint: FleetRoutePoint? {
        guard let latitude = latitude?.tessieDoubleValue,
              let longitude = longitude?.tessieDoubleValue else { return nil }
        return FleetRoutePoint(
            latitude: latitude,
            longitude: longitude,
            odometer: odometer?.tessieDoubleValue,
            speed: speed?.tessieDoubleValue,
            timestamp: timestamp?.tessieInt64Value.map(TessieModelAdapter.milliseconds),
            heading: heading?.tessieDoubleValue,
            autopilot: autopilot?.tessieStringValue
        )
    }
}

nonisolated struct TessieReleaseNotes: Decodable {
    let releaseNotes: [FleetSoftwareReleaseNote]

    enum CodingKeys: String, CodingKey {
        case releaseNotes = "release_notes"
    }
}

nonisolated struct TessieCommandResponse: Decodable {
    var result: Bool
}

nonisolated enum TessieModelAdapter {
    static let controlActions = [
        "actuate_trunk",
        "auto_conditioning_start",
        "auto_conditioning_stop",
        "door_lock",
        "door_unlock",
        "flash_lights",
        "honk_horn",
        "navigation_request",
        "remote_defrost",
        "set_bioweapon_mode",
        "set_pet_mode",
        "set_temps",
        "window_control"
    ]

    static let chargeActions = ["set_charge_limit"]

    static var capabilities: FleetCapabilities {
        FleetCapabilities(
            chargeActions: chargeActions,
            controlActions: controlActions,
            events: [],
            notificationEvents: [],
            scopes: ["vehicles", "vehicle_commands", "vehicle_history"],
            software: ["provider": "tessie"]
        )
    }

    static var controlActionInfo: FleetControlActions {
        FleetControlActions(
            actions: controlActions,
            chargeActions: chargeActions,
            schemas: [
                "actuate_trunk": ["which_trunk"],
                "navigation_request": ["value"],
                "remote_defrost": ["on"],
                "set_bioweapon_mode": ["on"],
                "set_charge_limit": ["percent"],
                "set_pet_mode": ["on"],
                "set_temps": ["driver_temp", "passenger_temp"],
                "window_control": ["command"]
            ]
        )
    }

    static func vehicle(from record: TessieVehicleRecord) -> FleetVehicle {
        let state = record.lastState ?? [:]
        return FleetVehicle(
            displayName: state.displayName,
            hidden: !record.isActive,
            latest: snapshot(vin: record.vin, state: state),
            permissions: ["read", "control"],
            vehicleTag: nil,
            vin: record.vin
        )
    }

    static func user(from state: TessieJSONObject?) -> FleetUser {
        FleetUser(
            authType: "tessie_access_token",
            name: "Tessie",
            scopes: capabilities.scopes,
            units: state?.units
        )
    }

    static func snapshot(
        vin: String,
        state: TessieJSONObject,
        tireState: TessieJSONObject? = nil
    ) -> FleetLatestSnapshot {
        let charge = state.object("charge_state")
        let climate = state.object("climate_state")
        let drive = state.object("drive_state")
        let vehicle = state.object("vehicle_state")
        let configuration = state.object("vehicle_config")
        let timestamps = [
            charge.int64("timestamp"),
            climate.int64("timestamp"),
            drive.int64("timestamp"),
            vehicle.int64("timestamp")
        ].compactMap { $0 }.map(milliseconds)
        let updatedAt = timestamps.max()

        return FleetLatestSnapshot(
            batteryLevel: charge.double("battery_level"),
            batteryRange: charge.double("battery_range"),
            chargeLimitSOC: charge.double("charge_limit_soc"),
            chargeRateMPH: charge.double("charge_rate"),
            chargerPowerKW: charge.double("charger_power"),
            chargePortDoorOpen: charge.bool("charge_port_door_open"),
            chargingState: charge.string("charging_state"),
            climateOn: climate.bool("is_climate_on"),
            closures: FleetVehicleClosureState(
                frontDriverDoorOpen: vehicle.bool("df"),
                frontDriverWindowOpen: vehicle.bool("fd_window"),
                frontPassengerDoorOpen: vehicle.bool("pf"),
                frontPassengerWindowOpen: vehicle.bool("fp_window"),
                frontTrunkOpen: vehicle.bool("ft"),
                rearDriverDoorOpen: vehicle.bool("dr"),
                rearDriverWindowOpen: vehicle.bool("rd_window"),
                rearPassengerDoorOpen: vehicle.bool("pr"),
                rearPassengerWindowOpen: vehicle.bool("rp_window"),
                rearTrunkOpen: vehicle.bool("rt")
            ),
            freshnessMS: updatedAt.map { max(Int64(Date().timeIntervalSince1970 * 1_000) - $0, 0) },
            gear: drive.string("shift_state"),
            heading: drive.double("heading"),
            insideTemp: state.displayTemperature(climate.double("inside_temp")),
            latitude: drive.double("latitude"),
            locked: vehicle.bool("locked"),
            longitude: drive.double("longitude"),
            odometer: vehicle.double("odometer"),
            outsideTemp: state.displayTemperature(climate.double("outside_temp")),
            sentryMode: vehicle.bool("sentry_mode"),
            software: software(from: state),
            speed: drive.double("speed"),
            targetTemperature: state.displayTemperature(climate.double("driver_temp_setting")),
            timeToFullCharge: charge.double("time_to_full_charge"),
            timestamp: updatedAt,
            tires: tireState.flatMap(tirePressures) ?? stateTirePressures(from: vehicle),
            updatedAt: updatedAt,
            vehicleConfiguration: FleetVehicleConfiguration(
                carType: configuration.string("car_type"),
                chassisType: configuration.string("chassis_type"),
                canActuateTrunks: configuration.bool("can_actuate_trunks"),
                canAcceptNavigationRequests: configuration.bool("can_accept_navigation_requests"),
                hasSeatCooling: configuration.bool("has_seat_cooling"),
                exteriorColor: configuration.string("exterior_color"),
                fasciaType: configuration.string("fascia_type"),
                interiorTrimType: configuration.string("interior_trim_type"),
                paintColorOverride: configuration.string("paint_color_override"),
                rightHandDrive: configuration.bool("rhd"),
                trimBadging: configuration.string("trimBadging") ?? configuration.string("trim_badging"),
                wheelType: configuration.string("wheel_type")
            ),
            vin: vin
        )
    }

    static func tirePressures(from tireState: TessieJSONObject) -> FleetTirePressures? {
        let pressures = FleetTirePressures(
            frontLeftPSI: tireState.double("front_left"),
            frontRightPSI: tireState.double("front_right"),
            lastMeasuredAt: tireState.int64("timestamp").map(milliseconds),
            rearLeftPSI: tireState.double("rear_left"),
            rearRightPSI: tireState.double("rear_right")
        )
        return pressures.hasAnyReading ? pressures : nil
    }

    static func stateTirePressures(from vehicle: TessieJSONObject) -> FleetTirePressures? {
        func psi(_ key: String) -> Double? {
            vehicle.double(key).map {
                Measurement(value: $0, unit: UnitPressure.bars).converted(to: .poundsForcePerSquareInch).value
            }
        }

        let pressures = FleetTirePressures(
            frontLeftPSI: psi("tpms_pressure_fl"),
            frontRightPSI: psi("tpms_pressure_fr"),
            rearLeftPSI: psi("tpms_pressure_rl"),
            rearRightPSI: psi("tpms_pressure_rr")
        )
        return pressures.hasAnyReading ? pressures : nil
    }

    static func software(from state: TessieJSONObject) -> FleetSoftwareUpdate {
        let vehicle = state.object("vehicle_state")
        let update = vehicle.object("software_update")
        let currentVersion = vehicle.string("car_version")?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let availableVersion = update.string("version")?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let status = update.string("status")
        let unavailableStatuses = ["", "idle", "unknown"]
        let isAvailable = availableVersion != nil
            || !unavailableStatuses.contains(status?.lowercased() ?? "")
        let expectedSeconds = update.int64("expected_duration_sec")
        let sourceTimestamp = vehicle.int64("timestamp").map(milliseconds)

        return FleetSoftwareUpdate(
            availableVersion: availableVersion,
            currentVersion: currentVersion,
            downloadPercent: update.double("download_perc"),
            expectedDurationMinutes: expectedSeconds.map { Double($0) / 60 },
            expectedDurationSec: expectedSeconds,
            installPercent: update.double("install_perc"),
            installable: isAvailable,
            scheduledStartTimeMS: update.int64("scheduled_time_ms").map(milliseconds),
            sourceTimestamp: sourceTimestamp,
            status: status,
            updateAvailable: isAvailable,
            updatedAt: sourceTimestamp,
            warningTimeRemainingMS: update.int64("warning_time_remaining_ms")
        )
    }

    static func drive(from object: TessieJSONObject, vin: String) -> FleetDriveSession? {
        guard let id = object.string("id"), let startedAt = object.int64("started_at") else { return nil }
        let startedAtMS = milliseconds(startedAt)
        let endedAtMS = object.int64("ended_at").map(milliseconds)
        return FleetDriveSession(
            avgSpeedMPH: object.double("average_speed"),
            distanceMiles: object.double("odometer_distance"),
            durationMS: endedAtMS.map { max($0 - startedAtMS, 0) },
            endedAt: endedAtMS,
            energyUsedKWH: object.double("energy_used"),
            maxSpeedMPH: object.double("max_speed"),
            route: [],
            sessionID: "\(vin):\(id)",
            startAddress: object.string("starting_location"),
            endAddress: object.string("ending_location"),
            startLatitude: object.double("starting_latitude"),
            startLongitude: object.double("starting_longitude"),
            endLatitude: object.double("ending_latitude"),
            endLongitude: object.double("ending_longitude"),
            startedAt: startedAtMS,
            vin: vin
        )
    }

    static func completedCharge(from object: TessieJSONObject, vin: String) -> FleetChargeSession? {
        guard let id = object.string("id"), let startedAt = object.int64("started_at") else { return nil }
        let startedAtMS = milliseconds(startedAt)
        let endedAtMS = object.int64("ended_at").map(milliseconds)
        return FleetChargeSession(
            batteryLevelEnd: object.double("ending_battery"),
            batteryLevelStart: object.double("starting_battery"),
            cost: object.double("cost"),
            durationMS: endedAtMS.map { max($0 - startedAtMS, 0) },
            endedAt: endedAtMS,
            energyAddedKWH: object.double("energy_added"),
            sessionID: "\(vin):\(id)",
            startedAt: startedAtMS,
            status: "Completed",
            vin: vin
        )
    }

    static func activeCharge(vin: String, state: TessieJSONObject) -> FleetChargeSession? {
        let charge = state.object("charge_state")
        guard charge.string("charging_state")?.lowercased() == "charging" else { return nil }
        let timestamp = charge.int64("timestamp").map(milliseconds)
            ?? Int64(Date().timeIntervalSince1970 * 1_000)
        return FleetChargeSession(
            avgPowerKW: charge.double("charger_power"),
            batteryLevelStart: charge.double("battery_level"),
            energyAddedKWH: charge.double("charge_energy_added"),
            maxPowerKW: charge.double("charger_power"),
            sessionID: "active:\(vin)",
            startedAt: timestamp,
            status: "Charging",
            vin: vin
        )
    }

    static func activeDrive(vin: String, state: TessieJSONObject, route: [FleetRoutePoint] = []) -> FleetActiveDriveSession {
        let drive = state.object("drive_state")
        let gear = drive.string("shift_state")?.uppercased()
        let isActive = gear.map { $0 != "P" } ?? false
        guard isActive else { return FleetActiveDriveSession(active: false, vin: vin) }

        let latest = snapshot(vin: vin, state: state)
        let latestRoutePoint = route.last ?? FleetRoutePoint(
            latitude: drive.double("latitude"),
            longitude: drive.double("longitude"),
            odometer: state.object("vehicle_state").double("odometer"),
            speed: drive.double("speed"),
            timestamp: drive.int64("timestamp").map(milliseconds)
        )
        let startedAt = route.first?.timestamp ?? drive.int64("timestamp").map(milliseconds)

        return FleetActiveDriveSession(
            active: true,
            bufferedPoints: route,
            lastUpdate: drive.int64("timestamp").map(milliseconds),
            latest: latest,
            latestRoutePoint: latestRoutePoint,
            route: route,
            routePointCount: route.count,
            sessionID: "active:\(vin)",
            startBattery: nil,
            startLocation: FleetLocationCoordinate(
                latitude: route.first?.latitude ?? drive.double("latitude"),
                longitude: route.first?.longitude ?? drive.double("longitude")
            ),
            startOdometer: route.first?.odometer,
            startedAt: startedAt,
            status: "Driving",
            vin: vin
        )
    }

    static func milliseconds(_ value: Int64) -> Int64 {
        value.magnitude < 10_000_000_000 ? value * 1_000 : value
    }
}

nonisolated extension JSONValue {
    var tessieStringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            if let integer = Int64(exactly: value) {
                return String(integer)
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var tessieDoubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .double(let value): value.isFinite ? value : nil
        case .string(let value): Double(value).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }

    var tessieInt64Value: Int64? {
        switch self {
        case .integer(let value): return Int64(value)
        case .double(let value):
            guard value.isFinite, value < Double(Int64.max), value >= Double(Int64.min) else { return nil }
            return Int64(value)
        case .string(let value):
            return Int64(value) ?? Double(value).flatMap { double in
                guard double.isFinite, double < Double(Int64.max), double >= Double(Int64.min) else { return nil }
                return Int64(double)
            }
        default:
            return nil
        }
    }

    var tessieBoolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .integer(let value):
            return value != 0
        case .double(let value):
            return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1", "yes", "on": return true
            case "false", "0", "no", "off": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    var tessieObjectValue: TessieJSONObject? {
        if case .object(let object) = self { return object }
        return nil
    }
}

nonisolated extension Dictionary where Key == String, Value == JSONValue {
    func object(_ key: String) -> TessieJSONObject {
        self[key]?.tessieObjectValue ?? [:]
    }

    func string(_ key: String) -> String? {
        self[key]?.tessieStringValue
    }

    func double(_ key: String) -> Double? {
        self[key]?.tessieDoubleValue
    }

    func int64(_ key: String) -> Int64? {
        self[key]?.tessieInt64Value
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.tessieBoolValue
    }

    var displayName: String? {
        string("display_name") ?? object("vehicle_state").string("vehicle_name")
    }

    var usesFahrenheit: Bool {
        let settings = object("gui_settings")
        if let temperature = settings.string("gui_temperature_units")?.lowercased() {
            return temperature.hasPrefix("f")
        }
        if let distance = settings.string("gui_distance_units")?.lowercased() {
            return !distance.contains("km")
        }
        return true
    }

    func displayTemperature(_ celsius: Double?) -> Double? {
        guard let celsius else { return nil }
        return usesFahrenheit ? (celsius * 9 / 5) + 32 : celsius
    }

    var units: String? {
        let settings = object("gui_settings")
        if let temperature = settings.string("gui_temperature_units")?.lowercased() {
            return temperature.hasPrefix("f") ? "imperial" : "metric"
        }
        guard let distance = settings.string("gui_distance_units")?.lowercased() else { return nil }
        return distance.contains("km") ? "metric" : "imperial"
    }
}
