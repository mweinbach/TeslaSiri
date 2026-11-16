import Foundation
import Testing
@testable import FleetKit

struct FleetModelTests {
    @Test func `vehicle info falls back from display name to vehicle tag to VIN`() throws {
        let vehicles = try FleetKitFixtures.decode([FleetVehicleInfo].self, from: """
        [
          {"vin":"VIN-1","display_name":"Roadrunner","vehicle_tag":"Model S"},
          {"vin":"VIN-2","display_name":null,"vehicle_tag":"Blue Y"},
          {"vin":"VIN-3","display_name":null,"vehicle_tag":null}
        ]
        """)

        #expect(vehicles.map(\.name) == ["Roadrunner", "Blue Y", "VIN-3"])
    }

    @Test func `snapshot decodes flexible numeric strings and dates`() throws {
        let snapshot = try FleetKitFixtures.decode(FleetSnapshotInfo.self, from: FleetKitFixtures.snapshotJSON)

        #expect(snapshot.batteryLevel == 82.4)
        #expect(snapshot.chargeRateMPH == 22.5)
        #expect(snapshot.latitude == 37.3317)
        #expect(snapshot.updatedAtDate == Date(timeIntervalSince1970: 1_710_000_000))
        #expect(snapshot.petModeOn == true)
        #expect(snapshot.defrostMode == "2")
    }

    @Test func `tire pressure summary rounds PSI readings`() throws {
        let snapshot = try FleetKitFixtures.decode(FleetSnapshotInfo.self, from: FleetKitFixtures.snapshotJSON)
        let tires = try #require(snapshot.tires)

        #expect(tires.displaySummary == "FL 39 PSI, FR 40 PSI, RL 41 PSI, RR 42 PSI")
        #expect(tires.hardWarnings == 1)
        #expect(tires.softWarnings == 0)
        #expect(tires.measuredAtDate == Date(timeIntervalSince1970: 1_710_000_001))
    }

    @Test func `drive info decodes trip metrics and timestamps`() throws {
        let drive = try FleetKitFixtures.decode(FleetDriveInfo.self, from: FleetKitFixtures.driveJSON)

        #expect(drive.id == "drive-1")
        #expect(drive.distanceMiles == 12.34)
        #expect(drive.durationMS == 1_860_000)
        #expect(drive.avgSpeedMPH == 23.9)
        #expect(drive.startedAtDate == Date(timeIntervalSince1970: 1_710_000_000))
        #expect(drive.endedAtDate == Date(timeIntervalSince1970: 1_710_001_860))
    }

    @Test func `software info decodes release version and notes`() throws {
        let software = try FleetKitFixtures.decode(FleetSoftwareInfo.self, from: FleetKitFixtures.softwareJSON)
        let note = try #require(software.releaseNotes.first)

        #expect(software.currentVersion == "2026.2.1")
        #expect(software.availableVersion == "2026.8.4")
        #expect(software.updateAvailable)
        #expect(software.installable)
        #expect(software.downloadPercent == 100)
        #expect(software.expectedDurationMinutes == 25)
        #expect(note.id == "Better routingNavigation")
        #expect(note.details == "Route planning improvements")
    }

    @Test func `control actions include charge actions`() throws {
        let actions = try FleetKitFixtures.decode(FleetControlActionsInfo.self, from: FleetKitFixtures.actionsJSON)

        #expect(actions.supports("door_lock"))
        #expect(actions.supports("set_charge_limit"))
        #expect(!actions.supports("remote_start_drive"))
        #expect(actions.schemas["set_charge_limit"] == ["percent"])
    }

    @Test func `fleet errors use user-facing descriptions`() {
        #expect(FleetKitError.notSignedIn.localizedDescription == "Open Wattie and add an access token for your vehicle provider.")
        #expect(FleetKitError.sessionExpired.localizedDescription == "Your vehicle provider access token is invalid or revoked. Open Wattie to replace it.")
        #expect(FleetKitError.unsupportedAction("honking").localizedDescription == "Your vehicle doesn't support honking right now.")
    }
}
