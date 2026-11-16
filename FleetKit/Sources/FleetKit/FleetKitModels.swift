import Foundation

/// Minimal, decode-tolerant models for the endpoints the intents use. These
/// mirror a subset of the app's `FleetAPIModels`, kept independent so the
/// package stays self-contained.

public struct FleetVehicleInfo: Decodable, Sendable, Identifiable {
    public let vin: String
    public let displayName: String?
    public let vehicleTag: String?
    /// Raw Tessie `vehicle_config.car_type`, such as `modely` or `cybertruck`.
    public let carType: String?
    /// Raw Tessie `vehicle_config.exterior_color`, such as `PearlWhite`.
    public let exteriorColor: String?

    var hasSeatCooling: Bool?
    var canActuateTrunks: Bool?
    var canAcceptNavigationRequests: Bool?

    var rosterCharge: FleetSnapshotInfo?
    var rosterClimate: FleetSnapshotInfo?

    func afterCommand(invalidatingCharge: Bool, invalidatingClimate: Bool) -> Self {
        var vehicle = self
        if invalidatingCharge { vehicle.rosterCharge = nil }
        if invalidatingClimate, let climate = rosterClimate {
            // A command invalidates the setpoint and HVAC state. Ambient temperatures keep their observation time.
            vehicle.rosterClimate = FleetSnapshotInfo(
                vin: vin, insideTemp: climate.insideTemp, outsideTemp: climate.outsideTemp,
                updatedAt: climate.updatedAt, temperatureInFahrenheit: climate.temperatureInFahrenheit
            )
        }
        return vehicle
    }

    public var id: String { vin }
    public var name: String { displayName ?? vehicleTag ?? vin }

    /// Marketing model name derived from `carType` ("Model Y", "Cybertruck").
    public var modelName: String? {
        guard let carType = carType?.lowercased(), !carType.isEmpty else { return nil }
        switch carType {
        case "models", "models2", "lychee": return "Model S"
        case "model3": return "Model 3"
        case "modelx", "tamarind": return "Model X"
        case "modely": return "Model Y"
        case "cybertruck": return "Cybertruck"
        default:
            if carType.hasPrefix("model"), let suffix = carType.dropFirst(5).first {
                return "Model \(String(suffix).uppercased())"
            }
            return carType.capitalized
        }
    }

    /// Readable paint name derived from `exteriorColor` ("PearlWhite" → "Pearl White").
    public var colorName: String? {
        guard let exteriorColor, !exteriorColor.isEmpty else { return nil }
        var words = ""
        for character in exteriorColor {
            if character.isUppercase, !words.isEmpty, words.last != " " {
                words.append(" ")
            }
            words.append(character)
        }
        return words
    }

    enum CodingKeys: String, CodingKey {
        case vin
        case displayName = "display_name"
        case vehicleTag = "vehicle_tag"
        case carType = "car_type"
        case exteriorColor = "exterior_color"
    }

    public init(
        vin: String,
        displayName: String?,
        vehicleTag: String? = nil,
        carType: String? = nil,
        exteriorColor: String? = nil,
        hasSeatCooling: Bool? = nil,
        canActuateTrunks: Bool? = nil,
        canAcceptNavigationRequests: Bool? = nil
    ) {
        self.vin = vin
        self.displayName = displayName
        self.vehicleTag = vehicleTag
        self.carType = carType
        self.exteriorColor = exteriorColor
        self.hasSeatCooling = hasSeatCooling
        self.canActuateTrunks = canActuateTrunks
        self.canAcceptNavigationRequests = canAcceptNavigationRequests
    }
}

public struct FleetSnapshotInfo: Codable, Sendable {
    public let vin: String
    public let batteryLevel: Double?
    public let batteryRangeMiles: Double?
    public let chargeLimitSOC: Double?
    public let chargingState: String?
    public let chargerPowerKW: Double?
    public let chargePortDoorOpen: Bool?
    public let locked: Bool?
    public let sentryModeOn: Bool?
    public let chargeRateMPH: Double?
    public let timeToFullCharge: Double?
    public let insideTemp: Double?
    public let outsideTemp: Double?
    public let targetTemp: Double?
    public let hvacOn: Bool?
    public let latitude: Double?
    public let longitude: Double?
    public let odometer: Double?
    public let speed: Double?
    public let updatedAt: Int64?
    /// Raw climate keeper state: a telemetry enum string (e.g. `ClimateKeeperModeDog`)
    /// or the vehicle_data string/number form (`2` = dog, `0` = off).
    public let climateKeeperMode: String?
    public let defrostMode: String?
    public let tires: FleetTirePressuresInfo?
    /// `true` when temperatures are in °F (the car's display units), `false` for °C, `nil` if unknown.
    public let temperatureInFahrenheit: Bool?
    /// Gear from `drive_state.shift_state` ("P", "D", "R", "N"); `nil` when parked and asleep.
    public let shiftState: String?
    /// Human-readable names of open doors, windows, frunk, and trunk ("Driver door", "Trunk").
    public let openClosures: [String]?
    /// Seat heater levels 0–3 keyed by seat ("Driver", "Passenger", "Rear left"…).
    public let seatHeaterLevels: [String: Int]?
    public let steeringWheelHeaterOn: Bool?

