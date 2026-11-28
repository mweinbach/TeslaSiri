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
    /// Optional owner name (e.g. "Max") used to build Spotlight titles like "Max's Car Status: Ares".
    let spotlightOwnerName: String?

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
        description: "Whether the car is charging, finished, plugged in but not charging, or unplugged. Empty when the car didn't report a state this app knows."
    )
    public var chargingState: VehicleChargingState?

    /// The provider's own wording for the charging state. Cards and summaries show it, so a
    /// state `chargingState` has no case for still appears.
    public let reportedChargingState: String?

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

    /// - Parameter includesLocation: Pass `false` from an intent that runs without
    ///   authentication, so the entity it returns and the card it shows never carry where the
    ///   car is. The location properties' own authentication policy only covers answers Siri
    ///   composes, not an intent's dialog or snippet.
    public init(
        snapshot: FleetSnapshotInfo,
        vehicleName: String,
        locationAddress: String? = nil,
        includesLocation: Bool = true,
        ownerName: String? = nil
    ) {
        self.id = Self.entityID(forVIN: snapshot.vin)
        self.reportedChargingState = snapshot.chargingState
        self.spotlightOwnerName = ownerName
        self.vin = snapshot.vin
        self.vehicleName = vehicleName
        self.batteryPercent = snapshot.batteryLevel.map { Int($0.rounded()) }
        self.batteryRangeMiles = snapshot.batteryRangeMiles
        self.chargeLimitPercent = snapshot.chargeLimitSOC.map { Int($0.rounded()) }
        self.chargingState = snapshot.chargingState.flatMap(VehicleChargingState.init(reported:))
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
        self.locationAddress = includesLocation ? locationAddress : nil
        self.latitude = includesLocation ? snapshot.latitude : nil
        self.longitude = includesLocation ? snapshot.longitude : nil
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

    public var usesMetric: Bool {
        if temperatureUnit == "°C" { return true }
        if temperatureUnit == "°F" { return false }
        return FleetKitFormatting.prefersMetric()
    }

    public static func localizedChargingState(_ state: String) -> String {
        switch state.lowercased() {
        case "charging":
            String(localized: "Charging", bundle: .module, comment: "Vehicle charging state: actively charging.")
        case "starting":
            String(localized: "Starting", bundle: .module, comment: "Vehicle charging state: starting to charge.")
        case "complete":
            String(localized: "Complete", bundle: .module, comment: "Vehicle charging state: charging complete.")
        case "stopped":
            String(localized: "Stopped", bundle: .module, comment: "Vehicle charging state: plugged in but stopped.")
        case "nopower":
            String(localized: "No Power", bundle: .module, comment: "Vehicle charging state: plugged in with no power.")
        case "disconnected":
            String(localized: "Disconnected", bundle: .module, comment: "Vehicle charging state: unplugged.")
        default:
            state.capitalized
        }
    }

    /// The charging state in a word or two, or `nil` when the car didn't report one.
    public var chargingStateLabel: String? {
        guard let reportedChargingState, !reportedChargingState.isEmpty else { return nil }
        return Self.localizedChargingState(reportedChargingState)
    }

    public var batteryDisplay: String {
        batteryPercent.map { FleetKitFormatting.percent($0) }
            ?? String(localized: "unknown battery", bundle: .module, comment: "Fallback text when battery percentage is unavailable.")
    }

    public var odometerDisplay: String? {
        odometerMiles.map { FleetKitFormatting.distance(miles: $0, usesMetric: usesMetric, fractionLength: 0) }
    }

    public var statusSummary: String {
        var parts: [String] = []
        parts.append(String(localized: "Battery \(batteryDisplay)", bundle: .module, comment: "Summary segment showing battery percentage."))
        if let chargingStateLabel {
            parts.append(chargingStateLabel)
        }
        if let isLocked {
            parts.append(
                isLocked
                    ? String(localized: "Locked", bundle: .module, comment: "Summary segment indicating vehicle doors are locked.")
                    : String(localized: "Unlocked", bundle: .module, comment: "Summary segment indicating vehicle doors are unlocked.")
            )
        }
        if let odometerDisplay {
            parts.append(String(localized: "Odometer \(odometerDisplay)", bundle: .module, comment: "Summary segment showing vehicle odometer reading."))
        }
        if let tireSummary {
            parts.append(String(localized: "Tires \(tireSummary)", bundle: .module, comment: "Summary segment showing tire pressures."))
        }
        return parts.joined(separator: " • ")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(
                "\(vehicleName) Status",
                bundle: FleetKitLocalization.bundleDescription,
                comment: "Display title for a vehicle status entity."
            ),
            subtitle: LocalizedStringResource(stringLiteral: statusSummary),
            synonyms: ["my car status", "car status", "my car", "my Tesla status"]
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        var descriptionParts = [statusSummary]
        if let chargeLimitPercent {
            let percentText = FleetKitFormatting.percent(chargeLimitPercent)
            descriptionParts.append(String(localized: "Charge limit \(percentText)", bundle: .module, comment: "Spotlight description segment for charge limit."))
        }
        if let speedMPH {
            let speedText = FleetKitFormatting.speed(mph: speedMPH, usesMetric: usesMetric, fractionLength: 0)
            descriptionParts.append(String(localized: "Speed \(speedText)", bundle: .module, comment: "Spotlight description segment for vehicle speed."))
        }
        let inFahrenheit = temperatureUnit != "°C"
        if let batteryRangeMiles {
            let rangeText = FleetKitFormatting.distance(miles: batteryRangeMiles, usesMetric: usesMetric, fractionLength: 0)
            descriptionParts.append(String(localized: "Range \(rangeText)", bundle: .module, comment: "Spotlight description segment for estimated driving range."))
        }
        if let insideTemp {
            let tempText = FleetKitFormatting.temperature(insideTemp, inFahrenheit: inFahrenheit, fractionLength: 0)
            descriptionParts.append(String(localized: "Cabin \(tempText)", bundle: .module, comment: "Spotlight description segment for cabin temperature."))
        }
        if let outsideTemp {
            let tempText = FleetKitFormatting.temperature(outsideTemp, inFahrenheit: inFahrenheit, fractionLength: 0)
            descriptionParts.append(String(localized: "Outside \(tempText)", bundle: .module, comment: "Spotlight description segment for exterior temperature."))
        }
        if let locationAddress {
            descriptionParts.append(String(localized: "Near \(locationAddress)", bundle: .module, comment: "Spotlight description segment for nearby address."))
        }
        if let updatedAt {
            let timestamp = updatedAt.formatted(date: .abbreviated, time: .shortened)
            descriptionParts.append(String(localized: "Updated \(timestamp)", bundle: .module, comment: "Spotlight description segment for last update timestamp."))
        }
        let description = descriptionParts.joined(separator: ". ")
        let spokenSnapshot = spokenAnswer(for: VehicleInfoTopic.allCases, includingLocation: false)
        let statusTitle = FleetSpotlightNaming.statusTitle(vehicleName: vehicleName, ownerName: spotlightOwnerName)
        let carHeader = FleetSpotlightNaming.carTitle(vehicleName: vehicleName, ownerName: spotlightOwnerName)
        var glanceParts: [String] = [carHeader]
        if let batteryPercent { glanceParts.append(FleetKitFormatting.percent(batteryPercent)) }
        if let isLocked {
            glanceParts.append(
                isLocked
                    ? String(localized: "Locked", bundle: .module, comment: "Short lock status in Spotlight display name.")
                    : String(localized: "Unlocked", bundle: .module, comment: "Short unlock status in Spotlight display name.")
            )
        }
        attributes.title = statusTitle
        attributes.displayName = glanceParts.joined(separator: " · ")
        var altNames: [String] = [
            String(localized: "My Car", bundle: .module, comment: "Spotlight alternate name for the user's car."),
            String(localized: "My Car Status", bundle: .module, comment: "Spotlight alternate name for the user's car status."),
            String(localized: "Car Climate", bundle: .module, comment: "Spotlight alternate name for car climate status."),
            "\(vehicleName) Status",
            "\(vehicleName) Battery",
            "\(vehicleName) Climate",
            "\(vehicleName) Tires",
            "\(vehicleName) Location",
            "Car Battery",
            "Car Location",
            statusTitle
        ]
        if let possessive = FleetSpotlightNaming.possessiveOwner(spotlightOwnerName) {
            altNames.append("\(possessive) Car")
            altNames.append("\(possessive) Car Status")
            altNames.append("\(possessive) Car Battery")
            altNames.append("\(possessive) Car Climate")
        }
        attributes.alternateNames = FleetSpotlightNaming.deduplicated(altNames)
        attributes.kind = String(localized: "Tesla Vehicle Status", bundle: .module, comment: "Spotlight item kind for a Tesla vehicle status snapshot.")
        attributes.contentDescription = description
        attributes.textContent = "\(spokenSnapshot) \(description)"
        attributes.keywords = FleetSpotlightNaming.deduplicated([
            vehicleName, FleetKitLog.vin(vin), "car", "my car", "the car", "vehicle", "my vehicle", "Tesla",
            "vehicle status", "car status", "battery", "range", "charge", "charging",
            "lock", "lock my car", "unlock", "unlock my car", "locked", "unlocked", "mileage", "odometer", "miles",
            "tire", "tires", "tire pressure", "PSI",
            "climate", "warm up", "warm up my car", "cool down", "cool down my car", "precondition", "defrost",
            "heat", "AC", "cabin", "temperature", "location",
            "coche", "mi coche", "carro", "vehículo", "vehiculo", "estado", "batería", "bateria", "autonomía", "autonomia", "carga", "clima", "ubicación", "ubicacion"
        ] + (attributes.alternateNames ?? []))
        if let latitude, let longitude {
            attributes.latitude = NSNumber(value: latitude)
            attributes.longitude = NSNumber(value: longitude)
            attributes.supportsNavigation = NSNumber(value: true)
            attributes.namedLocation = String(localized: "\(vehicleName) location", bundle: .module, comment: "Spotlight location name for a vehicle.")
        }
        return attributes
    }
}

