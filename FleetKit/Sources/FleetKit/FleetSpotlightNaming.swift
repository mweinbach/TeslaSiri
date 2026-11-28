import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Builds rich, natural-language Spotlight metadata across all FleetKit entities so
/// Spotlight search and iOS 27.3 Siri entity retrieval reliably match phrases like
/// "Max's car", "my car", "Ares", "warm up my car", "drive to the gym", and "Supercharger".
public enum FleetSpotlightNaming {
    /// Returns a clean possessive form for an optional owner name (e.g. "Max" → "Max's", "Chris" → "Chris'").
    public static func possessiveOwner(_ ownerName: String?) -> String? {
        guard let trimmed = ownerName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("'s") || lower.hasSuffix("’s") || lower.hasSuffix("'") || lower.hasSuffix("’") {
            return trimmed
        }
        return lower.hasSuffix("s") ? "\(trimmed)'" : "\(trimmed)'s"
    }

    /// Primary Spotlight title for a vehicle, such as "Max's Car: Ares" or "My Car: Ares".
    public static func carTitle(
        vehicleName: String,
        ownerName: String? = nil,
        isDefaultCar: Bool? = nil
    ) -> String {
        if let possessive = possessiveOwner(ownerName) {
            return String(
                localized: "\(possessive) Car: \(vehicleName)",
                bundle: .module,
                comment: "Spotlight title for a user's car when an owner name is set, e.g. 'Max's Car: Ares'."
            )
        }
        if isDefaultCar == false {
            return String(
                localized: "\(vehicleName) (Tesla)",
                bundle: .module,
                comment: "Spotlight title for a secondary car when no owner name is set."
            )
        }
        return String(
            localized: "My Car: \(vehicleName)",
            bundle: .module,
            comment: "Spotlight title for the default car when no owner name is set, e.g. 'My Car: Ares'."
        )
    }