    public var updatedAtDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    /// A roster read can be recent even when the parked car's observation is old.
    var isRecentRosterObservation: Bool {
        guard let updatedAtDate else { return false }
        return (0...30).contains(Date.now.timeIntervalSince(updatedAtDate))
    }

    /// Whether climate keeper reports pet (dog) mode.
    public var petModeOn: Bool? {
        guard let climateKeeperMode else { return nil }
        let lowered = climateKeeperMode.lowercased()
        return lowered.contains("dog") || lowered == "2"
    }

    enum CodingKeys: String, CodingKey {
        case vin
        case batteryLevel = "battery_level"
        case batteryRangeMiles = "battery_range"
        case chargeLimitSOC = "charge_limit_soc"
        case chargingState = "charging_state"
        case chargerPowerKW = "charger_power"
        case chargePortDoorOpen = "charge_port_door_open"
        case locked
        case sentryModeOn = "sentry_mode"
        case chargeRateMPH = "charge_rate_mph"
        case timeToFullCharge = "time_to_full_charge"
        case insideTemp = "inside_temp"
        case outsideTemp = "outside_temp"
        case targetTemp = "target_temp"
        case hvacOn = "hvac_on"
        case latitude
        case longitude
        case odometer
        case speed
        case updatedAt = "updated_at"
        case climateKeeperMode = "climate_keeper_mode"
        case defrostMode = "defrost_mode"
        case tires
        case shiftState = "shift_state"
        case temperatureInFahrenheit, openClosures, seatHeaterLevels, steeringWheelHeaterOn
    }

    init(
        vin: String,
        batteryLevel: Double? = nil,
        batteryRangeMiles: Double? = nil,
        chargeLimitSOC: Double? = nil,
        chargingState: String? = nil,
        chargerPowerKW: Double? = nil,
        chargePortDoorOpen: Bool? = nil,
        locked: Bool? = nil,
        sentryModeOn: Bool? = nil,
        chargeRateMPH: Double? = nil,
        timeToFullCharge: Double? = nil,
        insideTemp: Double? = nil,
        outsideTemp: Double? = nil,
        targetTemp: Double? = nil,
        hvacOn: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        odometer: Double? = nil,
        speed: Double? = nil,
        updatedAt: Int64? = nil,
        climateKeeperMode: String? = nil,
        defrostMode: String? = nil,
        tires: FleetTirePressuresInfo? = nil,
        temperatureInFahrenheit: Bool? = nil,
        shiftState: String? = nil,
        openClosures: [String]? = nil,
        seatHeaterLevels: [String: Int]? = nil,
        steeringWheelHeaterOn: Bool? = nil
    ) {
        self.vin = vin
        self.batteryLevel = batteryLevel
        self.batteryRangeMiles = batteryRangeMiles
        self.chargeLimitSOC = chargeLimitSOC
        self.chargingState = chargingState
        self.chargerPowerKW = chargerPowerKW
        self.chargePortDoorOpen = chargePortDoorOpen
        self.locked = locked
        self.sentryModeOn = sentryModeOn
        self.chargeRateMPH = chargeRateMPH
        self.timeToFullCharge = timeToFullCharge
        self.insideTemp = insideTemp
        self.outsideTemp = outsideTemp
        self.targetTemp = targetTemp
        self.hvacOn = hvacOn
        self.latitude = latitude
        self.longitude = longitude
        self.odometer = odometer
        self.speed = speed
        self.updatedAt = updatedAt
        self.climateKeeperMode = climateKeeperMode
        self.defrostMode = defrostMode
        self.tires = tires
        self.temperatureInFahrenheit = temperatureInFahrenheit
        self.shiftState = shiftState
        self.openClosures = openClosures
        self.seatHeaterLevels = seatHeaterLevels
        self.steeringWheelHeaterOn = steeringWheelHeaterOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vin = try c.decodeIfPresent(String.self, forKey: .vin) ?? ""
        batteryLevel = c.flexibleDouble(.batteryLevel)
        batteryRangeMiles = c.flexibleDouble(.batteryRangeMiles)
        chargeLimitSOC = c.flexibleDouble(.chargeLimitSOC)
        chargingState = try c.decodeIfPresent(String.self, forKey: .chargingState)
        chargerPowerKW = c.flexibleDouble(.chargerPowerKW)
        chargePortDoorOpen = try c.decodeIfPresent(Bool.self, forKey: .chargePortDoorOpen)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked)
        sentryModeOn = try c.decodeIfPresent(Bool.self, forKey: .sentryModeOn)
        chargeRateMPH = c.flexibleDouble(.chargeRateMPH)
        timeToFullCharge = c.flexibleDouble(.timeToFullCharge)
        insideTemp = c.flexibleDouble(.insideTemp)
        outsideTemp = c.flexibleDouble(.outsideTemp)
        targetTemp = c.flexibleDouble(.targetTemp)
        hvacOn = try c.decodeIfPresent(Bool.self, forKey: .hvacOn)
        latitude = c.flexibleDouble(.latitude)
        longitude = c.flexibleDouble(.longitude)
        odometer = c.flexibleDouble(.odometer)
        speed = c.flexibleDouble(.speed)
        updatedAt = c.flexibleInt64(.updatedAt)
        climateKeeperMode = c.flexibleEnumString(.climateKeeperMode)
        defrostMode = c.flexibleEnumString(.defrostMode)
        tires = try c.decodeIfPresent(FleetTirePressuresInfo.self, forKey: .tires)
        temperatureInFahrenheit = try c.decodeIfPresent(Bool.self, forKey: .temperatureInFahrenheit)
        shiftState = try c.decodeIfPresent(String.self, forKey: .shiftState)
        openClosures = try c.decodeIfPresent([String].self, forKey: .openClosures)
        seatHeaterLevels = try c.decodeIfPresent([String: Int].self, forKey: .seatHeaterLevels)
        steeringWheelHeaterOn = try c.decodeIfPresent(Bool.self, forKey: .steeringWheelHeaterOn)
    }
}

