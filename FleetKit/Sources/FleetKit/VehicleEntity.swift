import AppIntents
import CoreSpotlight
import CoreTransferable
import OSLog

/// A Tesla on the account, used as the optional vehicle parameter on
/// VIN-scoped intents so Siri/Shortcuts can disambiguate.
public struct VehicleEntity: AppEntity, IndexedEntity, SyncableEntity, Identifiable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Vehicle",
        synonyms: ["Car", "Tesla", "EV", "Electric Car"]
    )
    public static let defaultQuery = VehicleEntityQuery()

    /// Full vehicle identification number (VIN).
    public let id: String

    @Property(
        title: "Vehicle Name",
        description: "The name the owner gave this car in the Tesla app, such as \"Midnight\". Use it to tell the user's cars apart.",
        indexingKey: \.title
    )
    public var name: String

    @Property(
        title: "Model",
        description: "The car's model, such as Model 3, Model Y, Model S, Model X, or Cybertruck. Empty if the provider hasn't reported it.",
        indexingKey: \.kind
    )
    public var model: String?

    @Property(
        title: "Paint Color",
        description: "The car's exterior paint, such as Pearl White or Midnight Silver Metallic. Empty if unknown."
    )
    public var color: String?

    @Property(title: "Default Car", description: "Whether a command with no vehicle specified targets this car in the current fleet. Empty on a car returned without the roster.")
    public var isDefaultCar: Bool?

    @Property(title: "Control Car Requests", description: "Changes Wattie can request with the Control Car tool. Equipment, current vehicle state and account permissions determine which requests can be accepted.")
    public var controls: [String]?

    @Property(title: "Additional Controls", description: "Actions available through the named specialist tools, subject to equipment, vehicle state and permissions.")
    public var additionalControls: [String]?

    public var displayRepresentation: DisplayRepresentation {
        let subtitle = [model, color].compactMap { $0 }.joined(separator: " · ")
        var entitySynonyms: [LocalizedStringResource] = [
            "my car",
            "the car",
            "car",
            "my vehicle",
            "my Tesla",
            "Tesla"
        ]
        if let model, !model.isEmpty {
            entitySynonyms.append(LocalizedStringResource(stringLiteral: model))
            entitySynonyms.append(LocalizedStringResource(stringLiteral: "my \(model)"))
        }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? "Tesla" : "\(subtitle)",
            synonyms: entitySynonyms
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        let modelText = model ?? "Tesla"
        let description = "My car (\(modelText) named \(name)). Ask Siri for its battery, range, tire pressure, mileage, climate, drives, charging history, or software updates, or to lock, unlock, warm up my car, cool down my car, precondition, defrost, or send it a destination."
        attributes.title = name
        attributes.displayName = name
        attributes.alternateNames = ["My Car", "The Car", "My Vehicle", "My Tesla", "Tesla", model].compactMap { $0 }
        attributes.kind = model ?? "Tesla Vehicle"
        attributes.contentDescription = description
        attributes.textContent = description
        attributes.keywords = [
            "car", "my car", "the car", "vehicle", "my vehicle", "electric car", "EV", "Tesla",
            name, model, color,
            "warm up", "warm up my car", "cool down", "cool down my car", "precondition", "defrost",
            "heat", "AC", "air conditioning", "climate",
            "battery", "range", "mileage", "odometer", "tire pressure",
            "drive", "charging", "software", "release notes", "lock", "lock my car", "unlock", "unlock my car",
            "navigation"
        ].compactMap { $0 }
        return attributes
    }

    public init(id: String, name: String, model: String? = nil, color: String? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.color = color
    }

    public init(info: FleetVehicleInfo, usesTeslascope: Bool = false) {
        self.id = info.vin
        self.name = info.name
        self.model = info.modelName
        self.color = info.colorName
        let allowsVehicle = !usesTeslascope || info.allowsVehicleCommands != false
        let allowsCharging = !usesTeslascope || info.allowsChargingCommands != false
        var commands: [String] = []
        var additional: [String] = []
        if allowsVehicle {
            commands = [
                "Turn cabin climate on or off and set the target temperature",
                usesTeslascope ? "Adjust seat heat and max defrost" : "Adjust front seat heat, steering wheel heat, and max defrost",
                usesTeslascope ? "Turn Dog Mode on or off" : "Turn Dog Mode or Bioweapon Defense Mode on or off where equipped",
                usesTeslascope ? "Enable or disable Sentry Mode; lock or unlock the doors if Allow Unlock is enabled in Teslascope" : "Lock or unlock the doors and enable or disable Sentry Mode",
                "Vent or close the windows, honk the horn, and flash the lights"
            ]
            if info.canActuateTrunks != false {
                commands.append(info.canActuateTrunks == true ? "Open the trunk or frunk" : "Open the trunk or frunk if equipped")
            }
            if info.canAcceptNavigationRequests != false {
                commands.append(info.canAcceptNavigationRequests == true ? "Send a navigation destination" : "Send a navigation destination if supported")
            }
            additional = [
                "Set Car Temperature: set a target cabin temperature with an interactive card",
                "Set Seat Climate: adjust heating by seat position (front or rear) where equipped",
                usesTeslascope ? "Install Software Update: start an available update now" : "Install Software Update or Cancel Software Update when an update is available"
            ]
            if info.canAcceptNavigationRequests != false {
                additional.append(info.canAcceptNavigationRequests == true ? "Send Destination to Car: send a standalone navigation destination" : "Send Destination to Car: send a standalone navigation destination if supported")
            }
            if !usesTeslascope, info.hasSeatCooling != false {
                additional.append(info.hasSeatCooling == true ? "Set Seat Climate: adjust front seat cooling" : "Set Seat Climate: adjust front seat cooling if equipped")
            }
        }
        if allowsCharging {
            commands.append(usesTeslascope ? "Start or stop charging, set the charge limit, and open or close the charge port" : "Start or stop charging, set the charge limit and charging amps, and open or close the charge port")
        }
        self.controls = commands
        self.additionalControls = additional
    }
}

