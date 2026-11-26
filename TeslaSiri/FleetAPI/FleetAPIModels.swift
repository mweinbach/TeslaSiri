import FleetKit
import Foundation

nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

nonisolated struct FleetTelemetrySeriesPoint: Codable, Equatable, ExpressibleByDictionaryLiteral, Sendable {
    var fields: [String: JSONValue]

    var isEmpty: Bool { fields.isEmpty }

    init(_ fields: [String: JSONValue] = [:]) {
        self.fields = fields
    }

    init(dictionaryLiteral elements: (String, JSONValue)...) {
        fields = Dictionary(uniqueKeysWithValues: elements)
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: DynamicJSONCodingKey.self) else {
            fields = [:]
            return
        }

        var decodedFields: [String: JSONValue] = [:]
        for key in container.allKeys {
            decodedFields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        fields = decodedFields
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicJSONCodingKey.self)
        for (key, value) in fields {
            try container.encode(value, forKey: DynamicJSONCodingKey(key))
        }
    }

    subscript(key: String) -> JSONValue? {
        fields[key]
    }
}

nonisolated struct FleetTelemetrySeriesPayload: Decodable, Equatable, Sendable {
    var points: [FleetTelemetrySeriesPoint]

    init(points: [FleetTelemetrySeriesPoint] = []) {
        self.points = points
    }

    init(from decoder: Decoder) throws {
        if let points = try? [FleetTelemetrySeriesPoint](from: decoder) {
            self.points = points
            return
        }

        let container = try decoder.container(keyedBy: DynamicJSONCodingKey.self)
        var points: [FleetTelemetrySeriesPoint] = []

        for key in ["points", "items", "results", "series", "data"] {
            if let nestedPoints = try? container.decode([FleetTelemetrySeriesPoint].self, forKey: DynamicJSONCodingKey(key)) {
                points.append(contentsOf: nestedPoints)
            }
        }

        if points.isEmpty {
            for key in container.allKeys {
                if let nestedPoints = try? container.decode([FleetTelemetrySeriesPoint].self, forKey: key) {
                    points.append(contentsOf: nestedPoints)
                } else if let point = try? container.decode(FleetTelemetrySeriesPoint.self, forKey: key), !point.isEmpty {
                    points.append(point)
                }
            }
        }

        self.points = points
    }
}

nonisolated private extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeFlexibleInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Self.safeInt64(from: value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value) ?? Double(value).flatMap { Self.safeInt64(from: $0) }
        }
        return nil
    }

    private static func safeInt64(from value: Double) -> Int64? {
        guard value.isFinite,
              value >= Double(Int64.min),
              value < Double(Int64.max) else {
            return nil
        }
        return Int64(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }

    init(integerLiteral value: Int) {
        self = .integer(value)
    }

    init(floatLiteral value: Double) {
        self = .double(value)
    }

    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

struct FleetAPIPage<Value: Decodable>: Decodable {
    let data: Value
    let cursor: Int64?
    let cached: Bool
    let stale: Bool
    let requestID: String?
}

nonisolated struct FleetRawAPIResponse: Codable, Equatable, Identifiable, Sendable {
    var apiVersion: String?
    var body: JSONValue?
    var bodyText: String?
    var cacheControl: String?
    var durationMS: Int64
    var errorMessage: String?
    var method: String
    var path: String
    var query: [String: String]
    var requestID: String?
    var statusCode: Int?
    var timestamp: Int64
    var url: String

    var id: String { [method, url].joined(separator: " ") }
}

nonisolated struct FleetRawDataExport: Codable, Equatable, Sendable {
    var apiBaseURL: String
    var appSchemaVersion: Int
    var generatedAt: Int64
    var responses: [FleetRawAPIResponse]
    var vin: String
}

nonisolated struct FleetCapabilities: Codable, Equatable, Sendable {
    var chargeActions: [String]
    var controlActions: [String]
    var events: [String]
    var notificationEvents: [String]
    var scopes: [String]
    var software: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case chargeActions = "charge_actions"
        case controlActions = "control_actions"
        case events
        case notificationEvents = "notification_events"
        case scopes
        case software
    }

    init(
        chargeActions: [String] = [],
        controlActions: [String] = [],
        events: [String] = [],
        notificationEvents: [String] = [],
        scopes: [String] = [],
        software: [String: JSONValue] = [:]
    ) {
        self.chargeActions = chargeActions
        self.controlActions = controlActions
        self.events = events
        self.notificationEvents = notificationEvents
        self.scopes = scopes
        self.software = software
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chargeActions = try container.decodeIfPresent([String].self, forKey: .chargeActions) ?? []
        controlActions = try container.decodeIfPresent([String].self, forKey: .controlActions) ?? []
        events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
        notificationEvents = try container.decodeIfPresent([String].self, forKey: .notificationEvents) ?? []
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
        software = try container.decodeIfPresent([String: JSONValue].self, forKey: .software) ?? [:]
    }
}

nonisolated struct FleetControlActions: Codable, Equatable, Sendable {
    var actions: [String]
    var chargeActions: [String]
    var schemas: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case actions
        case chargeActions = "charge_actions"
        case schemas
    }

    init(actions: [String] = [], chargeActions: [String] = [], schemas: [String: [String]] = [:]) {
        self.actions = actions
        self.chargeActions = chargeActions
        self.schemas = schemas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actions = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
        chargeActions = try container.decodeIfPresent([String].self, forKey: .chargeActions) ?? []
        schemas = try container.decodeIfPresent([String: [String]].self, forKey: .schemas) ?? [:]
    }
}

nonisolated struct FleetControlRequest: Encodable, Sendable {
    var action: String
    var params: [String: JSONValue]?

    init(action: String, params: [String: JSONValue] = [:]) {
        self.action = action
        self.params = params.isEmpty ? nil : params
    }
}

nonisolated struct FleetBootstrap: Codable, Equatable, Sendable {
    var activeCharging: [FleetChargeSession]
    var capabilities: FleetCapabilities?
    var recentDrives: [FleetDriveSession]
    var user: FleetUser?
    var vehicles: [FleetVehicle]

    enum CodingKeys: String, CodingKey {
        case activeCharging = "active_charging"
        case capabilities
        case recentDrives = "recent_drives"
        case user
        case vehicles
    }

    init(
        activeCharging: [FleetChargeSession] = [],
        capabilities: FleetCapabilities? = nil,
        recentDrives: [FleetDriveSession] = [],
        user: FleetUser? = nil,
        vehicles: [FleetVehicle] = []
    ) {
        self.activeCharging = activeCharging
        self.capabilities = capabilities
        self.recentDrives = recentDrives
        self.user = user
        self.vehicles = vehicles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeCharging = try container.decodeIfPresent([FleetChargeSession].self, forKey: .activeCharging) ?? []
        capabilities = try container.decodeIfPresent(FleetCapabilities.self, forKey: .capabilities)
        recentDrives = try container.decodeIfPresent([FleetDriveSession].self, forKey: .recentDrives) ?? []
        user = try container.decodeIfPresent(FleetUser.self, forKey: .user)
        vehicles = try container.decodeIfPresent([FleetVehicle].self, forKey: .vehicles) ?? []
    }
}

