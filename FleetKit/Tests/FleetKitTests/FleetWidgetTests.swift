import Foundation
import Testing
@testable import FleetKit

struct FleetWidgetTests {
    @Test func snapshotPreservesUnitsAndVehicleTimestamp() {
        let vehicle = FleetVehicleInfo(vin: "widget-car", displayName: "Blue Y")
        let state = FleetSnapshotInfo(
            vin: vehicle.vin,
            batteryLevel: 64,
            batteryRangeMiles: 100,
            insideTemp: 21,
            updatedAt: 1_710_000_000_000,
            temperatureInFahrenheit: false
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_710_003_600)
        let snapshot = FleetWidgetSnapshot(vehicle: vehicle, snapshot: state, usesMetric: true, mode: .live, fetchedAt: fetchedAt)
        #expect(snapshot.rangeDescription == "161 km")
        #expect(snapshot.temperatureDescription(snapshot.insideTemperature) == "21°C")
        #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 1_710_000_000))
        #expect(snapshot.fetchedAt == fetchedAt)
    }

    @Test func missingStatesNeverImplyLockedOrClosed() {
        let vehicle = FleetVehicleInfo(vin: "widget-car", displayName: "Car")
        let state = FleetSnapshotInfo(vin: vehicle.vin)
        let snapshot = FleetWidgetSnapshot(vehicle: vehicle, snapshot: state, usesMetric: false, mode: .live)
        #expect(snapshot.lockDescription == "Lock status unavailable")
        #expect(snapshot.openClosures == nil)
        #expect(!snapshot.canStartCharging)
        #expect(snapshot.updatedAt == nil)
    }

    @Test(arguments: ["Stopped", "Connected", "NoPower"])
    func chargingCanStartOnlyWhenConnected(_ state: String) {
        var snapshot = FleetWidgetSnapshot.sample
        snapshot.chargingState = state
        #expect(snapshot.canStartCharging)
        snapshot.chargingState = "Disconnected"
        #expect(!snapshot.canStartCharging)
        snapshot.chargingState = "Charging"
        #expect(!snapshot.canStartCharging)
        #expect(snapshot.isCharging)
    }

    @Test func cacheSeparatesVehiclesAndSandboxModes() throws {
        let suite = "FleetWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetWidgetStore(appGroup: suite)
        var first = FleetWidgetSnapshot.sample
        first.vin = "car-one"
        var second = first
        second.vin = "car-two"
        second.batteryLevel = 35
        store.save(first)
        store.save(second)
        #expect(store.cached(vin: "car-one", mode: .demoVehicle) == first)
        #expect(store.cached(vin: "car-two", mode: .demoVehicle) == second)
        #expect(store.cached(vin: "car-one", mode: .live) == nil)
        store.clear(reload: false)
        #expect(store.cached(vin: "car-one", mode: .demoVehicle) == nil)
    }

    @Test func providerSelectionPreservesLegacyTessieVINAndInvalidatesOldWidgetData() throws {
        let suite = "FleetProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("first-car", forKey: FleetKitConfig.selectedVINDefaultsKey)
        let tokens = FleetSharedTokenStore(appGroup: suite) { _ in "same-token" }
        let widgets = FleetWidgetStore(appGroup: suite)
        let originalScope = tokens.sessionScope(for: "same-token")
        #expect(tokens.provider == .tessie)
        #expect(tokens.selectedVIN() == "first-car")
        widgets.save(.sample)

        tokens.selectProvider(.teslascope)
        #expect(tokens.sessionScope(for: "same-token") != originalScope)
        #expect(tokens.selectedVIN() == nil)
        #expect(widgets.cached(vin: FleetWidgetSnapshot.sample.vin, mode: .demoVehicle) == nil)
        tokens.save(selectedVIN: "second-car")
        #expect(FleetSharedTokenStore(appGroup: suite).provider == .teslascope)

        tokens.selectProvider(.tessie)
        #expect(tokens.selectedVIN() == "first-car")
        #expect(tokens.sessionScope(for: "same-token") != originalScope)
        tokens.selectProvider(.teslascope)
        #expect(tokens.selectedVIN() == "second-car")
    }

    @Test func snapshotCacheOmitsLocationAndCredentials() throws {
        let encoded = try JSONEncoder().encode(FleetWidgetSnapshot.sample)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["latitude"] == nil)
        #expect(fields["longitude"] == nil)
        #expect(fields["accessToken"] == nil)
    }

    @Test func credentialInvalidationClearsWidgetCache() throws {
        let suite = "FleetWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetWidgetStore(appGroup: suite)
        let snapshot = FleetWidgetSnapshot.sample
        store.save(snapshot)
        #expect(store.cached(vin: snapshot.vin, mode: .demoVehicle) != nil)
        FleetSharedTokenStore(appGroup: suite).invalidateSession()
        #expect(store.cached(vin: snapshot.vin, mode: .demoVehicle) == nil)
    }

    @Test func removedPinnedVehicleDoesNotFallBackToAnotherCar() async throws {
        let suite = "FleetWidgetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sandbox = FleetSandboxStore(appGroup: suite)
        sandbox.setMode(.demoVehicle)
        let service = FleetIntentService(sandbox: sandbox)
        let intent = FleetWidgetActionIntent(action: .lock, vehicle: VehicleEntity(id: "removed-car", name: "Removed car"))
        await #expect(throws: FleetKitError.self) {
            try await FleetIntentService.$testingOverride.withValue(service) {
                _ = try await intent.perform()
            }
        }
        #expect(sandbox.commandLog().isEmpty)
    }

    @Test func widgetActionsExposeOnlyNonDisruptiveCommands() {
        #expect(FleetWidgetAction.lock.command == "door_lock")
        #expect(FleetWidgetAction.startClimate.command == "auto_conditioning_start")
        #expect(FleetWidgetAction.startCharging.command == "charge_start")
        #expect(FleetWidgetAction.refresh.command == nil)
    }
}
