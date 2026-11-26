import CoreLocation
import Foundation
import MapKit

struct DriveEndpointAddresses: Equatable, Sendable {
    var start: String?
    var end: String?
}

let driveEndpointAddressGeocoder = DriveEndpointAddressGeocoder()

actor DriveEndpointAddressGeocoder {
    private let cachedAddresses = NSCache<NSString, NSString>()
    private var pending: [String: Task<String?, Never>] = [:]

    init() {
        cachedAddresses.countLimit = 512
    }

    func addresses(for drive: FleetDriveSession, route: [FleetRoutePoint]) async -> DriveEndpointAddresses {
        let startAddress: String?
        if let start = drive.startAddress {
            startAddress = start
        } else {
            startAddress = await address(for: route.first)
        }

        let endAddress: String?
        if let end = drive.endAddress {
            endAddress = end
        } else if route.first?.coordinateKey == route.last?.coordinateKey {
            endAddress = startAddress
        } else {
            endAddress = await address(for: route.last)
        }
        return DriveEndpointAddresses(start: startAddress, end: endAddress)
    }

    func address(latitude: Double?, longitude: Double?) async -> String? {
        guard let latitude, let longitude else {
            return nil
        }
        return await address(for: FleetRoutePoint(latitude: latitude, longitude: longitude))
    }

    private func address(for point: FleetRoutePoint?) async -> String? {
        guard !Task.isCancelled, let point, let latitude = point.latitude, let longitude = point.longitude else {
            return nil
        }

        let key = point.coordinateKey
        if let cached = cachedAddresses.object(forKey: key as NSString) { return cached as String }
        if let lookup = pending[key] { return await lookup.value }

        let lookup = Task { await lookupAddress(latitude: latitude, longitude: longitude) }
        pending[key] = lookup
        let address = await lookup.value
        pending[key] = nil
        if let address {
            cachedAddresses.setObject(address as NSString, forKey: key as NSString)
        }
        return address
    }

    private func lookupAddress(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            guard let mapItem = try await request.mapItems.first else {
                return nil
            }
            return formattedAddress(from: mapItem)
        } catch {
            return nil
        }
    }

    private func formattedAddress(from mapItem: MKMapItem) -> String {
        [mapItem.address?.shortAddress, mapItem.address?.fullAddress, mapItem.name]
            .compactMap(normalizedPlacemarkPart)
            .first ?? String(localized: "Address unavailable", comment: "Fallback when reverse geocoding returns no address")
    }

    private func normalizedPlacemarkPart(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