nonisolated struct FleetSyncChanges: Codable, Equatable, Sendable {
    var latest: [FleetLatestSnapshot]
    var vehicles: [FleetVehicle]?

    init(latest: [FleetLatestSnapshot] = [], vehicles: [FleetVehicle]? = nil) {
        self.latest = latest
        self.vehicles = vehicles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent([FleetLatestSnapshot].self, forKey: .latest) ?? []
        vehicles = try container.decodeIfPresent([FleetVehicle].self, forKey: .vehicles)
    }
}

nonisolated struct FleetUser: Codable, Equatable, Sendable {
    var authType: String?
    var email: String?
    var id: String?
    var name: String?
    var role: String?
    var scopes: [String]
    var units: String?

    enum CodingKeys: String, CodingKey {
        case authType = "auth_type"
        case email
        case id
        case name
        case role
        case scopes
        case units
    }

    init(authType: String? = nil, email: String? = nil, id: String? = nil, name: String? = nil, role: String? = nil, scopes: [String] = [], units: String? = nil) {
        self.authType = authType
        self.email = email
        self.id = id
        self.name = name
        self.role = role
        self.scopes = scopes
        self.units = units
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authType = try container.decodeIfPresent(String.self, forKey: .authType)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
        units = try container.decodeIfPresent(String.self, forKey: .units)
    }
}

nonisolated struct FleetVehicle: Codable, Equatable, Identifiable, Sendable {
    var displayName: String?
    var hidden: Bool
    var latest: FleetLatestSnapshot?
    var permissions: [String]
    var vehicleTag: String?
    var vin: String

    var id: String { vin }
    var name: String { displayName ?? vehicleTag ?? vin }
    var allowsVehicleControls: Bool { permissions.contains("control") || permissions.contains("vehicle_commands") }
    var allowsChargingControls: Bool { permissions.contains("control") || permissions.contains("charging_commands") }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case hidden
        case latest
        case permissions
        case vehicleTag = "vehicle_tag"
        case vin
    }

    init(displayName: String? = nil, hidden: Bool = false, latest: FleetLatestSnapshot? = nil, permissions: [String] = [], vehicleTag: String? = nil, vin: String) {
        self.displayName = displayName
        self.hidden = hidden
        self.latest = latest
        self.permissions = permissions
        self.vehicleTag = vehicleTag
        self.vin = vin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        latest = try container.decodeIfPresent(FleetLatestSnapshot.self, forKey: .latest)
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        vehicleTag = try container.decodeIfPresent(String.self, forKey: .vehicleTag)
        vin = try container.decode(String.self, forKey: .vin)
    }
}

nonisolated struct FleetVehicleConfiguration: Codable, Equatable, Sendable {
    var carType: String?
    var chassisType: String?
    var canActuateTrunks: Bool?
    var canAcceptNavigationRequests: Bool?
    var hasSeatCooling: Bool?
    var exteriorColor: String?
    var fasciaType: String?
    var interiorTrimType: String?
    var paintColorOverride: String?
    var rightHandDrive: Bool?
    var trimBadging: String?
    var wheelType: String?

    enum CodingKeys: String, CodingKey {
        case carType = "car_type"
        case chassisType = "chassis_type"
        case canActuateTrunks = "can_actuate_trunks"
        case canAcceptNavigationRequests = "can_accept_navigation_requests"
        case hasSeatCooling = "has_seat_cooling"
        case exteriorColor = "exterior_color"
        case fasciaType = "fascia_type"
        case interiorTrimType = "interior_trim_type"
        case paintColorOverride = "paint_color_override"
        case rightHandDrive = "right_hand_drive"
        case trimBadging = "trim_badging"
        case wheelType = "wheel_type"
    }
}

nonisolated struct FleetVehicleClosureState: Codable, Equatable, Sendable {
    var frontDriverDoorOpen: Bool?
    var frontDriverWindowOpen: Bool?
    var frontPassengerDoorOpen: Bool?
    var frontPassengerWindowOpen: Bool?
    var frontTrunkOpen: Bool?
    var rearDriverDoorOpen: Bool?
    var rearDriverWindowOpen: Bool?
    var rearPassengerDoorOpen: Bool?
    var rearPassengerWindowOpen: Bool?
    var rearTrunkOpen: Bool?

    enum CodingKeys: String, CodingKey {
        case frontDriverDoorOpen = "front_driver_door_open"
        case frontDriverWindowOpen = "front_driver_window_open"
        case frontPassengerDoorOpen = "front_passenger_door_open"
        case frontPassengerWindowOpen = "front_passenger_window_open"
        case frontTrunkOpen = "front_trunk_open"
        case rearDriverDoorOpen = "rear_driver_door_open"
        case rearDriverWindowOpen = "rear_driver_window_open"
        case rearPassengerDoorOpen = "rear_passenger_door_open"
        case rearPassengerWindowOpen = "rear_passenger_window_open"
        case rearTrunkOpen = "rear_trunk_open"
    }
}

