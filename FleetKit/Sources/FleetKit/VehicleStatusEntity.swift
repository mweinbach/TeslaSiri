import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation

/// A point-in-time, human-readable status snapshot for a vehicle. Conforms to
/// `IndexedEntity` and `SyncableEntity` so Siri AI, Shortcuts, and Spotlight
/// can inspect individual telemetry properties directly.
public struct VehicleStatusEntity: AppEntity, IndexedEntity, SyncableEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Vehicle Status",
        synonyms: ["Car Status", "My Car Status", "Tesla Status"]
    )
    public static let defaultQuery = VehicleStatusEntityQuery()
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    /// "status:<VIN>" — one current-status entity per vehicle. Namespaced so it
    /// can't collide with other VIN-keyed entity types in the shared Spotlight
    /// index, where the identifier is the primary key and collisions overwrite.
    public let id: String

    @Property(title: "VIN", description: "The car's vehicle identification number, for the app's own use.", visibility: .internal)
    public var vin: String

    @Property(
        title: "Vehicle Name",
        description: "The owner's name for this car, such as \"Midnight\".",
        indexingKey: \.title
    )
    public var vehicleName: String

    @Property(title: "Battery Level", description: "State of charge as a whole percent from 0 to 100, such as 72.")
    public var batteryPercent: Int?

    @Property(title: "Estimated Range", description: "Estimated driving range left at the current charge, in miles.")
    public var batteryRangeMiles: Double?

    @Property(title: "Charge Limit", description: "The percent the car stops charging at, from 50 to 100.")
    public var chargeLimitPercent: Int?

    @Property(
        title: "Charging State",
        description: "Tesla's charging state: Charging, Complete, Stopped (plugged in but not charging), Starting, NoPower, or Disconnected (unplugged)."
    )
    public var chargingState: String?

    @Property(title: "Charger Power", description: "Power flowing into the car while charging, in kilowatts. 0 when not charging.")
    public var chargerPowerKW: Double?

    @Property(title: "Charge Rate", description: "Range being added while charging, in miles per hour of charging.")
    public var chargeRateMPH: Double?

    @Property(title: "Time to Full", description: "Minutes until charging reaches the charge limit, while charging.")
    public var minutesToFullCharge: Int?

    @Property(title: "Charge Port Open", description: "Whether the charge port door is open.")
    public var chargePortDoorOpen: Bool?

    @Property(title: "Locked", description: "Whether the doors are locked.")
    public var isLocked: Bool?

    @Property(
        title: "Open Doors and Windows",
        description: "Comma-separated list of open doors, windows, frunk, and trunk, such as \"Trunk, Driver window\". \"None\" when everything is closed; empty when the car didn't report it."
    )
    public var openClosures: String?

    @Property(title: "Sentry Mode On", description: "Whether Sentry Mode (camera security monitoring while parked) is on.")
    public var sentryModeOn: Bool?

    @Property(title: "Climate On", description: "Whether the cabin heating and air conditioning is running.")
    public var isClimateOn: Bool?

    @Property(title: "Dog Mode On", description: "Whether Dog Mode is keeping the cabin conditioned for a pet.")
    public var dogModeOn: Bool?

    @Property(title: "Max Defrost On", description: "Whether max defrost (windshield and cabin defrost at full power) is on.")
    public var maxDefrostOn: Bool?

    @Property(
        title: "Seat Heaters",
        description: "Seat heater levels from 0 (off) to 3 (high), such as \"Driver 3, Passenger 0\"."
    )
    public var seatHeaterSummary: String?

    @Property(title: "Steering Wheel Heater On", description: "Whether the heated steering wheel is on.")
    public var steeringWheelHeaterOn: Bool?

    @Property(
        title: "Temperature Unit",
        description: "The unit of the cabin, outside, and target temperatures: °F or °C, matching the car's display setting."
    )
    public var temperatureUnit: String?

    @Property(title: "Cabin Temperature", description: "Current temperature inside the car, in the Temperature Unit.")
    public var insideTemp: Double?

    @Property(title: "Outside Temperature", description: "Current temperature outside the car, in the Temperature Unit.")
    public var outsideTemp: Double?

    @Property(title: "Target Cabin Temperature", description: "The climate setpoint the cabin is heating or cooling to, in the Temperature Unit.")
    public var targetTemp: Double?

    @Property(title: "Odometer", description: "Total distance the car has driven, in miles.")
    public var odometerMiles: Double?

    @Property(title: "Gear", description: "Current gear: P (park), D (drive), R (reverse), or N (neutral). Empty when the car is asleep or parked.")
    public var gear: String?

    @Property(title: "Speed", description: "Current speed in miles per hour. Empty or 0 when parked.")
    public var speedMPH: Double?

    @Property(
        title: "Location",
        description: "Street address or place name near the car's last reported position, when known.",
        authenticationPolicy: .requiresAuthentication
    )
    public var locationAddress: String?

    @Property(
        title: "Latitude",
        description: "Latitude of the car's last reported position, in decimal degrees.",
        authenticationPolicy: .requiresAuthentication
    )
    public var latitude: Double?

    @Property(
        title: "Longitude",
        description: "Longitude of the car's last reported position, in decimal degrees.",
        authenticationPolicy: .requiresAuthentication
    )
    public var longitude: Double?

    @Property(title: "Front Left Tire", description: "Front left tire pressure in PSI, such as 42.")
    public var frontLeftTirePSI: Double?

    @Property(title: "Front Right Tire", description: "Front right tire pressure in PSI.")
    public var frontRightTirePSI: Double?

    @Property(title: "Rear Left Tire", description: "Rear left tire pressure in PSI.")
    public var rearLeftTirePSI: Double?

    @Property(title: "Rear Right Tire", description: "Rear right tire pressure in PSI.")
    public var rearRightTirePSI: Double?

    @Property(title: "Tire Pressure Summary", description: "All four tire pressures in PSI, such as \"FL 42 PSI, FR 41 PSI, RL 42 PSI, RR 42 PSI\".")
    public var tireSummary: String?

    @Property(title: "Last Updated", description: "When the car last reported this data. Older readings can be stale if the car is asleep.")
    public var updatedAt: Date?

    public init(snapshot: FleetSnapshotInfo, vehicleName: String, locationAddress: String? = nil) {
        self.id = Self.entityID(forVIN: snapshot.vin)
        self.vin = snapshot.vin
        self.vehicleName = vehicleName
        self.batteryPercent = snapshot.batteryLevel.map { Int($0.rounded()) }
        self.batteryRangeMiles = snapshot.batteryRangeMiles
        self.chargeLimitPercent = snapshot.chargeLimitSOC.map { Int($0.rounded()) }
        self.chargingState = snapshot.chargingState
        self.chargerPowerKW = snapshot.chargerPowerKW
        self.chargeRateMPH = snapshot.chargeRateMPH
        self.minutesToFullCharge = snapshot.timeToFullCharge.flatMap { $0 > 0 ? Int(($0 * 60).rounded()) : nil }
        self.chargePortDoorOpen = snapshot.chargePortDoorOpen
        self.isLocked = snapshot.locked
        self.openClosures = snapshot.openClosures.map { $0.isEmpty ? "None" : $0.joined(separator: ", ") }
        self.sentryModeOn = snapshot.sentryModeOn
        self.isClimateOn = snapshot.hvacOn
        self.dogModeOn = snapshot.petModeOn
        // vehicle_data reports 0 (off), 1 (normal), or 2 (max); telemetry reports e.g. "DefrostModeStateMax".
        self.maxDefrostOn = snapshot.defrostMode.map { $0 == "2" || $0.lowercased().contains("max") }
        self.seatHeaterSummary = snapshot.seatHeaterLevels.map { levels in
            let order = ["Driver", "Passenger", "Rear left", "Rear center", "Rear right"]
            return order.compactMap { seat in levels[seat].map { "\(seat) \($0)" } }.joined(separator: ", ")
        }
        self.steeringWheelHeaterOn = snapshot.steeringWheelHeaterOn
        self.temperatureUnit = snapshot.temperatureInFahrenheit.map { $0 ? "°F" : "°C" }
        self.insideTemp = snapshot.insideTemp
        self.outsideTemp = snapshot.outsideTemp
        self.targetTemp = snapshot.targetTemp
        self.odometerMiles = snapshot.odometer
        self.gear = snapshot.shiftState
        self.speedMPH = snapshot.speed
        self.locationAddress = locationAddress
        self.latitude = snapshot.latitude
        self.longitude = snapshot.longitude
        self.frontLeftTirePSI = snapshot.tires?.frontLeftPSI
        self.frontRightTirePSI = snapshot.tires?.frontRightPSI
        self.rearLeftTirePSI = snapshot.tires?.rearLeftPSI
        self.rearRightTirePSI = snapshot.tires?.rearRightPSI
        self.tireSummary = snapshot.tires?.displaySummary
        self.updatedAt = snapshot.updatedAtDate
    }

    public static func entityID(forVIN vin: String) -> String {
        "status:\(vin)"
    }

    /// Accepts bare VINs too so identifiers saved before namespacing still resolve.
    public static func vin(fromEntityID id: String) -> String {
        id.hasPrefix("status:") ? String(id.dropFirst("status:".count)) : id
    }

    public var batteryDisplay: String {
        batteryPercent.map { "\($0)%" } ?? "unknown battery"
    }

    public var odometerDisplay: String? {
        odometerMiles.map { "\(Int($0.rounded())) mi" }
    }

    public var statusSummary: String {
        var parts: [String] = []
        parts.append("Battery \(batteryDisplay)")
        if let chargingState, !chargingState.isEmpty {
            parts.append(chargingState.capitalized)
        }
        if let isLocked {
            parts.append(isLocked ? "Locked" : "Unlocked")
        }
        if let odometerDisplay {
            parts.append("Odometer \(odometerDisplay)")
        }
        if let tireSummary {
            parts.append("Tires \(tireSummary)")
        }
        return parts.joined(separator: " • ")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(vehicleName) Status",
            subtitle: "\(statusSummary)",
            synonyms: ["my car status", "car status", "my car", "my Tesla status"]
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        var descriptionParts = [statusSummary]
        if let chargeLimitPercent { descriptionParts.append("Charge limit \(chargeLimitPercent)%") }
        if let speedMPH { descriptionParts.append("Speed \(Int(speedMPH.rounded())) mph") }
        let unit = temperatureUnit ?? "°"
        if let batteryRangeMiles { descriptionParts.append("Range \(Int(batteryRangeMiles.rounded())) mi") }
        if let insideTemp { descriptionParts.append("Cabin \(Int(insideTemp.rounded()))\(unit)") }
        if let outsideTemp { descriptionParts.append("Outside \(Int(outsideTemp.rounded()))\(unit)") }
        if let locationAddress { descriptionParts.append("Near \(locationAddress)") }
        if let updatedAt { descriptionParts.append("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))") }
        let description = descriptionParts.joined(separator: ". ")
        attributes.title = "\(vehicleName) Status"
        attributes.displayName = "\(vehicleName) vehicle status"
        attributes.alternateNames = ["My Car", "My Car Status", "Car Climate", "\(vehicleName) Status"]
        attributes.kind = "Tesla Vehicle Status"
        attributes.contentDescription = description
        attributes.textContent = description
        attributes.keywords = [
            vehicleName, FleetKitLog.vin(vin), "car", "my car", "the car", "vehicle", "my vehicle", "Tesla",
            "vehicle status", "car status", "battery", "range", "charge", "charging",
            "lock", "lock my car", "unlock", "unlock my car", "locked", "unlocked", "mileage", "odometer", "miles",
            "tire", "tires", "tire pressure", "PSI",
            "climate", "warm up", "warm up my car", "cool down", "cool down my car", "precondition", "defrost",
            "heat", "AC", "cabin", "temperature", "location"
        ]
        if let latitude, let longitude {
            attributes.latitude = NSNumber(value: latitude)
            attributes.longitude = NSNumber(value: longitude)
            attributes.supportsNavigation = NSNumber(value: true)
            attributes.namedLocation = "\(vehicleName) location"
        }
        return attributes
    }
}

