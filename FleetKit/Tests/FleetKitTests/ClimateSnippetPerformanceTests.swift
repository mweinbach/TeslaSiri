import AppIntents
import Foundation
import Testing
@testable import FleetKit

struct ClimateSnippetPerformanceTests {
    @Test func firstClimateCardAndWarmAdjustmentAvoidStateAndExtraStart() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { sandbox, service, requests in
            let vehicle = VehicleEntity(id: "VIN-1", name: "Roadrunner")
            let intent = SetCabinTemperatureIntent()
            intent.temperature = Measurement(value: 72, unit: .fahrenheit)
            _ = try await intent.perform()
            let receipt = try #require(ClimateCommandReceipt.latest(vin: vehicle.id, scope: service.sessionScopeID, group: service.appGroupIdentifier))
            #expect(receipt.targetCelsius == 22)
            #expect(receipt.recentlyStarted())
            let card = ClimateControlSnippetIntent(vehicle: vehicle, appliedSummary: receipt.summary)
            card.interactionID = receipt.interactionID
            let beforeRender = requests().count
            _ = try await card.perform()
            _ = try await card.perform()
            #expect(requests().count == beforeRender)

            let adjust = AdjustSnippetClimateIntent(vehicle: vehicle, targetFahrenheit: 74, turnOff: false,
                                                    interactionID: receipt.interactionID, scope: service.sessionScopeID)
            _ = try await adjust.perform()
            var paths = requests().compactMap { $0.url?.lastPathComponent }.filter { $0 != "vehicles" }
            #expect(paths == ["start_climate", "set_temperatures", "set_temperatures"])
            let newReceipt = try #require(ClimateCommandReceipt.latest(vin: vehicle.id, scope: service.sessionScopeID, group: service.appGroupIdentifier))
            #expect(newReceipt.targetCelsius == 23.5)

            try await service.runControl(action: "auto_conditioning_stop", vin: vehicle.id, humanName: "stopping climate")
            #expect(ClimateCommandReceipt.latest(vin: vehicle.id, scope: service.sessionScopeID, group: service.appGroupIdentifier)?.running == false)
            _ = try await adjust.perform()
            paths = requests().compactMap { $0.url?.lastPathComponent }.filter { $0 != "vehicles" }
            #expect(Array(paths.suffix(3)) == ["stop_climate", "start_climate", "set_temperatures"])

            let count = requests().count
            sandbox.setMode(.dryRun)
            await #expect(throws: FleetKitError.self) { try await adjust.perform() }
            #expect(requests().count == count)
            #expect(sandbox.commandLog().isEmpty)
        }
    }

    @Test func controlCarUpdatesPreviouslyDisplayedClimateCard() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" { return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8)) }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { _, service, requests in
            let vehicle = VehicleEntity(id: "VIN-1", name: "Roadrunner")
            let card = ClimateControlSnippetIntent(vehicle: vehicle, appliedSummary: "Started",
                                                   scope: service.sessionScopeID, running: true, targetCelsius: 20)
            _ = try await card.perform()
            let control = ControlCarIntent()
            let changes = CarControlSettings()
            changes.targetTemperature = 26
            changes.temperatureUnit = .celsius
            control.vehicle = vehicle
            control.changes = changes
            let result = try #require(try await control.perform().value)
            #expect(result.succeeded)
            let receipt = try #require(ClimateCommandReceipt.latest(vin: vehicle.id, scope: service.sessionScopeID,
                                                                     group: service.appGroupIdentifier))
            #expect(receipt.targetCelsius == 26)
            #expect(receipt.running == true)
            #expect(receipt.interactionID == card.interactionID)
            let count = requests().count
            _ = try await card.perform()
            #expect(requests().count == count)
        }
    }

    @MainActor
    @Test func cardShowsOnlyKnownValuesAndUsesTheLatestObservation() {
        let vehicle = VehicleEntity(id: "VIN", name: "Car")
        let unknown = ClimateControlSnippetView(vehicle: vehicle, status: nil, appliedSummary: "")
        #expect(unknown.displayedTarget == nil)
        #expect(unknown.displayedRunning == nil)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = ClimateCommandReceipt(sessionScope: "test", interactionID: "card", date: now,
                                           targetCelsius: 20, targetSetAt: now, running: true, startedAt: now, summary: "")
        func view(observedAt: Date) -> ClimateControlSnippetView {
            let snapshot = FleetSnapshotInfo(vin: vehicle.id, targetTemp: 60, hvacOn: false,
                                             updatedAt: Int64(observedAt.timeIntervalSince1970 * 1000),
                                             temperatureInFahrenheit: true)
            return ClimateControlSnippetView(vehicle: vehicle, status: VehicleStatusEntity(snapshot: snapshot, vehicleName: vehicle.name),
                                            appliedSummary: "", receipt: receipt, interactionID: "card", sessionScope: "test")
        }
        let earlier = view(observedAt: now.addingTimeInterval(-1))
        #expect(abs((earlier.displayedTarget?.value ?? 0) - 68) < 0.01)
        #expect(earlier.displayedRunning == true)
        let later = view(observedAt: now.addingTimeInterval(1))
        #expect(later.displayedTarget?.value == 60)
        #expect(later.displayedRunning == false)
        #expect(receipt.recentlyStarted(at: now.addingTimeInterval(29)))
        #expect(!receipt.recentlyStarted(at: now.addingTimeInterval(30)))
        let stopped = FleetSnapshotInfo(vin: vehicle.id, hvacOn: false,
                                       updatedAt: Int64(now.addingTimeInterval(1).timeIntervalSince1970 * 1000))
        #expect(!receipt.recentlyStarted(at: now.addingTimeInterval(2), observation: stopped))
    }
}