nonisolated struct FleetTirePressures: Codable, Equatable, Sendable {
    var frontLeftPSI: Double?
    var frontRightPSI: Double?
    var lastMeasuredAt: Int64?
    var rearLeftPSI: Double?
    var rearRightPSI: Double?

    var hasAnyReading: Bool {
        frontLeftPSI != nil || frontRightPSI != nil || rearLeftPSI != nil || rearRightPSI != nil
    }

    var measuredAtDate: Date? {
        lastMeasuredAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    var displaySummary: String? {
        let readings = [
            frontLeftPSI.map { "FL \(Self.formatPSI($0))" },
            frontRightPSI.map { "FR \(Self.formatPSI($0))" },
            rearLeftPSI.map { "RL \(Self.formatPSI($0))" },
            rearRightPSI.map { "RR \(Self.formatPSI($0))" }
        ].compactMap { $0 }
        guard !readings.isEmpty else { return nil }
        return readings.joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case frontLeftPSI = "front_left_psi"
        case frontRightPSI = "front_right_psi"
        case lastMeasuredAt = "last_measured_at"
        case rearLeftPSI = "rear_left_psi"
        case rearRightPSI = "rear_right_psi"
    }

    init(
        frontLeftPSI: Double? = nil,
        frontRightPSI: Double? = nil,
        lastMeasuredAt: Int64? = nil,
        rearLeftPSI: Double? = nil,
        rearRightPSI: Double? = nil
    ) {
        self.frontLeftPSI = frontLeftPSI
        self.frontRightPSI = frontRightPSI
        self.lastMeasuredAt = lastMeasuredAt
        self.rearLeftPSI = rearLeftPSI
        self.rearRightPSI = rearRightPSI
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frontLeftPSI = container.decodeFlexibleDoubleIfPresent(forKey: .frontLeftPSI)
        frontRightPSI = container.decodeFlexibleDoubleIfPresent(forKey: .frontRightPSI)
        lastMeasuredAt = container.decodeFlexibleInt64IfPresent(forKey: .lastMeasuredAt)
        rearLeftPSI = container.decodeFlexibleDoubleIfPresent(forKey: .rearLeftPSI)
        rearRightPSI = container.decodeFlexibleDoubleIfPresent(forKey: .rearRightPSI)
    }

    private static func formatPSI(_ value: Double) -> String {
        FleetKitFormatting.tirePressure(psi: value, usesMetric: Locale.current.measurementSystem == .metric)
    }
}

nonisolated struct FleetLatestSnapshot: Codable, Equatable, Sendable {
    var batteryLevel: Double?
    var batteryRange: Double?
    var chargeLimitSOC: Double?
    var chargeRateMPH: Double?
    var chargerPowerKW: Double?
    var chargePortDoorOpen: Bool?
    var chargingState: String?
    var climateOn: Bool?
    var closures: FleetVehicleClosureState?
    var freshnessMS: Int64?
    var gear: String?
    /// Compass heading in degrees (0 = north), from Tessie `drive_state.heading`.
    var heading: Double?
    var insideTemp: Double?
    var latitude: Double?
    var locked: Bool?
    var longitude: Double?
    var odometer: Double?
    var outsideTemp: Double?
    var sentryMode: Bool?
    var software: FleetSoftwareUpdate?
    var speed: Double?
    var targetTemperature: Double?
    var timeToFullCharge: Double?
    var timestamp: Int64?
    var tires: FleetTirePressures?
    var updatedAt: Int64?
    var vehicleConfiguration: FleetVehicleConfiguration?
    var vin: String

    var timestampDate: Date? { timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var updatedAtDate: Date? { updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case batteryLevel = "battery_level"
        case batteryRange = "battery_range"
        case chargeLimitSOC = "charge_limit_soc"
        case chargeRateMPH = "charge_rate_mph"
        case chargerPowerKW = "charger_power_kw"
        case chargePortDoorOpen = "charge_port_door_open"
        case chargingState = "charging_state"
        case climateOn = "climate_on"
        case closures
        case freshnessMS = "freshness_ms"
        case gear
        case heading
        case insideTemp = "inside_temp"
        case latitude
        case locked
        case longitude
        case odometer
        case outsideTemp = "outside_temp"
        case sentryMode = "sentry_mode"
        case software
        case speed
        case targetTemperature = "target_temperature"
        case timeToFullCharge = "time_to_full_charge"
        case timestamp
        case tires
        case updatedAt = "updated_at"
        case vehicleConfiguration = "vehicle_configuration"
        case vin
    }

    init(
        batteryLevel: Double? = nil,
        batteryRange: Double? = nil,
        chargeLimitSOC: Double? = nil,
        chargeRateMPH: Double? = nil,
        chargerPowerKW: Double? = nil,
        chargePortDoorOpen: Bool? = nil,
        chargingState: String? = nil,
        climateOn: Bool? = nil,
        closures: FleetVehicleClosureState? = nil,
        freshnessMS: Int64? = nil,
        gear: String? = nil,
        heading: Double? = nil,
        insideTemp: Double? = nil,
        latitude: Double? = nil,
        locked: Bool? = nil,
        longitude: Double? = nil,
        odometer: Double? = nil,
        outsideTemp: Double? = nil,
        sentryMode: Bool? = nil,
        software: FleetSoftwareUpdate? = nil,
        speed: Double? = nil,
        targetTemperature: Double? = nil,
        timeToFullCharge: Double? = nil,
        timestamp: Int64? = nil,
        tires: FleetTirePressures? = nil,
        updatedAt: Int64? = nil,
        vehicleConfiguration: FleetVehicleConfiguration? = nil,
        vin: String = ""
    ) {
        self.batteryLevel = batteryLevel
        self.batteryRange = batteryRange
        self.chargeLimitSOC = chargeLimitSOC
        self.chargeRateMPH = chargeRateMPH
        self.chargerPowerKW = chargerPowerKW
        self.chargePortDoorOpen = chargePortDoorOpen
        self.chargingState = chargingState
        self.climateOn = climateOn
        self.closures = closures
        self.freshnessMS = freshnessMS
        self.gear = gear
        self.heading = heading
        self.insideTemp = insideTemp
        self.latitude = latitude
        self.locked = locked
        self.longitude = longitude
        self.odometer = odometer
        self.outsideTemp = outsideTemp
        self.sentryMode = sentryMode
        self.software = software
        self.speed = speed
        self.targetTemperature = targetTemperature
        self.timeToFullCharge = timeToFullCharge
        self.timestamp = timestamp
        self.tires = tires
        self.updatedAt = updatedAt
        self.vehicleConfiguration = vehicleConfiguration
        self.vin = vin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        batteryLevel = container.decodeFlexibleDoubleIfPresent(forKey: .batteryLevel)
        batteryRange = container.decodeFlexibleDoubleIfPresent(forKey: .batteryRange)
        chargeLimitSOC = container.decodeFlexibleDoubleIfPresent(forKey: .chargeLimitSOC)
        chargeRateMPH = container.decodeFlexibleDoubleIfPresent(forKey: .chargeRateMPH)
        chargerPowerKW = container.decodeFlexibleDoubleIfPresent(forKey: .chargerPowerKW)
        chargePortDoorOpen = try container.decodeIfPresent(Bool.self, forKey: .chargePortDoorOpen)
        chargingState = try container.decodeIfPresent(String.self, forKey: .chargingState)
        climateOn = try container.decodeIfPresent(Bool.self, forKey: .climateOn)
        closures = try container.decodeIfPresent(FleetVehicleClosureState.self, forKey: .closures)
        freshnessMS = container.decodeFlexibleInt64IfPresent(forKey: .freshnessMS)
        gear = try container.decodeIfPresent(String.self, forKey: .gear)
        heading = container.decodeFlexibleDoubleIfPresent(forKey: .heading)
        insideTemp = container.decodeFlexibleDoubleIfPresent(forKey: .insideTemp)
        latitude = container.decodeFlexibleDoubleIfPresent(forKey: .latitude)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked)
        longitude = container.decodeFlexibleDoubleIfPresent(forKey: .longitude)
        odometer = container.decodeFlexibleDoubleIfPresent(forKey: .odometer)
        outsideTemp = container.decodeFlexibleDoubleIfPresent(forKey: .outsideTemp)
        sentryMode = try container.decodeIfPresent(Bool.self, forKey: .sentryMode)
        software = try container.decodeIfPresent(FleetSoftwareUpdate.self, forKey: .software)
        speed = container.decodeFlexibleDoubleIfPresent(forKey: .speed)
        targetTemperature = container.decodeFlexibleDoubleIfPresent(forKey: .targetTemperature)
        timeToFullCharge = container.decodeFlexibleDoubleIfPresent(forKey: .timeToFullCharge)
        timestamp = container.decodeFlexibleInt64IfPresent(forKey: .timestamp)
        tires = try container.decodeIfPresent(FleetTirePressures.self, forKey: .tires)
        updatedAt = container.decodeFlexibleInt64IfPresent(forKey: .updatedAt)
        vehicleConfiguration = try container.decodeIfPresent(FleetVehicleConfiguration.self, forKey: .vehicleConfiguration)
        vin = try container.decodeIfPresent(String.self, forKey: .vin) ?? ""
    }
}

nonisolated struct FleetChargeSession: Codable, Equatable, Identifiable, Sendable {
    var avgPowerKW: Double?
    var batteryLevelEnd: Double?
    var batteryLevelStart: Double?
    var cost: Double?
    var currency: String?
    var durationMS: Int64?
    var endedAt: Int64?
    var energyAddedKWH: Double?
    var maxPowerKW: Double?
    var sessionID: String
    var startedAt: Int64
    var status: String?
    var vin: String

    var id: String { sessionID }
    var startedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000) }
    var endedAtDate: Date? { endedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case avgPowerKW = "avg_power_kw"
        case batteryLevelEnd = "battery_level_end"
        case batteryLevelStart = "battery_level_start"
        case cost
        case currency
        case durationMS = "duration_ms"
        case endedAt = "ended_at"
        case energyAddedKWH = "energy_added_kwh"
        case maxPowerKW = "max_power_kw"
        case sessionID = "session_id"
        case startedAt = "started_at"
        case status
        case vin
    }

    init(
        avgPowerKW: Double? = nil,
        batteryLevelEnd: Double? = nil,
        batteryLevelStart: Double? = nil,
        cost: Double? = nil,
        currency: String? = nil,
        durationMS: Int64? = nil,
        endedAt: Int64? = nil,
        energyAddedKWH: Double? = nil,
        maxPowerKW: Double? = nil,
        sessionID: String = "",
        startedAt: Int64 = 0,
        status: String? = nil,
        vin: String = ""
    ) {
        self.avgPowerKW = avgPowerKW
        self.batteryLevelEnd = batteryLevelEnd
        self.batteryLevelStart = batteryLevelStart
        self.cost = cost
        self.currency = currency
        self.durationMS = durationMS
        self.endedAt = endedAt
        self.energyAddedKWH = energyAddedKWH
        self.maxPowerKW = maxPowerKW
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.status = status
        self.vin = vin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        avgPowerKW = container.decodeFlexibleDoubleIfPresent(forKey: .avgPowerKW)
        batteryLevelEnd = container.decodeFlexibleDoubleIfPresent(forKey: .batteryLevelEnd)
        batteryLevelStart = container.decodeFlexibleDoubleIfPresent(forKey: .batteryLevelStart)
        cost = container.decodeFlexibleDoubleIfPresent(forKey: .cost)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        durationMS = container.decodeFlexibleInt64IfPresent(forKey: .durationMS)
        endedAt = container.decodeFlexibleInt64IfPresent(forKey: .endedAt)
        energyAddedKWH = container.decodeFlexibleDoubleIfPresent(forKey: .energyAddedKWH)
        maxPowerKW = container.decodeFlexibleDoubleIfPresent(forKey: .maxPowerKW)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        startedAt = container.decodeFlexibleInt64IfPresent(forKey: .startedAt) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status)
        vin = try container.decodeIfPresent(String.self, forKey: .vin) ?? ""
    }
}