    /// Rich Spotlight display name including the model when known, e.g. "Max's Car: Ares (Model Y)".
    public static func carDisplayName(
        vehicleName: String,
        model: String? = nil,
        ownerName: String? = nil,
        isDefaultCar: Bool? = nil
    ) -> String {
        let base = carTitle(vehicleName: vehicleName, ownerName: ownerName, isDefaultCar: isDefaultCar)
        guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
            return base
        }
        return "\(base) (\(model))"
    }

    /// Spotlight title for live vehicle status, e.g. "Max's Car Status: Ares" or "My Car Status: Ares".
    public static func statusTitle(vehicleName: String, ownerName: String? = nil) -> String {
        if let possessive = possessiveOwner(ownerName) {
            return String(
                localized: "\(possessive) Car Status: \(vehicleName)",
                bundle: .module,
                comment: "Spotlight title for live vehicle status when an owner name is set."
            )
        }
        return String(
            localized: "My Car Status: \(vehicleName)",
            bundle: .module,
            comment: "Spotlight title for live vehicle status when no owner name is set."
        )
    }

    /// Spotlight title for software update status, e.g. "Max's Car Software: Ares (2026.8.4)".
    public static func softwareTitle(
        vehicleName: String,
        availableVersion: String? = nil,
        ownerName: String? = nil
    ) -> String {
        let base: String
        if let possessive = possessiveOwner(ownerName) {
            base = String(
                localized: "\(possessive) Car Software: \(vehicleName)",
                bundle: .module,
                comment: "Spotlight title for vehicle software status when an owner name is set."
            )
        } else {
            base = String(
                localized: "My Car Software: \(vehicleName)",
                bundle: .module,
                comment: "Spotlight title for vehicle software status when no owner name is set."
            )
        }
        if let availableVersion, !availableVersion.isEmpty {
            return "\(base) (\(availableVersion))"
        }
        return base
    }

    /// Natural-language alternate names for a vehicle in Spotlight (deduplicated, preserving order).
    public static func carAlternateNames(
        vehicleName: String,
        model: String? = nil,
        color: String? = nil,
        ownerName: String? = nil
    ) -> [String] {
        var candidates: [String] = [
            vehicleName,
            String(localized: "My Car", bundle: .module, comment: "Alternate Spotlight name for vehicle"),
            String(localized: "My Car: \(vehicleName)", bundle: .module, comment: "Alternate Spotlight name pairing My Car with vehicle name"),
            String(localized: "The Car", bundle: .module, comment: "Alternate Spotlight name for vehicle"),
            String(localized: "My Vehicle", bundle: .module, comment: "Alternate Spotlight name for vehicle"),
            String(localized: "My Tesla", bundle: .module, comment: "Alternate Spotlight name for vehicle"),
            "My EV",
            "Tesla",
            "Mi coche",
            "Mi auto",
            "Mi Tesla"
        ]
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = color?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedModel, !trimmedModel.isEmpty {
            candidates.append(trimmedModel)
            candidates.append("My \(trimmedModel)")
            if let trimmedColor, !trimmedColor.isEmpty {
                candidates.append("\(trimmedColor) \(trimmedModel)")
                candidates.append("My \(trimmedColor) \(trimmedModel)")
            }
        }
        if let trimmedColor, !trimmedColor.isEmpty {
            candidates.append("\(trimmedColor) Tesla")
            candidates.append("\(trimmedColor) Car")
        }
        if let owner = ownerName?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty,
           let possessive = possessiveOwner(owner) {
            candidates.append("\(possessive) Car")
            candidates.append("\(possessive) Tesla")
            candidates.append("\(possessive) Vehicle")
            candidates.append("\(possessive) \(vehicleName)")
            candidates.append("\(owner) car")
            candidates.append("Coche de \(owner)")
            if let trimmedModel, !trimmedModel.isEmpty {
                candidates.append("\(possessive) \(trimmedModel)")
            }
        }
        return deduplicated(candidates)
    }

    /// Identifiers for the companion semantic Spotlight items associated with a vehicle via `relatedAppEntityIdentifier`.
    static func companionItemIdentifiers(forVIN vin: String) -> [String] {
        ["car-climate:\(vin)", "car-controls:\(vin)"]
    }

    /// Builds companion `CSSearchableItem`s cross-linked to `VehicleEntity` via iOS 27's
    /// `relatedAppEntityIdentifier` so climate ("warm up my car") and quick-control queries
    /// resolve directly to the car entity in Spotlight.
    static func companionSearchItems(
        for vehicle: VehicleEntity,
        status: VehicleStatusEntity? = nil,
        ownerName: String? = nil
    ) -> [CSSearchableItem] {
        let entityID = EntityIdentifier(for: vehicle)
        let label = carTitle(vehicleName: vehicle.name, ownerName: ownerName, isDefaultCar: vehicle.isDefaultCar)
        let possessive = possessiveOwner(ownerName)

        // 1. Cabin climate & preconditioning anchor
        let climateAttrs = CSSearchableItemAttributeSet(contentType: .item)
        climateAttrs.title = String(
            localized: "Warm Up \(label)",
            bundle: .module,
            comment: "Spotlight companion item title for warming up or cooling down the user's car."
        )
        climateAttrs.displayName = String(
            localized: "Climate & Preconditioning — \(label)",
            bundle: .module,
            comment: "Spotlight companion item display name for vehicle climate controls."
        )
        var climateAlts: [String] = [
            "Warm up my car",
            "Cool down my car",
            "Heat up my car",
            "Precondition my car",
            "Start car climate",
            "Car climate",
            "Car temperature",
            "Defrost my car",
            "Warm up \(vehicle.name)",
            "Cool down \(vehicle.name)",
            "Calentar mi coche",
            "Enfriar mi coche"
        ]
        if let possessive {
            climateAlts.append("Warm up \(possessive) car")
            climateAlts.append("Cool down \(possessive) car")
            climateAlts.append("\(possessive) car climate")
        }
        climateAttrs.alternateNames = deduplicated(climateAlts)
        climateAttrs.kind = String(localized: "Car Climate Control", bundle: .module, comment: "Spotlight kind for car climate control anchor.")
        let liveClimate = status?.spokenAnswer(for: [.climate])
        let climateDesc = [
            liveClimate,
            String(
                localized: "Warm up, cool down, precondition cabin, set temperature, max defrost, seat heaters, seat cooling, steering wheel heater, Dog Mode, or Bioweapon Defense for \(label).",
                bundle: .module,
                comment: "Spotlight description for car climate control anchor."
            )
        ].compactMap { $0 }.joined(separator: " ")
        climateAttrs.contentDescription = climateDesc
        climateAttrs.textContent = climateDesc
        climateAttrs.keywords = deduplicated(
            climateAlts + [
                vehicle.name, "Tesla", "Wattie", "climate", "HVAC", "AC", "heat", "temperature",
                "seat heater", "seat cooling", "steering wheel heater", "Dog Mode", "Bioweapon Defense",
                "defrost", "my car", "car"
            ] + [vehicle.model, vehicle.color, ownerName].compactMap { $0 }
        )
        climateAttrs.relatedAppEntityIdentifier = entityID
        let climateItem = CSSearchableItem(
            uniqueIdentifier: "car-climate:\(vehicle.id)",
            domainIdentifier: "com.maxweinbach.TeslaSiri.car-anchors",
            attributeSet: climateAttrs
        )
        climateItem.relatedAppEntityIdentifier = entityID

        // 2. Locks, charging, trunk & location anchor
        let controlAttrs = CSSearchableItemAttributeSet(contentType: .item)
        controlAttrs.title = String(
            localized: "Control \(label)",
            bundle: .module,
            comment: "Spotlight companion item title for controlling the user's car."
        )
        controlAttrs.displayName = String(
            localized: "Locks, Charging & Trunk — \(label)",
            bundle: .module,
            comment: "Spotlight companion item display name for vehicle controls."
        )
        var controlAlts: [String] = [
            "Control my car",
            "Lock my car",
            "Unlock my car",
            "Open trunk",
            "Close trunk",
            "Open frunk",
            "Charge my car",
            "Sentry Mode",
            "Where is my car",
            "Where did I park",
            "Locate my car",
            "\(vehicle.name) controls",
            "Bloquear mi coche",
            "Dónde está mi coche"
        ]
        if let possessive {
            controlAlts.append("Lock \(possessive) car")
            controlAlts.append("Unlock \(possessive) car")
            controlAlts.append("Where is \(possessive) car")
            controlAlts.append("\(possessive) car controls")
        }
        controlAttrs.alternateNames = deduplicated(controlAlts)
        controlAttrs.kind = String(localized: "Car Controls", bundle: .module, comment: "Spotlight kind for car controls anchor.")
        let liveStatus = status?.spokenAnswer(for: [.battery, .range, .security, .charging])
        let controlDesc = [
            liveStatus,
            String(
                localized: "Lock or unlock doors, open or close trunk, open frunk, start or stop charging, set charge limit, vent or close windows, toggle Sentry Mode, send a destination, or locate \(label).",
                bundle: .module,
                comment: "Spotlight description for car controls anchor."
            )
        ].compactMap { $0 }.joined(separator: " ")
        controlAttrs.contentDescription = controlDesc
        controlAttrs.textContent = controlDesc
        controlAttrs.keywords = deduplicated(
            controlAlts + [
                vehicle.name, "Tesla", "Wattie", "lock", "unlock", "trunk", "frunk", "charge", "charging",
                "charge port", "charge limit", "windows", "Sentry Mode", "horn", "lights", "navigation",
                "location", "battery", "range", "tire pressure", "my car", "car"
            ] + [vehicle.model, vehicle.color, ownerName].compactMap { $0 }
        )
        controlAttrs.relatedAppEntityIdentifier = entityID
        let controlItem = CSSearchableItem(
            uniqueIdentifier: "car-controls:\(vehicle.id)",
            domainIdentifier: "com.maxweinbach.TeslaSiri.car-anchors",
            attributeSet: controlAttrs
        )
        controlItem.relatedAppEntityIdentifier = entityID

        return [climateItem, controlItem]
    }

    static func deduplicated(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in items {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
