import AppIntents
import FleetKit
import MapKit
import SwiftUI

struct DriveRouteMap: View {
    let route: [FleetRoutePoint]
    let selectedPointIndex: Int
    let driveSessionID: String?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var geometry: RouteGeometry?

    init(route: [FleetRoutePoint], selectedPointIndex: Int, driveSessionID: String? = nil) {
        self.route = route
        self.selectedPointIndex = selectedPointIndex
        self.driveSessionID = driveSessionID
    }

    var body: some View {
        ZStack {
            if let geometry {
                Map(position: $cameraPosition) {
                    MapPolyline(geometry.polyline)
                        .stroke(AppTheme.climateBlue, lineWidth: 5)

                    Marker("Start", systemImage: "flag.fill", coordinate: geometry.start)
                        .tint(AppTheme.chargeGreen)

                    Marker("End", systemImage: "flag.checkered", coordinate: geometry.end)
                        .tint(.black)

                    if let selectedCoordinate = route[safe: selectedPointIndex]?.coordinate {
                        Marker("Vehicle", systemImage: "car.fill", coordinate: selectedCoordinate)
                            .tint(AppTheme.accent)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
            } else {
                ContentUnavailableView("No route", systemImage: "map", description: Text("Select a drive with normalized route geometry."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.surface)
            }
        }
        .onAppear {
            updateGeometry(refit: true)
        }
        .onChange(of: route) {
            updateGeometry(refit: false)
        }
        .appEntityIdentifier(driveEntityIdentifier)
    }

    private func updateGeometry(refit: Bool) {
        let updated = RouteGeometry(route: route)
        if let updated, refit || updated.cameraKey != geometry?.cameraKey {
            cameraPosition = .rect(updated.cameraRect)
        }
        geometry = updated
    }

    private var driveEntityIdentifier: EntityIdentifier? {
        guard let driveSessionID, !driveSessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: driveSessionID)
    }
}

private struct RouteGeometry {
    let polyline: MKPolyline
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let cameraRect: MKMapRect
    let cameraKey: String

    init?(route: [FleetRoutePoint]) {
        let coordinates = route.compactMap(\.coordinate)
        guard let first = coordinates.first, let last = coordinates.last else { return nil }
        start = first
        end = last
        polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        cameraKey = [route.first?.id, route.last?.id, String(route.count)].compactMap { $0 }.joined(separator: ":")

        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1, height: 1))
        for coordinate in coordinates.dropFirst() {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 1, height: 1)))
        }
        let widthPadding = max(rect.size.width * 0.24, 1_500)
        let topPadding = max(rect.size.height * 0.48, 2_600)
        let bottomPadding = max(rect.size.height * 0.24, 1_500)
        cameraRect = MKMapRect(
            x: rect.minX - widthPadding,
            y: rect.minY - topPadding,
            width: rect.size.width + widthPadding * 2,
            height: rect.size.height + topPadding + bottomPadding
        )
    }
}