nonisolated struct FleetDriveSession: Codable, Equatable, Identifiable, Sendable {
    var avgSpeedMPH: Double?
    var distanceMiles: Double?
    var durationMS: Int64?
    var endedAt: Int64?
    var energyUsedKWH: Double?
    var maxSpeedMPH: Double?
    var route: [FleetRoutePoint]
    var sessionID: String
    var startAddress: String?
    var endAddress: String?
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var startedAt: Int64
    var vin: String

    var id: String { sessionID }
    var startedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000) }
    var endedAtDate: Date? { endedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case avgSpeedMPH = "avg_speed_mph"
        case distanceMiles = "distance_miles"
        case durationMS = "duration_ms"
        case endedAt = "ended_at"
        case energyUsedKWH = "energy_used_kwh"
        case maxSpeedMPH = "max_speed_mph"
        case route = "route_points"
        case sessionID = "session_id"
        case startAddress = "start_address"
        case endAddress = "end_address"
        case startLatitude = "start_latitude"
        case startLongitude = "start_longitude"
        case endLatitude = "end_latitude"
        case endLongitude = "end_longitude"
        case startedAt = "started_at"
        case vin
    }

    private enum DecodeKeys: String, CodingKey {
        case avgSpeedMPH = "avg_speed_mph"
        case distanceMiles = "distance_miles"
        case durationMS = "duration_ms"
        case endedAt = "ended_at"
        case energyUsedKWH = "energy_used_kwh"
        case legacyRoute = "route"
        case maxSpeedMPH = "max_speed_mph"
        case routePoints = "route_points"
        case sessionID = "session_id"
        case startAddress = "start_address"
        case startLocationAddress = "start_location_address"
        case originAddress = "origin_address"
        case endAddress = "end_address"
        case endLocationAddress = "end_location_address"
        case destinationAddress = "destination_address"
        case startLatitude = "start_latitude"
        case startLongitude = "start_longitude"
        case endLatitude = "end_latitude"
        case endLongitude = "end_longitude"
        case startedAt = "started_at"
        case vin
    }

    init(
        avgSpeedMPH: Double? = nil,
        distanceMiles: Double? = nil,
        durationMS: Int64? = nil,
        endedAt: Int64? = nil,
        energyUsedKWH: Double? = nil,
        maxSpeedMPH: Double? = nil,
        route: [FleetRoutePoint] = [],
        sessionID: String = "",
        startAddress: String? = nil,
        endAddress: String? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        startedAt: Int64 = 0,
        vin: String = ""
    ) {
        self.avgSpeedMPH = avgSpeedMPH
        self.distanceMiles = distanceMiles
        self.durationMS = durationMS
        self.endedAt = endedAt
        self.energyUsedKWH = energyUsedKWH
        self.maxSpeedMPH = maxSpeedMPH
        self.route = route
        self.sessionID = sessionID
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.startedAt = startedAt
        self.vin = vin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodeKeys.self)
        avgSpeedMPH = container.decodeFlexibleDoubleIfPresent(forKey: .avgSpeedMPH)
        distanceMiles = container.decodeFlexibleDoubleIfPresent(forKey: .distanceMiles)
        durationMS = container.decodeFlexibleInt64IfPresent(forKey: .durationMS)
        endedAt = container.decodeFlexibleInt64IfPresent(forKey: .endedAt)
        energyUsedKWH = container.decodeFlexibleDoubleIfPresent(forKey: .energyUsedKWH)
        maxSpeedMPH = container.decodeFlexibleDoubleIfPresent(forKey: .maxSpeedMPH)
        let routePoints = try container.decodeIfPresent([FleetRoutePoint].self, forKey: .routePoints) ?? []
        let legacyRoute = try container.decodeIfPresent([FleetRoutePoint].self, forKey: .legacyRoute) ?? []
        route = routePoints.isEmpty ? legacyRoute : routePoints
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        startAddress = try container.decodeIfPresent(String.self, forKey: .startAddress)
            ?? container.decodeIfPresent(String.self, forKey: .startLocationAddress)
            ?? container.decodeIfPresent(String.self, forKey: .originAddress)
        endAddress = try container.decodeIfPresent(String.self, forKey: .endAddress)
            ?? container.decodeIfPresent(String.self, forKey: .endLocationAddress)
            ?? container.decodeIfPresent(String.self, forKey: .destinationAddress)
        startLatitude = container.decodeFlexibleDoubleIfPresent(forKey: .startLatitude)
        startLongitude = container.decodeFlexibleDoubleIfPresent(forKey: .startLongitude)
        endLatitude = container.decodeFlexibleDoubleIfPresent(forKey: .endLatitude)
        endLongitude = container.decodeFlexibleDoubleIfPresent(forKey: .endLongitude)
        startedAt = container.decodeFlexibleInt64IfPresent(forKey: .startedAt) ?? 0
        vin = try container.decodeIfPresent(String.self, forKey: .vin) ?? ""
    }
}

