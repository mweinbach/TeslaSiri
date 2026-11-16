import Foundation
import Testing
@testable import FleetKit

struct FleetKitLogTests {
    @Test(arguments: [
        (FleetKitError.notSignedIn, "Open Wattie and add an access token for your vehicle provider."),
        (.sessionExpired, "Your vehicle provider access token is invalid or revoked. Open Wattie to replace it."),
        (.api("The vehicle is offline."), "The vehicle is offline."),
        (.api(nil), "Your vehicle provider returned an error."),
        (.badResponse, "Your vehicle provider returned an unexpected response."),
        (.unsupportedAction("starting climate"), "Your vehicle doesn't support starting climate right now.")
    ])
    func `fleet errors expose messages to Siri across process boundaries`(error: FleetKitError, expected: String) {
        let siriError: any CustomLocalizedStringResourceConvertible = error
        #expect(String(localized: siriError.localizedStringResource) == expected)
        #expect(error.localizedDescription == expected)
    }

    @Test func `vin helper redacts to last six characters`() {
        #expect(FleetKitLog.vin("5YJ3E1EA7KF000316") == "…000316")
        #expect(FleetKitLog.vin("ABC123") == "ABC123")
        #expect(FleetKitLog.vin("") == "")
    }

    @Test func `milliseconds since a past instant is non-negative`() {
        let start = ContinuousClock.now
        #expect(FleetKitLog.milliseconds(since: start) >= 0)
    }

    @Test func `intent log failure returns the original error`() {
        let log = FleetIntentLog(LockVehicleIntent.self, vehicle: VehicleEntity(id: "5YJ3E1EA7KF000316", name: "Test Car"))
        let original = FleetKitError.sessionExpired
        let returned = log.failure(original)
        #expect((returned as? FleetKitError)?.localizedDescription == original.localizedDescription)
    }

    @Test func `intent log success does not crash without vehicle`() {
        let log = FleetIntentLog(GetBatteryLevelIntent.self)
        log.success("test detail")
    }
}