/// The vehicle list is small, so an enumerable + string query powers both
/// Shortcuts suggestions and natural-language Siri AI lookups like "my car".
public struct VehicleEntityQuery: EnumerableEntityQuery, EntityStringQuery, IndexedEntityQuery {
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension, .widgetKitExtension] }

    private static let genericCarTerms: Set<String> = [
        "car", "my car", "the car", "our car",
        "vehicle", "my vehicle", "the vehicle",
        "ev", "my ev", "electric car", "electric vehicle",
        "auto", "automobile", "suv", "sedan", "truck",
        "tesla", "my tesla", "the tesla"
    ]

    public init() {}

    public func allEntities() async throws -> [VehicleEntity] {
        let service = FleetIntentService.make()
        let vehicles = try await service.vehicles()
        guard let defaultVehicle = service.defaultVehicle(in: vehicles) else { return [] }
        let ordered = [defaultVehicle] + vehicles.filter { $0.vin != defaultVehicle.vin }
        let entities = ordered.map { info in
            let entity = VehicleEntity(info: info, usesTeslascope: service.usesTeslascope)
            entity.isDefaultCar = info.vin == defaultVehicle.vin
            return entity
        }
        FleetKitLog.entities.info("VehicleEntityQuery.allEntities returned \(entities.count, privacy: .public) vehicle(s)")
        return entities
    }

    public func entities(for identifiers: [VehicleEntity.ID]) async throws -> [VehicleEntity] {
        let matches = try await allEntities().filter { identifiers.contains($0.id) }
        FleetKitLog.entities.info("VehicleEntityQuery matched \(matches.count, privacy: .public) of \(identifiers.count, privacy: .public) requested vehicle(s)")
        return matches
    }

    public func entities(matching string: String) async throws -> [VehicleEntity] {
        let all = try await allEntities()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !Self.genericCarTerms.contains(trimmed) else {
            return all
        }

        let directMatches = all.filter { entity in
            entity.name.localizedStandardContains(trimmed)
                || (entity.model?.localizedStandardContains(trimmed) == true)
                || (entity.color?.localizedStandardContains(trimmed) == true)
        }
        if !directMatches.isEmpty {
            return directMatches
        }

        if trimmed.contains("car") || trimmed.contains("vehicle") || trimmed.contains("tesla") {
            return all
        }
        return []
    }

    public func reindexEntities(for identifiers: [VehicleEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(entities(for: identifiers))
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await FleetSpotlightIndexer.donate(allEntities())
    }
}

extension VehicleEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.transferSummary)
    }

    /// Human-readable vehicle summary for sharing with other apps (never exposes the VIN).
    public var transferSummary: String {
        let details = [model, color].compactMap { $0 }.joined(separator: " · ")
        return details.isEmpty ? "\(name) (Tesla)" : "\(name) (\(details))"
    }
}