nonisolated struct FleetRoutePoint: Codable, Equatable, Identifiable, Sendable {
    var latitude: Double?
    var longitude: Double?
    var odometer: Double?
    var speed: Double?
    var timestamp: Int64?
    /// Compass heading in degrees (0 = north), from Tessie `/path?details=true`.
    var heading: Double?
    /// Tessie's Autopilot state at this point, such as `Off`, `Standby` or an active mode.
    var autopilot: String?

    var id: String {
        [
            timestamp.map { String($0) },
            latitude.map { String($0) },
            longitude.map { String($0) }
        ]
        .compactMap { $0 }
        .joined(separator: ":")
    }

    var timestampDate: Date? { timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    /// Whether Autopilot or FSD was steering at this point. Unknown or inactive states are false.
    var isSelfDriving: Bool {
        guard let state = autopilot?.lowercased().trimmingCharacters(in: .whitespaces), !state.isEmpty else { return false }
        return !["off", "standby", "unavailable", "none", "disabled", "aborting", "aborted"].contains(state)
    }

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case odometer
        case speed
        case timestamp
        case heading
        case autopilot
    }

    init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        odometer: Double? = nil,
        speed: Double? = nil,
        timestamp: Int64? = nil,
        heading: Double? = nil,
        autopilot: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.odometer = odometer
        self.speed = speed
        self.timestamp = timestamp
        self.heading = heading
        self.autopilot = autopilot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = container.decodeFlexibleDoubleIfPresent(forKey: .latitude)
        longitude = container.decodeFlexibleDoubleIfPresent(forKey: .longitude)
        odometer = container.decodeFlexibleDoubleIfPresent(forKey: .odometer)
        speed = container.decodeFlexibleDoubleIfPresent(forKey: .speed)
        timestamp = container.decodeFlexibleInt64IfPresent(forKey: .timestamp)
        heading = container.decodeFlexibleDoubleIfPresent(forKey: .heading)
        autopilot = try? container.decodeIfPresent(String.self, forKey: .autopilot)
    }
}

nonisolated struct FleetLocationCoordinate: Codable, Equatable, Sendable {
    var latitude: Double?
    var longitude: Double?

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    init(latitude: Double? = nil, longitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = container.decodeFlexibleDoubleIfPresent(forKey: .latitude)
        longitude = container.decodeFlexibleDoubleIfPresent(forKey: .longitude)
    }
}