public struct VehicleStatusEntityQuery: EntityQuery, EntityStringQuery, IndexedEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

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
            } else if ![
                "car", "vehicle", "tesla", "status", "climate", "cabin", "battery", "warm", "cool",
                "coche", "carro", "vehículo", "vehiculo", "estado", "clima", "cabina", "batería", "bateria", "calentar", "enfriar"
            ].contains(where: { trimmed.contains($0) }) {
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
            let rangeText = FleetKitFormatting.distance(miles: batteryRangeMiles, usesMetric: usesMetric, fractionLength: 0)
            parts.append(String(localized: "Range \(rangeText)", bundle: .module, comment: "Shared text segment showing estimated range."))
        }
        let inFahrenheit = temperatureUnit != "°C"
        if let insideTemp {
            let tempText = FleetKitFormatting.temperature(insideTemp, inFahrenheit: inFahrenheit, fractionLength: 0)
            parts.append(String(localized: "Cabin \(tempText)", bundle: .module, comment: "Shared text segment showing cabin temperature."))
        }
        if let locationAddress, !locationAddress.isEmpty {
            parts.append(String(localized: "Location: \(locationAddress)", bundle: .module, comment: "Shared text segment showing vehicle address."))
        }
        return parts.joined(separator: " • ")
    }
}

