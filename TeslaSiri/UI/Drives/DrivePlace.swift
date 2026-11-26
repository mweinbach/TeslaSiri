import CoreLocation
import Foundation
import MapKit

/// A place the car drives to or from, such as a gym, an office or home: a cluster of drive
/// endpoints within about 120 m, named from the nearest Apple Maps point of interest, a name
/// saved in Tessie, or the street address.
struct DrivePlace: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var nickname: String?
    /// Raw `MKPointOfInterestCategory` value when the name came from a point of interest.
    var category: String?
    var address: String?
    var latitude: Double
    var longitude: Double
    /// Drives that ended here, newest first.
    var arrivalIDs: [String]
    /// Drives that started here, newest first.
    var departureIDs: [String]
    var lastVisit: Int64
    /// Whether the name has been looked up (not just taken from Tessie's address).
    var isResolved: Bool
    /// True when the place was automatically detected as the vehicle's overnight home.
    var isDetectedHome: Bool = false

    init(
        id: String,
        name: String,
        nickname: String? = nil,
        category: String? = nil,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        arrivalIDs: [String],
        departureIDs: [String],
        lastVisit: Int64,
        isResolved: Bool,
        isDetectedHome: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.category = category
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.arrivalIDs = arrivalIDs
        self.departureIDs = departureIDs
        self.lastVisit = lastVisit
        self.isResolved = isResolved
        self.isDetectedHome = isDetectedHome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        arrivalIDs = try container.decode([String].self, forKey: .arrivalIDs)
        departureIDs = try container.decode([String].self, forKey: .departureIDs)
        lastVisit = try container.decode(Int64.self, forKey: .lastVisit)
        isResolved = try container.decode(Bool.self, forKey: .isResolved)
        isDetectedHome = try container.decodeIfPresent(Bool.self, forKey: .isDetectedHome) ?? false
    }

    /// Localized automatic name (ignoring user nickname).
    var defaultName: String {
        if isDetectedHome || (category == nil && name.caseInsensitiveCompare("Home") == .orderedSame) {
            return String(localized: "Home", comment: "Automatically detected or saved home location for the vehicle")
        }
        if name == Self.unnamedPlaceholder {
            return String(localized: "Unnamed place", comment: "Fallback name for a place before its address or point of interest is resolved")
        }
        if name == Self.unknownPlaceholder {
            return String(localized: "Unknown place", comment: "Fallback name when a drive destination cannot be geocoded")
        }
        return name
    }

    var displayName: String { nickname ?? defaultName }
    var endpointName: String? {
        if let nickname { return nickname }
        if isDetectedHome || isResolved { return defaultName }
        return nil
    }
    var visitCount: Int { arrivalIDs.count }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    static let unnamedPlaceholder = "Unnamed place"
    static let unknownPlaceholder = "Unknown place"

    var systemImage: String {
        let lowered = displayName.lowercased()
        let homeNames: Set<String> = [
            "home",
            "casa",
            "hogar",
            "domicilio",
            String(localized: "Home", comment: "Automatically detected or saved home location for the vehicle").lowercased()
        ]
        if isDetectedHome || homeNames.contains(lowered) { return "house.fill" }
        let workNames: Set<String> = ["work", "office", "trabajo", "oficina"]
        if workNames.contains(lowered) { return "briefcase.fill" }
        guard let category else { return "mappin.circle.fill" }
        return Self.symbols[MKPointOfInterestCategory(rawValue: category)] ?? "mappin.circle.fill"
    }

    /// Search keywords for the POI category in both the user's language and English.
    var categorySearchTerms: [String] {
        guard let category else { return [] }
        let poiCategory = MKPointOfInterestCategory(rawValue: category)
        return [
            Self.localizedCategoryName(for: poiCategory),
            Self.categoryNames[poiCategory]
        ].compactMap { $0 }
    }

    func matches(_ query: String) -> Bool {
        nickname?.localizedStandardContains(query) == true
            || displayName.localizedStandardContains(query)
            || name.localizedStandardContains(query)
            || address?.localizedStandardContains(query) == true
            || categorySearchTerms.contains { $0.localizedStandardContains(query) }
    }

    private static let symbols: [MKPointOfInterestCategory: String] = [
        .fitnessCenter: "figure.strengthtraining.traditional",
        .restaurant: "fork.knife",
        .cafe: "cup.and.saucer.fill",
        .bakery: "birthday.cake.fill",
        .brewery: "mug.fill",
        .winery: "wineglass.fill",
        .nightlife: "wineglass.fill",
        .foodMarket: "cart.fill",
        .store: "bag.fill",
        .gasStation: "fuelpump.fill",
        .evCharger: "bolt.car.fill",
        .parking: "parkingsign",
        .school: "graduationcap.fill",
        .university: "graduationcap.fill",
        .hospital: "cross.case.fill",
        .pharmacy: "pills.fill",
        .airport: "airplane",
        .hotel: "bed.double.fill",
        .park: "tree.fill",
        .nationalPark: "tree.fill",
        .beach: "beach.umbrella.fill",
        .marina: "sailboat.fill",
        .bank: "building.columns.fill",
        .atm: "banknote.fill",
        .movieTheater: "film.fill",
        .theater: "theatermasks.fill",
        .museum: "building.columns",
        .library: "books.vertical.fill",
        .stadium: "sportscourt.fill",
        .postOffice: "envelope.fill",
        .publicTransport: "tram.fill",
        .carRental: "car.fill",
        .police: "shield.fill",
        .fireStation: "flame.fill",
        .laundry: "washer.fill",
        .zoo: "pawprint.fill",
        .amusementPark: "ferriswheel"
    ]

    private static let categoryNames: [MKPointOfInterestCategory: String] = [
        .fitnessCenter: "Gym",
        .restaurant: "Restaurant",
        .cafe: "Cafe coffee",
        .bakery: "Bakery",
        .brewery: "Brewery",
        .winery: "Winery",
        .nightlife: "Bar",
        .foodMarket: "Grocery",
        .store: "Store shopping",
        .gasStation: "Gas station",
        .evCharger: "Charger charging Supercharger",
        .parking: "Parking",
        .school: "School",
        .university: "University",
        .hospital: "Hospital",
        .pharmacy: "Pharmacy",
        .airport: "Airport",
        .hotel: "Hotel",
        .park: "Park",
        .beach: "Beach",
        .bank: "Bank",
        .movieTheater: "Movies cinema",
        .museum: "Museum",
        .library: "Library",
        .stadium: "Stadium",
        .postOffice: "Post office"
    ]

    private static func localizedCategoryName(for category: MKPointOfInterestCategory) -> String? {
        switch category {
        case .fitnessCenter:
            String(localized: "Gym fitness", comment: "Search keywords for fitness center places")
        case .restaurant:
            String(localized: "Restaurant", comment: "Search keywords for restaurant places")
        case .cafe:
            String(localized: "Cafe coffee", comment: "Search keywords for cafe and coffee shop places")
        case .bakery:
            String(localized: "Bakery", comment: "Search keywords for bakery places")
        case .brewery:
            String(localized: "Brewery", comment: "Search keywords for brewery places")
        case .winery:
            String(localized: "Winery", comment: "Search keywords for winery places")
        case .nightlife:
            String(localized: "Bar nightlife", comment: "Search keywords for bar and nightlife places")
        case .foodMarket:
            String(localized: "Grocery supermarket", comment: "Search keywords for grocery and food market places")
        case .store:
            String(localized: "Store shopping", comment: "Search keywords for retail store places")
        case .gasStation:
            String(localized: "Gas station", comment: "Search keywords for gas station places")
        case .evCharger:
            String(localized: "Charger charging Supercharger", comment: "Search keywords for EV charging station places")
        case .parking:
            String(localized: "Parking", comment: "Search keywords for parking places")
        case .school:
            String(localized: "School", comment: "Search keywords for school places")
        case .university:
            String(localized: "University", comment: "Search keywords for university places")
        case .hospital:
            String(localized: "Hospital", comment: "Search keywords for hospital places")
        case .pharmacy:
            String(localized: "Pharmacy", comment: "Search keywords for pharmacy places")
        case .airport:
            String(localized: "Airport", comment: "Search keywords for airport places")
        case .hotel:
            String(localized: "Hotel", comment: "Search keywords for hotel places")
        case .park:
            String(localized: "Park", comment: "Search keywords for park places")
        case .beach:
            String(localized: "Beach", comment: "Search keywords for beach places")
        case .bank:
            String(localized: "Bank", comment: "Search keywords for bank places")
        case .movieTheater:
            String(localized: "Movies cinema", comment: "Search keywords for movie theater places")
        case .museum:
            String(localized: "Museum", comment: "Search keywords for museum places")
        case .library:
            String(localized: "Library", comment: "Search keywords for library places")
        case .stadium:
            String(localized: "Stadium", comment: "Search keywords for stadium places")
        case .postOffice:
            String(localized: "Post office", comment: "Search keywords for post office places")
        default:
            nil
        }
    }
}