nonisolated struct FleetActiveDriveSession: Codable, Equatable, Identifiable, Sendable {
    var active: Bool
    var bufferedPoints: [FleetRoutePoint]
    var distanceMiles: Double?
    var durationMS: Int64?
    var lastUpdate: Int64?
    var latest: FleetLatestSnapshot?
    var latestRoutePoint: FleetRoutePoint?
    var route: [FleetRoutePoint]
    var routePointCount: Int?
    var sessionID: String
    var startBattery: Double?
    var startLocation: FleetLocationCoordinate?
    var startOdometer: Double?
    var startedAt: Int64?
    var status: String?
    var vin: String

    var id: String { sessionID.isEmpty ? "active:\(vin)" : sessionID }
    var lastUpdateDate: Date? { lastUpdate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var startedAtDate: Date? { startedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case active
        case bufferedPoints = "buffered_points"
        case distanceMiles = "distance_miles"
        case durationMS = "duration_ms"
        case lastUpdate = "last_update"
        case latest
        case latestRoutePoint = "latest_route_point"
        case route = "route_points"
        case routePointCount = "route_point_count"
        case sessionID = "session_id"
        case startBattery = "start_battery"
        case startLocation = "start_location"
        case startOdometer = "start_odometer"
        case startedAt = "started_at"
        case status
        case vin
    }

    private enum DecodeKeys: String, CodingKey {
        case active
        case bufferedPoints = "buffered_points"
        case data
        case distanceMiles = "distance_miles"
        case durationMS = "duration_ms"
        case lastUpdate = "last_update"
        case latest
        case latestRoutePoint = "latest_route_point"
        case legacyRoute = "route"
        case routePoints = "route_points"
        case routePointCount = "route_point_count"
        case sessionID = "session_id"
        case startBattery = "start_battery"
        case startLocation = "start_location"
        case startOdometer = "start_odometer"
        case startedAt = "started_at"
        case status
        case vin
    }

    init(
        active: Bool = true,
        bufferedPoints: [FleetRoutePoint] = [],
        distanceMiles: Double? = nil,
        durationMS: Int64? = nil,
        lastUpdate: Int64? = nil,
        latest: FleetLatestSnapshot? = nil,
        latestRoutePoint: FleetRoutePoint? = nil,
        route: [FleetRoutePoint] = [],
        routePointCount: Int? = nil,
        sessionID: String = "",
        startBattery: Double? = nil,
        startLocation: FleetLocationCoordinate? = nil,
        startOdometer: Double? = nil,
        startedAt: Int64? = nil,
        status: String? = nil,
        vin: String = ""
    ) {
        self.active = active
        self.bufferedPoints = bufferedPoints
        self.distanceMiles = distanceMiles
        self.durationMS = durationMS
        self.lastUpdate = lastUpdate
        self.latest = latest
        self.latestRoutePoint = latestRoutePoint
        self.route = route
        self.routePointCount = routePointCount
        self.sessionID = sessionID
        self.startBattery = startBattery
        self.startLocation = startLocation
        self.startOdometer = startOdometer
        self.startedAt = startedAt
        self.status = status
        self.vin = vin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodeKeys.self)
        if let nested = try container.decodeIfPresent(FleetActiveDriveSession.self, forKey: .data) {
            self = nested
            if let active = try container.decodeIfPresent(Bool.self, forKey: .active) {
                self.active = active
            }
            if self.vin.isEmpty, let vin = try container.decodeIfPresent(String.self, forKey: .vin) {
                self.vin = vin
            }
            return
        }

        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        bufferedPoints = try container.decodeIfPresent([FleetRoutePoint].self, forKey: .bufferedPoints) ?? []
        distanceMiles = container.decodeFlexibleDoubleIfPresent(forKey: .distanceMiles)
        durationMS = container.decodeFlexibleInt64IfPresent(forKey: .durationMS)
        lastUpdate = container.decodeFlexibleInt64IfPresent(forKey: .lastUpdate)
        latest = try container.decodeIfPresent(FleetLatestSnapshot.self, forKey: .latest)
        latestRoutePoint = try container.decodeIfPresent(FleetRoutePoint.self, forKey: .latestRoutePoint)
        let routePoints = try container.decodeIfPresent([FleetRoutePoint].self, forKey: .routePoints) ?? []
        let legacyRoute = try container.decodeIfPresent([FleetRoutePoint].self, forKey: .legacyRoute) ?? []
        route = routePoints.isEmpty ? legacyRoute : routePoints
        routePointCount = try container.decodeIfPresent(Int.self, forKey: .routePointCount)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        startBattery = container.decodeFlexibleDoubleIfPresent(forKey: .startBattery)
        startLocation = try container.decodeIfPresent(FleetLocationCoordinate.self, forKey: .startLocation)
        startOdometer = container.decodeFlexibleDoubleIfPresent(forKey: .startOdometer)
        startedAt = container.decodeFlexibleInt64IfPresent(forKey: .startedAt)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        vin = try container.decodeIfPresent(String.self, forKey: .vin) ?? latest?.vin ?? ""
    }
}

nonisolated struct FleetStreamReadyMessage: Codable, Equatable, Sendable {
    var streamTypes: [String]
    var vins: [String]

    enum CodingKeys: String, CodingKey {
        case streamTypes = "stream_types"
        case vins
    }

    init(streamTypes: [String] = [], vins: [String] = []) {
        self.streamTypes = streamTypes
        self.vins = vins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamTypes = try container.decodeIfPresent([String].self, forKey: .streamTypes) ?? []
        vins = try container.decodeIfPresent([String].self, forKey: .vins) ?? []
    }
}

nonisolated enum FleetStreamMessage: Decodable, Equatable, Sendable {
    case ready(FleetStreamReadyMessage)
    case telemetryLatest([FleetLatestSnapshot])
    case driveActive([FleetActiveDriveSession])
    case error(String)
    case unknown(type: String?, payload: [String: JSONValue])

    enum CodingKeys: String, CodingKey {
        case data
        case error
        case type
        case vins
        case streamTypes = "stream_types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)

        switch type {
        case "ready":
            let ready = FleetStreamReadyMessage(
                streamTypes: try container.decodeIfPresent([String].self, forKey: .streamTypes) ?? [],
                vins: try container.decodeIfPresent([String].self, forKey: .vins) ?? []
            )
            self = .ready(ready)
        case "telemetry.latest":
            self = .telemetryLatest(try container.decodeIfPresent([FleetLatestSnapshot].self, forKey: .data) ?? [])
        case "drive.active":
            self = .driveActive(try container.decodeIfPresent([FleetActiveDriveSession].self, forKey: .data) ?? [])
        default:
            if let error = try container.decodeIfPresent(String.self, forKey: .error) {
                self = .error(error)
            } else {
                let dynamicContainer = try decoder.container(keyedBy: DynamicJSONCodingKey.self)
                var payload: [String: JSONValue] = [:]
                for key in dynamicContainer.allKeys {
                    payload[key.stringValue] = try dynamicContainer.decode(JSONValue.self, forKey: key)
                }
                self = .unknown(type: type, payload: payload)
            }
        }
    }
}

nonisolated struct FleetChargingOptions: Codable, Equatable, Sendable {
    var actions: [String]
    var chargeState: FleetLatestSnapshot?
    var vehicle: FleetVehicle

    enum CodingKeys: String, CodingKey {
        case actions
        case chargeState = "charge_state"
        case vehicle
    }

    init(actions: [String] = [], chargeState: FleetLatestSnapshot? = nil, vehicle: FleetVehicle) {
        self.actions = actions
        self.chargeState = chargeState
        self.vehicle = vehicle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actions = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
        chargeState = try container.decodeIfPresent(FleetLatestSnapshot.self, forKey: .chargeState)
        vehicle = try container.decode(FleetVehicle.self, forKey: .vehicle)
    }
}