public struct VehicleStatusEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    public init() {}

    public func entities(for identifiers: [VehicleStatusEntity.ID]) async throws -> [VehicleStatusEntity] {
        let service = FleetIntentService.make()
        let vehicles = try await service.vehicles()
        var results: [VehicleStatusEntity] = []
        for identifier in identifiers {
            let vin = VehicleStatusEntity.vin(fromEntityID: identifier)
            guard let vehicle = vehicles.first(where: { $0.vin == vin }) else { continue }
            let snapshot = try await service.snapshot(vin: vin)
            results.append(VehicleStatusEntity(snapshot: snapshot, vehicleName: vehicle.name))
        }
        return results
    }

    public func suggestedEntities() async throws -> [VehicleStatusEntity] {
        try await entities(matching: "")
    }

    public func entities(matching string: String) async throws -> [VehicleStatusEntity] {
        let service = FleetIntentService.make()
        let selectedVIN = FleetSharedTokenStore.shared.selectedVIN()
        var vehicles = try await service.vehicles()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            let namedMatches = vehicles.filter { $0.name.localizedStandardContains(trimmed) }
            if !namedMatches.isEmpty {
                vehicles = namedMatches
            } else if !["car", "vehicle", "tesla", "status", "climate", "cabin", "battery", "warm", "cool"].contains(where: { trimmed.contains($0) }) {
                return []
            }
        }

        if let index = vehicles.firstIndex(where: { $0.vin == selectedVIN }), index != vehicles.startIndex {
            let selected = vehicles.remove(at: index)
            vehicles.insert(selected, at: 0)
        }
        var results: [VehicleStatusEntity] = []
        for vehicle in vehicles {
            let snapshot = try await service.snapshot(vin: vehicle.vin)
            results.append(VehicleStatusEntity(snapshot: snapshot, vehicleName: vehicle.name))
        }
        return results
    }

    public func reindexEntities(for identifiers: [VehicleStatusEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(entities(for: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(suggestedEntities())
    }
}

extension VehicleStatusEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.transferSummary)
    }

    /// Human-readable status summary for sharing with other apps (never exposes the VIN).
    public var transferSummary: String {
        var parts = ["\(vehicleName): \(statusSummary)"]
        if let batteryRangeMiles {
            parts.append("Range \(Int(batteryRangeMiles.rounded())) mi")
        }
        let unit = temperatureUnit ?? "°"
        if let insideTemp {
            parts.append("Cabin \(Int(insideTemp.rounded()))\(unit)")
        }
        if let locationAddress, !locationAddress.isEmpty {
            parts.append("Location: \(locationAddress)")
        }
        return parts.joined(separator: " • ")
    }
}

