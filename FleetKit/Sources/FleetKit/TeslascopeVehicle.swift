import Foundation

struct TeslascopeVehicleEntry: Sendable {
    let publicID: String
    var vehicle: FleetVehicleInfo
}

struct TeslascopeVehicleRecord: Decodable {
    let publicID: String
    let vin: String?
    let name: String?
    let model: String?
    let config: Configuration?

    enum CodingKeys: String, CodingKey {
        case publicID = "public_id"
        case vin, name, model
        case config = "vehicle_config"
    }

    struct Configuration: Decodable {
        var carType: String?
        var exteriorColor: String?
        var canActuateTrunks: Bool?
        var canAcceptNavigationRequests: Bool?
        var hasSeatCooling: Bool?

        enum CodingKeys: String, CodingKey {
            case carType = "car_type", exteriorColor = "exterior_color"
            case canActuateTrunks = "can_actuate_trunks", canAcceptNavigationRequests = "can_accept_navigation_requests"
            case hasSeatCooling = "has_seat_cooling"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            carType = try values.decodeIfPresent(String.self, forKey: .carType)
            exteriorColor = try values.decodeIfPresent(String.self, forKey: .exteriorColor)
            func flag(_ key: CodingKeys) -> Bool? {
                if let bool = try? values.decode(Bool.self, forKey: key) { return bool }
                return values.flexibleDouble(key).map { $0 != 0 }
            }
            canActuateTrunks = flag(.canActuateTrunks)
            canAcceptNavigationRequests = flag(.canAcceptNavigationRequests)
            hasSeatCooling = flag(.hasSeatCooling)
        }
    }

    var entry: TeslascopeVehicleEntry? {
        guard let vin = Self.normalizedVIN(vin) else { return nil }
        return TeslascopeVehicleEntry(
            publicID: publicID,
            vehicle: FleetVehicleInfo(
                vin: vin, displayName: name, carType: config?.carType ?? model?.lowercased().replacing(" ", with: ""),
                exteriorColor: config?.exteriorColor, hasSeatCooling: config?.hasSeatCooling,
                canActuateTrunks: config?.canActuateTrunks, canAcceptNavigationRequests: config?.canAcceptNavigationRequests
            )
        )
    }

    static func normalizedVIN(_ value: String?) -> String? {
        guard let vin = value?.uppercased(), vin.utf8.count == 17,
              vin.utf8.allSatisfy({ "ABCDEFGHJKLMNPRSTUVWXYZ0123456789".utf8.contains($0) }) else { return nil }
        return vin
    }
}

extension TeslascopeClient {
    /// Teslascope's detailed data uses Celsius and miles. Wattie's shared models
    /// use one display-unit setting across vehicles on the same account.
    public static var displayUnits: String {
        UnitTemperature(forLocale: .current, usage: .general) == .fahrenheit ? "imperial" : "metric"
    }

    public func stateData(vin: String) async throws -> Data {
        let publicID = try await publicID(vin: vin)
        let data = try await request(["vehicle", publicID, "detailed"])
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = envelope["response"] as? [String: Any],
              detail["public_id"] as? String == publicID,
              TeslascopeVehicleRecord.normalizedVIN(detail["vin"] as? String) == vin else {
            throw FleetKitError.api("Teslascope returned details for an unrecognized vehicle.")
        }

        var state: [String: Any] = [:]
        state["display_name"] = detail["name"]
        state["vehicle_config"] = detail["vehicle_config"]
        state["gui_settings"] = ["gui_temperature_units": Self.displayUnits == "imperial" ? "F" : "C"]
        for key in ["charge_state", "climate_state", "drive_state", "vehicle_state"] {
            guard var section = detail[key] as? [String: Any] else { continue }
            if let updatedAt = section["updated_at"] as? String,
               let observed = try? Date.ISO8601FormatStyle().parse(updatedAt) {
                section["timestamp"] = Int64((observed.timeIntervalSince1970 * 1_000).rounded())
            }
            if key == "vehicle_state" {
                var update: [String: Any] = [:]
                for field in ["status", "version", "download_perc", "install_perc"] {
                    update[field] = section["software_update_" + field]
                }
                update["expected_duration_sec"] = section["software_update_expected_duration"]
                if !update.isEmpty { section["software_update"] = update }
            }
            state[key] = section
        }
        return try JSONSerialization.data(withJSONObject: state)
    }
}
