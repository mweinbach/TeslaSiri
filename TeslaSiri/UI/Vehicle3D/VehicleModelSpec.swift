import Foundation

/// The bundled TeslaVehicleKit build that best represents a Tessie vehicle.
///
/// Tessie reports `car_type` (`modely`, `model3`, `models`, `modelx`, `cybertruck`) but not
/// the body generation, so the refresh generation is inferred from the VIN model-year
/// character: Model Y "Juniper" (`bayberry`) from 2025, Model 3 "Highland" (`poppyseed`) from
/// 2024, and the Model S/X "Palladium" refresh from 2021. Performance Model Ys use the
/// bundled Performance fascia build. Paint is matched by name against the build's presets.
nonisolated struct VehicleModelSpec: Hashable, Sendable {
    var modelID: String
    var bodyStyle: String
    /// Raw Tessie paint name (`exterior_color`), matched against the catalog at load time.
    var paintName: String?
    var rightHandDrive: Bool

    static let showroomDefault = VehicleModelSpec(
        modelID: "bayberry",
        bodyStyle: "UltraRedPerformance",
        paintName: nil,
        rightHandDrive: false
    )

    init(modelID: String, bodyStyle: String, paintName: String?, rightHandDrive: Bool) {
        self.modelID = modelID
        self.bodyStyle = bodyStyle
        self.paintName = paintName
        self.rightHandDrive = rightHandDrive
    }

    init(configuration: FleetVehicleConfiguration?, vin: String) {
        let year = Self.modelYear(fromVIN: vin)
        let carType = configuration?.carType?.lowercased() ?? ""
        let isPerformance = Self.isPerformance(configuration?.trimBadging)

        switch carType {
        case "modely":
            if (year ?? 2025) >= 2025 {
                modelID = "bayberry"
                bodyStyle = isPerformance ? "UltraRedPerformance" : "default"
            } else {
                modelID = "model_y"
                bodyStyle = "default"
            }
        case "model3":
            modelID = (year ?? 2024) >= 2024 ? "poppyseed" : "model_3"
            bodyStyle = "default"
        case "models", "models2":
            modelID = (year ?? 2021) >= 2021 ? "model_s_palladium" : "model_s"
            bodyStyle = "default"
        case "modelx":
            modelID = (year ?? 2021) >= 2021 ? "model_x_palladium" : "model_x"
            bodyStyle = "default"
        case "cybertruck":
            modelID = "cybertruck"
            bodyStyle = "default"
        default:
            modelID = Self.showroomDefault.modelID
            bodyStyle = Self.showroomDefault.bodyStyle
        }

        paintName = configuration?.paintColorOverride.flatMap(Self.namedPaint) ?? configuration?.exteriorColor
        rightHandDrive = configuration?.rightHandDrive ?? false
    }

    /// Picks the catalog preset for a Tessie paint name, ignoring case and punctuation.
    static func matchPaint(_ raw: String?, in choices: [String]) -> String? {
        guard let raw else { return nil }
        let key = normalized(raw)
        guard !key.isEmpty else { return nil }
        let aliases = [
            "obsidianblack": "metallicblack",
            "midnightsilvermetallic": "midnightsilver",
            "deepbluemetallic": "deepblue",
            "silver": "silvermetallic",
            "white": "pearlwhite",
            "black": "solidblack",
            "red": "redmulticoat",
            "blue": "deepblue",
            "grey": "stealthgrey",
            "gray": "stealthgrey"
        ]
        let lookup = Dictionary(choices.map { (normalized($0), $0) }, uniquingKeysWith: { first, _ in first })
        if let exact = lookup[key] { return exact }
        if let alias = aliases[key], let match = lookup[alias] { return match }
        return choices.first { key.contains(normalized($0)) && normalized($0).count > 4 }
    }

    private static func normalized(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// `paint_color_override` is sometimes a name and sometimes RGBA numbers; only names are useful.
    private static func namedPaint(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains(where: \.isLetter) else { return nil }
        return trimmed
    }

    private static func isPerformance(_ trim: String?) -> Bool {
        guard let trim = trim?.lowercased(), !trim.isEmpty else { return false }
        return trim == "performance" || trim.hasPrefix("p")
    }

    /// The 10th VIN character encodes the model year.
    private static func modelYear(fromVIN vin: String) -> Int? {
        let characters = Array(vin.uppercased())
        guard characters.count == 17 else { return nil }
        let codes: [Character: Int] = [
            "J": 2018, "K": 2019, "L": 2020, "M": 2021, "N": 2022, "P": 2023,
            "R": 2024, "S": 2025, "T": 2026, "V": 2027, "W": 2028, "X": 2029, "Y": 2030
        ]
        return codes[characters[9]]
    }
}
