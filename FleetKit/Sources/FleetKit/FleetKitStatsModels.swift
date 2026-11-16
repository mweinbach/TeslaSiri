import Foundation

/// A completed charging session returned by Tessie's `/{vin}/charges` endpoint.
public struct FleetChargeInfo: Encodable, Sendable, Identifiable {
    public let sessionID: String
    public let vin: String
    public let startedAt: Int64
    public let endedAt: Int64?
    public let location: String?
    public let latitude: Double?
    public let longitude: Double?
    public let isSupercharger: Bool
    public let odometerMiles: Double?
    public let energyAddedKWH: Double?
    public let energyUsedKWH: Double?
    public let milesAdded: Double?
    public let startingBatteryPercent: Int?
    public let endingBatteryPercent: Int?
    public let cost: Double?
    public let currency: String?

    public var id: String { sessionID }
    public var startedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(startedAt) / 1000) }
    public var endedAtDate: Date? { endedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

    public var durationMinutes: Int? {
        guard let endedAt else { return nil }
        return Int(max(endedAt - startedAt, 0) / 60_000)
    }

    public init(
        sessionID: String,
        vin: String,
        startedAt: Int64,
        endedAt: Int64?,
        location: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isSupercharger: Bool,
        odometerMiles: Double? = nil,
        energyAddedKWH: Double?,
        energyUsedKWH: Double? = nil,
        milesAdded: Double?,
        startingBatteryPercent: Int?,
        endingBatteryPercent: Int?,
        cost: Double?,
        currency: String? = nil
    ) {
        self.sessionID = sessionID
        self.vin = vin
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.isSupercharger = isSupercharger
        self.odometerMiles = odometerMiles
        self.energyAddedKWH = energyAddedKWH
        self.energyUsedKWH = energyUsedKWH
        self.milesAdded = milesAdded
        self.startingBatteryPercent = startingBatteryPercent
        self.endingBatteryPercent = endingBatteryPercent
        self.cost = cost
        self.currency = currency
    }
}

/// Combined battery pack health and pack telemetry from Tessie's `/battery_health`
/// and `/{vin}/battery` endpoints.
public struct FleetBatteryHealthInfo: Sendable {
    public let vin: String
    public let healthPercent: Double?
    public let degradationPercent: Double?
    public let usableCapacityKWH: Double?
    public let originalCapacityKWH: Double?
    public let maxRangeMiles: Double?
    public let maxIdealRangeMiles: Double?
    public let odometerMiles: Double?
    public let energyRemainingKWH: Double?
    public let lifetimeEnergyUsedKWH: Double?
    public let phantomDrainPercent: Double?
    public let packVoltage: Double?
    public let packCurrentAmps: Double?
    public let moduleTempMinF: Double?
    public let moduleTempMaxF: Double?

    public init(
        vin: String,
        healthPercent: Double? = nil,
        degradationPercent: Double? = nil,
        usableCapacityKWH: Double? = nil,
        originalCapacityKWH: Double? = nil,
        maxRangeMiles: Double? = nil,
        maxIdealRangeMiles: Double? = nil,
        odometerMiles: Double? = nil,
        energyRemainingKWH: Double? = nil,
        lifetimeEnergyUsedKWH: Double? = nil,
        phantomDrainPercent: Double? = nil,
        packVoltage: Double? = nil,
        packCurrentAmps: Double? = nil,
        moduleTempMinF: Double? = nil,
        moduleTempMaxF: Double? = nil
    ) {
        self.vin = vin
        self.healthPercent = healthPercent
        self.degradationPercent = degradationPercent
        self.usableCapacityKWH = usableCapacityKWH
        self.originalCapacityKWH = originalCapacityKWH
        self.maxRangeMiles = maxRangeMiles
        self.maxIdealRangeMiles = maxIdealRangeMiles
        self.odometerMiles = odometerMiles
        self.energyRemainingKWH = energyRemainingKWH
        self.lifetimeEnergyUsedKWH = lifetimeEnergyUsedKWH
        self.phantomDrainPercent = phantomDrainPercent
        self.packVoltage = packVoltage
        self.packCurrentAmps = packCurrentAmps
        self.moduleTempMinF = moduleTempMinF
        self.moduleTempMaxF = moduleTempMaxF
    }
}

/// Energy consumption and range usage since the last completed charge from
/// Tessie's `/{vin}/consumption_since_charge` endpoint.
public struct FleetConsumptionInfo: Sendable {
    public let lastChargeAt: Int64?
    public let distanceDrivenMiles: Double?
    public let batteryPercentUsed: Double?
    public let batteryPercentUsedByDriving: Double?
    public let ratedRangeUsedMiles: Double?
    public let ratedRangeUsedByDrivingMiles: Double?
    public let energyUsedKWH: Double?
    public let energyUsedByDrivingKWH: Double?

    public var lastChargeDate: Date? {
        lastChargeAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    public var idleEnergyUsedKWH: Double? {
        guard let total = energyUsedKWH, let driving = energyUsedByDrivingKWH else { return nil }
        return max(total - driving, 0)
    }

    public var idleBatteryPercentUsed: Double? {
        guard let total = batteryPercentUsed, let driving = batteryPercentUsedByDriving else { return nil }
        return max(total - driving, 0)
    }

    public init(
        lastChargeAt: Int64? = nil,
        distanceDrivenMiles: Double? = nil,
        batteryPercentUsed: Double? = nil,
        batteryPercentUsedByDriving: Double? = nil,
        ratedRangeUsedMiles: Double? = nil,
        ratedRangeUsedByDrivingMiles: Double? = nil,
        energyUsedKWH: Double? = nil,
        energyUsedByDrivingKWH: Double? = nil
    ) {
        self.lastChargeAt = lastChargeAt
        self.distanceDrivenMiles = distanceDrivenMiles
        self.batteryPercentUsed = batteryPercentUsed
        self.batteryPercentUsedByDriving = batteryPercentUsedByDriving
        self.ratedRangeUsedMiles = ratedRangeUsedMiles
        self.ratedRangeUsedByDrivingMiles = ratedRangeUsedByDrivingMiles
        self.energyUsedKWH = energyUsedKWH
        self.energyUsedByDrivingKWH = energyUsedByDrivingKWH
    }
}
