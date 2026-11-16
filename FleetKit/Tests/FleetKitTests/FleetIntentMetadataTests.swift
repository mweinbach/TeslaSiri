import AppIntents
import Foundation
import Testing
@testable import FleetKit

struct FleetIntentMetadataTests {
    @Test func `search intent preserves system search criteria`() {
        let intent = SearchFleetIntent(criteria: StringSearchCriteria(term: "battery"))

        #expect(intent.criteria.term == "battery")
        #expect(SearchFleetIntent.searchScopes == [.general])
    }

    @Test func `all vehicle scoped intents default to no explicit vehicle`() {
        #expect(LockVehicleIntent().vehicle == nil)
        #expect(UnlockVehicleIntent().vehicle == nil)
        #expect(StartClimateIntent().vehicle == nil)
        #expect(VentWindowsIntent().vehicle == nil)
        #expect(OpenTrunkIntent().vehicle == nil)
        #expect(OpenFrunkIntent().vehicle == nil)
        #expect(SetChargeLimitIntent().vehicle == nil)
        #expect(StopClimateIntent().vehicle == nil)
        #expect(SetCabinTemperatureIntent().vehicle == nil)
        #expect(SetMaxDefrostIntent().vehicle == nil)
        #expect(SetPetModeIntent().vehicle == nil)
        #expect(SetBioweaponModeIntent().vehicle == nil)
        #expect(FlashLightsIntent().vehicle == nil)
        #expect(HonkHornIntent().vehicle == nil)
        #expect(SendNavigationIntent().vehicle == nil)
        #expect(GetBatteryLevelIntent().vehicle == nil)
        #expect(GetVehicleMileageIntent().vehicle == nil)
        #expect(GetTirePressureIntent().vehicle == nil)
        #expect(GetVehicleStatusIntent().vehicle == nil)
        #expect(GetRecentDrivesIntent().vehicle == nil)
        #expect(GetLastDriveIntent().vehicle == nil)
        #expect(GetSoftwareStatusIntent().vehicle == nil)
        #expect(InstallSoftwareUpdateIntent().vehicle == nil)
        #expect(CancelSoftwareUpdateIntent().vehicle == nil)
        #expect(SetSeatClimateIntent().vehicle == nil)
        #expect(SetSteeringWheelHeaterIntent().vehicle == nil)
        #expect(SetChargingAmpsIntent().vehicle == nil)
        #expect(ControlCarIntent().vehicle == nil)
        #expect(GetDriveDetailsIntent().vehicle == nil)
        #expect(GetDrivingStatsIntent().vehicle == nil)
        #expect(GetChargingStatsIntent().vehicle == nil)
        #expect(GetRecentChargesIntent().vehicle == nil)
        #expect(GetChargeDetailsIntent().vehicle == nil)
        #expect(GetBatteryHealthIntent().vehicle == nil)
        #expect(StartChargingIntent().vehicle == nil)
        #expect(StopChargingIntent().vehicle == nil)
        #expect(SetChargePortIntent().vehicle == nil)
        #expect(SetSentryModeIntent().vehicle == nil)
        #expect(ConfigureCabinClimateIntent().vehicle == nil)
        #expect(FindDrivesIntent().vehicle == nil)
        #expect(GetReleaseNotesIntent().vehicle == nil)
        #expect(CloseWindowsIntent().vehicle == nil)
        #expect(GetVehicleInfoIntent().vehicle == nil)
    }

    @Test(
        "Cabin temperature clamps to Tesla range and rounds to half-degree Celsius",
        arguments: [
            (Measurement(value: 40.0, unit: UnitTemperature.celsius), 28.0),
            (Measurement(value: 10.0, unit: UnitTemperature.celsius), 15.0),
            (Measurement(value: 20.24, unit: UnitTemperature.celsius), 20.0),
            (Measurement(value: 20.26, unit: UnitTemperature.celsius), 20.5),
            (Measurement(value: 68.0, unit: UnitTemperature.fahrenheit), 20.0)
        ]
    )
    func cabinTemperatureTarget(input: Measurement<UnitTemperature>, expectedCelsius: Double) {
        #expect(SetCabinTemperatureIntent.targetCelsius(for: input) == expectedCelsius)
    }
}
