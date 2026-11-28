import AppIntentsTesting
import Testing

@Suite("Wattie - AppIntentsTesting Metadata & Definitions")
struct WattieAppIntentsTests {
    static let definitions = IntentDefinitions(bundleIdentifier: "com.maxweinbach.TeslaSiri")

    @Test("All 20 Siri AI tools are registered under the app bundle")
    func registersAllSiriTools() {
        let toolNames = [
            "ListCarsIntent",
            "GetVehicleInfoIntent",
            "GetVehicleStatusIntent",
            "LocateCarIntent",
            "ControlCarIntent",
            "UnlockOrOpenCarIntent",
            "SetCabinTemperatureIntent",
            "SetSeatClimateIntent",
            "SendNavigationIntent",
            "InstallSoftwareUpdateIntent",
            "CancelSoftwareUpdateIntent",
            "FindDrivesIntent",
            "GetDriveDetailsIntent",
            "GetDrivingStatsIntent",
            "GetRecentChargesIntent",
            "GetChargeDetailsIntent",
            "GetChargingStatsIntent",
            "GetBatteryHealthIntent",
            "GetSoftwareStatusIntent",
            "GetReleaseNotesIntent"
        ]
        for name in toolNames {
            let def = Self.definitions.intents[name]
            #expect(def.identifier == name)
            #expect(def.bundleIdentifier == "com.maxweinbach.TeslaSiri")
        }
    }

    @Test("All 5 bundled App Skills are addressable by name")
    func registersAllBundledSkills() {
        let skillNames = [
            "vehicle-control",
            "prepare-trip",
            "overnight-security-check",
            "driving-and-energy-insights",
            "software-update-advisor"
        ]
        for name in skillNames {
            let skill = Self.definitions.skills[name]
            #expect(skill.skillName == name)
            #expect(skill.bundleIdentifier == "com.maxweinbach.TeslaSiri")
        }
    }

    @Test("Server-backed entities and generable inputs are registered")
    func registersCoreEntities() {
        let entityNames = [
            "VehicleEntity",
            "VehicleStatusEntity",
            "DriveEntity",
            "ChargeSessionEntity",
            "SoftwareUpdateEntity",
            "ReleaseNoteEntity"
        ]
        for name in entityNames {
            let entity = Self.definitions.entities[name]
            #expect(entity.typeIdentifier == name)
            #expect(entity.bundleIdentifier == "com.maxweinbach.TeslaSiri")
        }

        let generableNames = [
            "CarControlSettings",
            "DriveFilterCriteria"
        ]
        for name in generableNames {
            let entity = Self.definitions.transientEntities[name]
            #expect(entity.typeIdentifier == name)
            #expect(entity.bundleIdentifier == "com.maxweinbach.TeslaSiri")
        }
    }
}
