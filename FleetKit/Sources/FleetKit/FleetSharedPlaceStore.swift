import CryptoKit
import Foundation

/// Lightweight, extension-safe record of a named place from the app's Drives tab
/// (user nicknames, detected overnight Home, and Apple Maps POIs), mirrored into
/// the App Group so Siri tools and Spotlight can match places the same way the app does.
public struct FleetKnownPlace: Codable, Hashable, Sendable {
    public let id: String
    /// Primary display name (user nickname if set, otherwise resolved place name such as "Home" or "Blue Bottle Coffee").
    public let name: String
    /// Additional searchable terms: automatic name when nicknamed, street address, and POI category keywords.
    public let alternateNames: [String]
    public let latitude: Double
    public let longitude: Double
    /// True when `name` is a human-friendly nickname, detected Home, or resolved POI rather than a fallback placeholder.
    public let isNamedPlace: Bool

    public init(
        id: String,
        name: String,
        alternateNames: [String] = [],
        latitude: Double,
        longitude: Double,
        isNamedPlace: Bool = true
    ) {
        self.id = id
        self.name = name
        self.alternateNames = alternateNames
        self.latitude = latitude
        self.longitude = longitude
        self.isNamedPlace = isNamedPlace
    }

    /// All non-empty searchable strings for this place, deduplicated preserving order.
    public var searchTerms: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in [name] + alternateNames {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return searchTerms.contains { $0.localizedStandardContains(trimmed) }
    }
}

/// App Group bridge sharing the Drives tab's named places and nicknames with FleetKit
/// intents and Spotlight indexing.
public struct FleetSharedPlaceStore: Sendable {
    public static let shared = FleetSharedPlaceStore()
    /// Matches `DrivePlacesIndex.clusterRadius` (120 meters).
    public static let defaultMatchRadiusMeters: Double = 120

    private static let vinsKey = "FleetKit.knownPlaceVINs"
    private static let keyPrefix = "FleetKit.knownPlaces."

    let appGroup: String

    public init(appGroup: String = FleetKitConfig.appGroupIdentifier) {
        self.appGroup = appGroup
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private func storageKey(forVIN vin: String) -> String {
        Self.keyPrefix + vin
    }

    public func save(_ places: [FleetKnownPlace], forVIN vin: String) {
        guard let defaults, !vin.isEmpty else { return }
        if places.isEmpty {
            clear(forVIN: vin)
            return
        }
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: storageKey(forVIN: vin))
        var vins = Set(defaults.stringArray(forKey: Self.vinsKey) ?? [])
        if vins.insert(vin).inserted {
            defaults.set(Array(vins).sorted(), forKey: Self.vinsKey)
        }
    }

    public func places(forVIN vin: String) -> [FleetKnownPlace] {
        guard let defaults, !vin.isEmpty,
              let data = defaults.data(forKey: storageKey(forVIN: vin)),
              let decoded = try? JSONDecoder().decode([FleetKnownPlace].self, from: data) else {
            return []
        }
        return decoded
    }

    public func clear(forVIN vin: String) {
        guard let defaults, !vin.isEmpty else { return }
        defaults.removeObject(forKey: storageKey(forVIN: vin))
        var vins = Set(defaults.stringArray(forKey: Self.vinsKey) ?? [])
        if vins.remove(vin) != nil {
            defaults.set(Array(vins).sorted(), forKey: Self.vinsKey)
        }
    }

    public func clearAll() {
        guard let defaults else { return }
        for vin in defaults.stringArray(forKey: Self.vinsKey) ?? [] {
            defaults.removeObject(forKey: storageKey(forVIN: vin))
        }
        defaults.removeObject(forKey: Self.vinsKey)
    }

    /// Stable digest of the saved places for `vin`, used by Spotlight indexing to detect
    /// nickname edits or newly resolved POIs.
    func digest(forVIN vin: String) -> Data {
        guard let defaults, !vin.isEmpty,
              let data = defaults.data(forKey: storageKey(forVIN: vin)) else {
            return Data()
        }
        return Data(SHA256.hash(data: data))
    }

    // MARK: - Matching & Display Helpers

    public static func nearestPlace(
        latitude: Double?,
        longitude: Double?,
        in places: [FleetKnownPlace],
        radiusMeters: Double = defaultMatchRadiusMeters
    ) -> FleetKnownPlace? {
        guard let latitude, let longitude, !places.isEmpty,
              abs(latitude) <= 90, abs(longitude) <= 180,
              latitude != 0 || longitude != 0 else {
            return nil
        }
        var best: (place: FleetKnownPlace, distance: Double)?
        for place in places {
            let distance = haversineMeters(lat1: latitude, lon1: longitude, lat2: place.latitude, lon2: place.longitude)
            guard distance <= radiusMeters else { continue }
            if best == nil || distance < best!.distance {
                best = (place, distance)
            }
        }
        return best?.place
    }

    public static func displayLabel(
        address: String?,
        latitude: Double?,
        longitude: Double?,
        in places: [FleetKnownPlace],
        radiusMeters: Double = defaultMatchRadiusMeters
    ) -> String? {
        if let match = nearestPlace(latitude: latitude, longitude: longitude, in: places, radiusMeters: radiusMeters),
           match.isNamedPlace, !match.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return match.name
        }
        return address
    }

    public static func searchTerms(
        address: String?,
        latitude: Double?,
        longitude: Double?,
        in places: [FleetKnownPlace],
        radiusMeters: Double = defaultMatchRadiusMeters
    ) -> [String] {
        var raw: [String] = []
        if let match = nearestPlace(latitude: latitude, longitude: longitude, in: places, radiusMeters: radiusMeters) {
            raw.append(contentsOf: match.searchTerms)
        }
        if let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            raw.append(address)
        }
        var seen: Set<String> = []
        return raw.filter { seen.insert($0.lowercased()).inserted }
    }

    public static func matches(
        query: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        in places: [FleetKnownPlace],
        radiusMeters: Double = defaultMatchRadiusMeters
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if address?.localizedStandardContains(trimmed) == true {
            return true
        }
        if let match = nearestPlace(latitude: latitude, longitude: longitude, in: places, radiusMeters: radiusMeters) {
            return match.matches(trimmed)
        }
        return false
    }

    /// Great-circle distance in meters using the Haversine formula (avoids CoreLocation dependency).
    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let rLat1 = lat1 * .pi / 180
        let rLat2 = lat2 * .pi / 180
        let sinHalfLat = sin(dLat / 2)
        let sinHalfLon = sin(dLon / 2)
        let a = sinHalfLat * sinHalfLat + cos(rLat1) * cos(rLat2) * sinHalfLon * sinHalfLon
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }
}
