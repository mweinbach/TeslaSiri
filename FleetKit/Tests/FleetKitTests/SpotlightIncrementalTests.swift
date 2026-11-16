import Foundation
import Testing
@testable import FleetKit

struct SpotlightIncrementalTests {
    @Test func shortDashboardPagesRetainOlderIndexedIDs() {
        let now = Date()
        var group = SpotlightIndexManifest.Group()
        group.digests = Dictionary(uniqueKeysWithValues: (0..<50).map { ("VIN:\($0)", Data()) })
        group.completeAt = now
        let page = Set((0..<10).map { "VIN:\($0)" })
        #expect(group.canUsePage(ids: page, requested: 10, limit: 50, at: now))
        #expect(group.removedIDs(in: page, complete: false).isEmpty)
        #expect(group.removedIDs(in: page, complete: true).count == 40)
        #expect(!group.canUsePage(ids: page, requested: 10, limit: 50, at: now.addingTimeInterval(901)))
        let changedHead = Set(page.dropFirst()).union(["VIN:51"])
        #expect(!group.canUsePage(ids: changedHead, requested: 10, limit: 50, at: now))
        #expect(group.canUsePage(ids: ["VIN:1"], requested: 10, limit: 50, at: now))
        #expect(group.canUsePage(ids: [], requested: 50, limit: 50, at: now))
    }

    @Test func backgroundHistoryRejectsPartialCoverageWithoutChangingOrdinaryReads() async throws {
        try await withIsolatedFleetService { _ in
            (200, Data(#"{"results":[{"id":1,"started_at":5},{"started_at":6}]}"#.utf8))
        } body: { _ in
            let service = FleetIntentService.make()
            let drives = try await service.drives(vin: "VIN-1", limit: 50)
            let charges = try await service.charges(vin: "VIN-1", limit: 50)
            #expect(drives.count == 1)
            #expect(charges.count == 1)
            await #expect(throws: FleetKitError.self) {
                try await service.drives(vin: "VIN-1", limit: 50, requireCompleteRows: true)
            }
            await #expect(throws: FleetKitError.self) {
                try await service.charges(vin: "VIN-1", limit: 50, requireCompleteRows: true)
            }
        }
    }

    @Test func dashboardPayloadsKeepSiriOnlyFieldsAndMarkMalformedHistory() throws {
        let vin = "VIN"
        let payload = Data(#"{"results":[{"id":10,"started_at":5,"tag":"business","autopilot_distance":2.2},{"started_at":6}]}"#.utf8)
        let (drives, count) = try FleetIntentClient.spotlightDrives(payload, vin: vin)
        #expect(drives.map(\.sessionID) == ["VIN:10"])
        #expect(count == 2)
        #expect(drives.first?.autopilotDistanceMiles == 2.2)
        #expect(drives.first?.tag == "business")
        let charges = try FleetIntentClient.spotlightCharges(Data(#"{"results":[{"id":"a","started_at":5,"is_supercharger":true,"location":"A"}]}"#.utf8), vin: vin)
        #expect(charges.0.first?.location == "A")
        #expect(charges.0.first?.isSupercharger == true)
        let state = Data(#"{"climate_state":{"steering_wheel_heater":true},"vehicle_state":{"car_version":"2026.42"}}"#.utf8)
        let (snapshot, software) = try FleetIntentClient.spotlightState(state, tires: Data(#"{"front_left":41}"#.utf8), vin: vin)
        #expect(snapshot.steeringWheelHeaterOn == true)
        #expect(snapshot.tires?.frontLeftPSI == 41)
        #expect(software.currentVersion == "2026.42")
        #expect(try FleetIntentClient.spotlightNotes(Data(#"{"release_notes":[]}"#.utf8)).isEmpty)
        #expect(throws: FleetKitError.self) { try FleetIntentClient.spotlightNotes(Data("{}".utf8)) }
    }
}