/// TPMS readings from the live snapshot. `nil` until the backend has received
/// a TPMS reading; values use PSI regardless of the vehicle's display settings.
public struct FleetTirePressuresInfo: Codable, Sendable {
    public let frontLeftPSI: Double?
    public let frontRightPSI: Double?
    public let rearLeftPSI: Double?
    public let rearRightPSI: Double?
    public let hardWarnings: Int?
    public let softWarnings: Int?
    public let lastMeasuredAt: Int64?

    public var measuredAtDate: Date? {
        lastMeasuredAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    public var displaySummary: String? {
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
        case rearLeftPSI = "rear_left_psi"
        case rearRightPSI = "rear_right_psi"
        case hardWarnings = "hard_warnings"
        case softWarnings = "soft_warnings"
        case lastMeasuredAt = "last_measured_at"
    }

    init(
        frontLeftPSI: Double?,
        frontRightPSI: Double?,
        rearLeftPSI: Double?,
        rearRightPSI: Double?,
        hardWarnings: Int? = nil,
        softWarnings: Int? = nil,
        lastMeasuredAt: Int64? = nil
    ) {
        self.frontLeftPSI = frontLeftPSI
        self.frontRightPSI = frontRightPSI
        self.rearLeftPSI = rearLeftPSI
        self.rearRightPSI = rearRightPSI
        self.hardWarnings = hardWarnings
        self.softWarnings = softWarnings
        self.lastMeasuredAt = lastMeasuredAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frontLeftPSI = c.flexibleDouble(.frontLeftPSI)
        frontRightPSI = c.flexibleDouble(.frontRightPSI)
        rearLeftPSI = c.flexibleDouble(.rearLeftPSI)
        rearRightPSI = c.flexibleDouble(.rearRightPSI)
        hardWarnings = c.flexibleInt64(.hardWarnings).map { Int($0) }
        softWarnings = c.flexibleInt64(.softWarnings).map { Int($0) }
        lastMeasuredAt = c.flexibleInt64(.lastMeasuredAt)
    }

    private static func formatPSI(_ value: Double) -> String {
        "\(Int(value.rounded())) PSI"
    }
}

public struct FleetUserInfo: Decodable, Sendable {
    public let units: String?

    init(units: String?) {
        self.units = units
    }
}

extension KeyedDecodingContainer {
    /// Tolerates values arriving as either JSON numbers or numeric strings.
    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Double(string)
        }
        return nil
    }

    /// Tolerates enum-ish values arriving as either strings or numbers
    /// (e.g. `climate_keeper_mode`: "ClimateKeeperModeDog" or 2).
    func flexibleEnumString(_ key: Key) -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let int = try? decodeIfPresent(Int.self, forKey: key) {
            return String(int)
        }
        if let double = try? decodeIfPresent(Double.self, forKey: key) {
            return String(double)
        }
        return nil
    }
}