/// Names a coordinate the way a person would: the point of interest the car parked at, a
/// name the user saved in Tessie, or failing those, the street address.
@MainActor
enum DrivePlaceResolver {
    struct Resolution: Sendable {
        var name: String
        var category: String?
        var address: String?
    }

    enum Failure: Error {
        case throttled
    }

    /// Looks up a place for `coordinate`. `tessieLabel` is Tessie's ending/starting location,
    /// which is either a saved name (e.g. "Home") or an address.
    static func resolve(_ coordinate: CLLocationCoordinate2D, tessieLabel: String?) async throws -> Resolution {
        async let addressLookup = reverseGeocode(coordinate)
        if let saved = savedName(from: tessieLabel) {
            let address = try await addressLookup
            return Resolution(name: saved, category: nil, address: address ?? tessieLabel)
        }
        let poi = try await nearestPointOfInterest(to: coordinate)
        let address = try await addressLookup
        if let poi {
            return Resolution(
                name: poi.name ?? address ?? DrivePlace.unknownPlaceholder,
                category: poi.pointOfInterestCategory?.rawValue,
                address: address
            )
        }
        return Resolution(
            name: address ?? shortAddress(tessieLabel) ?? DrivePlace.unknownPlaceholder,
            category: nil,
            address: address ?? tessieLabel
        )
    }

    /// Tessie reports saved locations by name ("Home", "Work") and everything else as an
    /// address; a short label with no digits or commas is a saved name.
    static func savedName(from label: String?) -> String? {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
              label.count <= 40, !label.contains(","), !label.contains(where: \.isNumber)
        else { return nil }
        return label
    }

    /// The street part of an address ("42 Danbury Avenue").
    static func shortAddress(_ address: String?) -> String? {
        guard let first = address?.split(separator: ",").first else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nearestPointOfInterest(to coordinate: CLLocationCoordinate2D) async throws -> MKMapItem? {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 150)
        request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [.parking, .publicTransport, .atm])
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .loadingThrottled {
            throw Failure.throttled
        } catch {
            return nil
        }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // The car parks in the lot, not at the pin, so accept anything within about 100 m and
        // take the closest.
        return response.mapItems
            .map { ($0, $0.location.distance(from: target)) }
            .filter { $0.1 <= 100 && $0.0.name?.isEmpty == false }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) else {
            return nil
        }
        do {
            let item = try await request.mapItems.first
            return item?.address?.shortAddress ?? item?.address?.fullAddress
        } catch let error as MKError where error.code == .loadingThrottled {
            throw Failure.throttled
        } catch {
            return nil
        }
    }
}