nonisolated struct FleetSoftwareReleaseNote: Codable, Equatable, Identifiable, Sendable {
    var description: String?
    var imageURL: URL?
    var subtitle: String?
    var title: String

    var id: String {
        [title, subtitle, imageURL?.absoluteString]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    enum CodingKeys: String, CodingKey {
        case description
        case imageURL = "image_url"
        case subtitle
        case title
    }

    init(description: String? = nil, imageURL: URL? = nil, subtitle: String? = nil, title: String) {
        self.description = description
        self.imageURL = imageURL
        self.subtitle = subtitle
        self.title = title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        if let imageURLString = try container.decodeIfPresent(String.self, forKey: .imageURL) {
            imageURL = URL(string: imageURLString)
        } else {
            imageURL = nil
        }
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}

nonisolated struct FleetSoftwareUpdate: Codable, Equatable, Sendable {
    var availableVersion: String?
    var currentVersion: String?
    var downloadPercent: Double?
    var expectedDurationMinutes: Double?
    var expectedDurationSec: Int64?
    var installPercent: Double?
    var installable: Bool
    var releaseNotes: [FleetSoftwareReleaseNote]
    var releaseNotesCount: Int?
    var scheduledStartTimeMS: Int64?
    var sourceTimestamp: Int64?
    var status: String?
    var updateAvailable: Bool
    var updatedAt: Int64?
    var warningTimeRemainingMS: Int64?

    var scheduledStartDate: Date? { scheduledStartTimeMS.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var sourceDate: Date? { sourceTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var updatedAtDate: Date? { updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case availableVersion = "available_version"
        case currentVersion = "current_version"
        case downloadPercent = "download_percent"
        case expectedDurationMinutes = "expected_duration_minutes"
        case expectedDurationSec = "expected_duration_sec"
        case installPercent = "install_percent"
        case installable
        case releaseNotes = "release_notes"
        case releaseNotesCount = "release_notes_count"
        case scheduledStartTimeMS = "scheduled_start_time_ms"
        case sourceTimestamp = "source_timestamp"
        case status
        case updateAvailable = "update_available"
        case updatedAt = "updated_at"
        case warningTimeRemainingMS = "warning_time_remaining_ms"
    }

    init(
        availableVersion: String? = nil,
        currentVersion: String? = nil,
        downloadPercent: Double? = nil,
        expectedDurationMinutes: Double? = nil,
        expectedDurationSec: Int64? = nil,
        installPercent: Double? = nil,
        installable: Bool = false,
        releaseNotes: [FleetSoftwareReleaseNote] = [],
        releaseNotesCount: Int? = nil,
        scheduledStartTimeMS: Int64? = nil,
        sourceTimestamp: Int64? = nil,
        status: String? = nil,
        updateAvailable: Bool = false,
        updatedAt: Int64? = nil,
        warningTimeRemainingMS: Int64? = nil
    ) {
        self.availableVersion = availableVersion
        self.currentVersion = currentVersion
        self.downloadPercent = downloadPercent
        self.expectedDurationMinutes = expectedDurationMinutes
        self.expectedDurationSec = expectedDurationSec
        self.installPercent = installPercent
        self.installable = installable
        self.releaseNotes = releaseNotes
        self.releaseNotesCount = releaseNotesCount
        self.scheduledStartTimeMS = scheduledStartTimeMS
        self.sourceTimestamp = sourceTimestamp
        self.status = status
        self.updateAvailable = updateAvailable
        self.updatedAt = updatedAt
        self.warningTimeRemainingMS = warningTimeRemainingMS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        availableVersion = try container.decodeIfPresent(String.self, forKey: .availableVersion)
        currentVersion = try container.decodeIfPresent(String.self, forKey: .currentVersion)
        downloadPercent = container.decodeFlexibleDoubleIfPresent(forKey: .downloadPercent)
        expectedDurationMinutes = container.decodeFlexibleDoubleIfPresent(forKey: .expectedDurationMinutes)
        expectedDurationSec = container.decodeFlexibleInt64IfPresent(forKey: .expectedDurationSec)
        installPercent = container.decodeFlexibleDoubleIfPresent(forKey: .installPercent)
        installable = try container.decodeIfPresent(Bool.self, forKey: .installable) ?? false
        releaseNotes = try container.decodeIfPresent([FleetSoftwareReleaseNote].self, forKey: .releaseNotes) ?? []
        releaseNotesCount = try container.decodeIfPresent(Int.self, forKey: .releaseNotesCount)
        scheduledStartTimeMS = container.decodeFlexibleInt64IfPresent(forKey: .scheduledStartTimeMS)
        sourceTimestamp = container.decodeFlexibleInt64IfPresent(forKey: .sourceTimestamp)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        updateAvailable = try container.decodeIfPresent(Bool.self, forKey: .updateAvailable) ?? false
        updatedAt = container.decodeFlexibleInt64IfPresent(forKey: .updatedAt)
        warningTimeRemainingMS = container.decodeFlexibleInt64IfPresent(forKey: .warningTimeRemainingMS)
    }
}

nonisolated struct FleetSoftwareInstallRequest: Encodable, Equatable, Sendable {
    var offsetSec: Int

    enum CodingKeys: String, CodingKey {
        case offsetSec = "offset_sec"
    }

    init(offsetSec: Int = 0) {
        self.offsetSec = min(max(offsetSec, 0), 604_800)
    }
}

nonisolated enum FleetNotificationEvent {
    static let all = "*"
    static let chargingEnded = "charging.ended"
    static let chargingInterrupted = "charging.interrupted"
    static let chargingStarted = "charging.started"
    static let climateReady = "climate.ready"
    static let driveEnded = "drive.ended"
    static let driveStarted = "drive.started"
    static let telemetryAlert = "telemetry.alert"

    static let supportedEvents = [
        driveStarted,
        driveEnded,
        chargingStarted,
        chargingEnded,
        chargingInterrupted,
        climateReady,
        telemetryAlert
    ]
    static let defaultEvents = [driveStarted]
}

nonisolated struct FleetDeviceNotificationWebhook: Codable, Equatable, Identifiable, Sendable {
    var createdAt: Int64
    var description: String?
    var deviceID: String
    var deviceName: String?
    var enabled: Bool
    var events: [String]
    var failureCount: Int
    var id: String
    var lastFailureAt: Int64?
    var lastSuccessAt: Int64?
    var platform: String?
    var secret: String?
    var updatedAt: Int64
    var url: URL
    var vins: [String]

    var createdAtDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000) }
    var updatedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000) }
    var lastFailureDate: Date? { lastFailureAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var lastSuccessDate: Date? { lastSuccessAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case description
        case deviceID = "device_id"
        case deviceName = "device_name"
        case enabled
        case events
        case failureCount = "failure_count"
        case id
        case lastFailureAt = "last_failure_at"
        case lastSuccessAt = "last_success_at"
        case platform
        case secret
        case updatedAt = "updated_at"
        case url
        case vins
    }

    init(
        createdAt: Int64,
        description: String?,
        deviceID: String,
        deviceName: String?,
        enabled: Bool,
        events: [String],
        failureCount: Int,
        id: String,
        lastFailureAt: Int64?,
        lastSuccessAt: Int64?,
        platform: String?,
        secret: String?,
        updatedAt: Int64,
        url: URL,
        vins: [String]
    ) {
        self.createdAt = createdAt
        self.description = description
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.enabled = enabled
        self.events = events
        self.failureCount = failureCount
        self.id = id
        self.lastFailureAt = lastFailureAt
        self.lastSuccessAt = lastSuccessAt
        self.platform = platform
        self.secret = secret
        self.updatedAt = updatedAt
        self.url = url
        self.vins = vins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = container.decodeFlexibleInt64IfPresent(forKey: .createdAt) ?? 0
        description = try container.decodeIfPresent(String.self, forKey: .description)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
        failureCount = try container.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        id = try container.decode(String.self, forKey: .id)
        lastFailureAt = container.decodeFlexibleInt64IfPresent(forKey: .lastFailureAt)
        lastSuccessAt = container.decodeFlexibleInt64IfPresent(forKey: .lastSuccessAt)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        secret = try container.decodeIfPresent(String.self, forKey: .secret)
        updatedAt = container.decodeFlexibleInt64IfPresent(forKey: .updatedAt) ?? createdAt
        url = try container.decode(URL.self, forKey: .url)
        vins = try container.decodeIfPresent([String].self, forKey: .vins) ?? []
    }
}

nonisolated struct FleetDeviceNotificationWebhookCreateRequest: Encodable, Equatable, Sendable {
    var description: String?
    var deviceID: String
    var deviceName: String?
    var enabled: Bool
    var events: [String]
    var platform: String
    var url: URL
    var vins: [String]

    init(
        deviceID: String,
        url: URL,
        events: [String] = FleetNotificationEvent.defaultEvents,
        vins: [String] = [],
        description: String? = nil,
        deviceName: String? = nil,
        enabled: Bool = true,
        platform: String = "ios"
    ) {
        self.description = description
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.enabled = enabled
        self.events = events
        self.platform = platform
        self.url = url
        self.vins = vins
    }
}

nonisolated struct FleetDeviceNotificationWebhookCreateForDeviceRequest: Encodable, Equatable, Sendable {
    var description: String?
    var deviceName: String?
    var enabled: Bool
    var events: [String]
    var platform: String
    var url: URL
    var vins: [String]

    init(
        url: URL,
        events: [String] = FleetNotificationEvent.defaultEvents,
        vins: [String] = [],
        description: String? = nil,
        deviceName: String? = nil,
        enabled: Bool = true,
        platform: String = "ios"
    ) {
        self.description = description
        self.deviceName = deviceName
        self.enabled = enabled
        self.events = events
        self.platform = platform
        self.url = url
        self.vins = vins
    }
}

nonisolated struct FleetDeviceNotificationWebhookUpdateRequest: Encodable, Equatable, Sendable {
    var description: String?
    var deviceName: String?
    var enabled: Bool?
    var events: [String]?
    var platform: String?
    var url: URL?
    var vins: [String]?

    init(
        url: URL? = nil,
        events: [String]? = nil,
        vins: [String]? = nil,
        description: String? = nil,
        deviceName: String? = nil,
        enabled: Bool? = nil,
        platform: String? = nil
    ) {
        self.description = description
        self.deviceName = deviceName
        self.enabled = enabled
        self.events = events
        self.platform = platform
        self.url = url
        self.vins = vins
    }
}

nonisolated struct FleetDeviceNotificationWebhookTestRequest: Encodable, Equatable, Sendable {
    var event: String
    var vin: String?

    init(event: String = FleetNotificationEvent.driveStarted, vin: String? = nil) {
        self.event = event
        self.vin = vin
    }
}

nonisolated struct FleetWebhook: Codable, Equatable, Identifiable, Sendable {
    var createdAt: Int64
    var description: String?
    var enabled: Bool
    var events: [String]
    var failureCount: Int
    var id: String
    var lastFailureAt: Int64?
    var lastSuccessAt: Int64?
    var secret: String?
    var updatedAt: Int64
    var url: URL
    var vins: [String]

    var createdAtDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000) }
    var updatedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000) }
    var lastFailureDate: Date? { lastFailureAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }
    var lastSuccessDate: Date? { lastSuccessAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case description
        case enabled
        case events
        case failureCount = "failure_count"
        case id
        case lastFailureAt = "last_failure_at"
        case lastSuccessAt = "last_success_at"
        case secret
        case updatedAt = "updated_at"
        case url
        case vins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = container.decodeFlexibleInt64IfPresent(forKey: .createdAt) ?? 0
        description = try container.decodeIfPresent(String.self, forKey: .description)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
        failureCount = try container.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        id = try container.decode(String.self, forKey: .id)
        lastFailureAt = container.decodeFlexibleInt64IfPresent(forKey: .lastFailureAt)
        lastSuccessAt = container.decodeFlexibleInt64IfPresent(forKey: .lastSuccessAt)
        secret = try container.decodeIfPresent(String.self, forKey: .secret)
        updatedAt = container.decodeFlexibleInt64IfPresent(forKey: .updatedAt) ?? createdAt
        url = try container.decode(URL.self, forKey: .url)
        vins = try container.decodeIfPresent([String].self, forKey: .vins) ?? []
    }
}

