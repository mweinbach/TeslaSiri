import AppIntents
import Foundation
import Testing
@testable import FleetKit

struct FleetDriveLatencyTests {
    private func drive(vin: String = "VIN-1", end: Int64? = 1_710_000_100_000) -> DriveEntity {
        DriveEntity(info: FleetDriveInfo(
            sessionID: "\(vin):123", vin: vin, distanceMiles: 5, durationMS: 100_000,
            avgSpeedMPH: nil, maxSpeedMPH: nil, energyUsedKWH: nil,
            startedAt: 1_710_000_000_000, endedAt: end, startAddress: nil, endAddress: nil,
            startLatitude: 10, startLongitude: 20, endLatitude: 11, endLongitude: 21
        ))
    }

    @Test func knownDriveChecksMembershipWithoutLoadingHistory() async throws {
        try await withIsolatedFleetService(responder: { request in
            #expect(request.url?.path == "/vehicles")
            return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
        }) { requests in
            let intent = GetDriveDetailsIntent()
            let provided = drive()
            intent.drive = provided
            let result = try #require(try await intent.perform().value)
            #expect(result.id == provided.id)
            #expect(result.distanceMiles == 5)
            #expect(requests().map { $0.url?.path } == ["/vehicles"])

            let unknown = GetDriveDetailsIntent()
            unknown.drive = drive(vin: "NOT-ON-ACCOUNT")
            await #expect(throws: FleetKitError.self) {
                _ = try await unknown.perform()
            }
        }
    }

    @Test func completedGeometryCoalescesAcrossStylesAndSeparatesBoundsAndAccounts() async throws {
        // Both sessions use the same VIN, drive ID and time bounds but return different tracks.
        for latitude in [5, 15] {
            try await withIsolatedFleetService(responder: { request in
                #expect(request.url?.path == "/VIN-1/path")
                return (200, Data("""
                    {"results":[{"latitude":\(latitude),"longitude":0},{"latitude":2,"longitude":3}]}
                    """.utf8))
            }) { requests in
                let service = FleetIntentService.make()
                let trip = drive()
                async let standard = SiriMapSnapshotRenderer.renderDriveRoute(
                    for: trip, service: service, style: .standard, allowNetworkSnapshot: false
                )
                async let hybrid = SiriMapSnapshotRenderer.renderDriveRoute(
                    for: trip, service: service, style: .hybrid, allowNetworkSnapshot: false
                )
                let (first, second) = await (standard, hybrid)
                #expect(first.points.first?.latitude == Double(latitude))
                #expect(first.points == second.points)
                #expect(requests().count == 1)

                _ = await SiriMapSnapshotRenderer.resolveRoutePoints(
                    for: drive(end: 1_710_000_101_000), service: service, allowGeocoding: false
                )
                #expect(requests().count == 2)
            }
        }
    }

    @Test func missingRecordedPathRetriesAndOpenEndedDriveNeverReusesGeometry() async throws {
        try await withIsolatedFleetService(responder: { _ in
            (200, Data(#"{"results":[]}"#.utf8))
        }) { requests in
            for _ in 0..<2 {
                let fallback = await SiriMapSnapshotRenderer.resolveRoutePoints(for: drive(), allowGeocoding: false)
                #expect(fallback.first?.latitude == 10)
                #expect(fallback.last?.latitude == 11)
            }
            #expect(requests().count == 2)
        }
        try await withIsolatedFleetService(responder: { _ in
            (200, Data(#"{"results":[{"latitude":1,"longitude":2},{"latitude":3,"longitude":4}]}"#.utf8))
        }) { requests in
            for _ in 0..<2 {
                let path = await SiriMapSnapshotRenderer.resolveRoutePoints(for: drive(end: nil), allowGeocoding: false)
                #expect(path.count == 2)
            }
            #expect(requests().count == 2)
        }
    }
}