nonisolated struct FleetWebhookCreateRequest: Encodable, Equatable, Sendable {
    var description: String?
    var enabled: Bool
    var events: [String]
    var url: URL
    var vins: [String]

    init(url: URL, events: [String], vins: [String] = [], description: String? = nil, enabled: Bool = true) {
        self.description = description
        self.enabled = enabled
        self.events = events
        self.url = url
        self.vins = vins
    }
}

nonisolated struct FleetWebhookUpdateRequest: Encodable, Equatable, Sendable {
    var description: String?
    var enabled: Bool?
    var events: [String]?
    var url: URL?
    var vins: [String]?

    init(url: URL? = nil, events: [String]? = nil, vins: [String]? = nil, description: String? = nil, enabled: Bool? = nil) {
        self.description = description
        self.enabled = enabled
        self.events = events
        self.url = url
        self.vins = vins
    }
}

nonisolated struct FleetWebhookDeliveryResult: Codable, Equatable, Sendable {
    var ok: Bool
    var status: Int?
    var error: String?
    var metadata: [String: JSONValue]

    private static let reservedKeys: Set<String> = ["ok", "status", "error"]

    init(ok: Bool, status: Int? = nil, error: String? = nil, metadata: [String: JSONValue] = [:]) {
        self.ok = ok
        self.status = status
        self.error = error
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicJSONCodingKey.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: DynamicJSONCodingKey("ok")) ?? false
        status = try container.decodeIfPresent(Int.self, forKey: DynamicJSONCodingKey("status"))
        error = try container.decodeIfPresent(String.self, forKey: DynamicJSONCodingKey("error"))

        var metadata: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.reservedKeys.contains(key.stringValue) {
            metadata[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.metadata = metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicJSONCodingKey.self)
        try container.encode(ok, forKey: DynamicJSONCodingKey("ok"))
        try container.encodeIfPresent(status, forKey: DynamicJSONCodingKey("status"))
        try container.encodeIfPresent(error, forKey: DynamicJSONCodingKey("error"))

        for (key, value) in metadata where !Self.reservedKeys.contains(key) {
            try container.encode(value, forKey: DynamicJSONCodingKey(key))
        }
    }
}

private struct DynamicJSONCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
