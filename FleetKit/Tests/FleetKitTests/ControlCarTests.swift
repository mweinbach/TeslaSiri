import AppIntents
import Foundation
import Synchronization
import Testing
@testable import FleetKit

struct ControlCarTests {
    private static func respond(_ request: URLRequest) -> (Int, Data) {
        if request.url?.path == "/vehicles" { return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8)) }
        return (200, FleetKitFixtures.commandResponse())
    }

    @Test func resolvesDefaultAndStartsHVACOnceBeforeSettingTargetAndLocking() async throws {
        try await withIsolatedFleetService(selectedVIN: "VIN-2", responder: Self.respond) { requests in
            let intent = ControlCarIntent()
            let changes = CarControlSettings()
            changes.climateOn = true
            changes.cabin = CabinClimateSettings(targetTemperatureCelsius: 22)
            changes.locked = true
            intent.changes = changes

            let value = try #require(try await intent.perform().value)
            #expect(value.succeeded && value.vin == "VIN-2")
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles", "/VIN-2/command/start_climate", "/VIN-2/command/set_temperatures", "/VIN-2/command/lock"])
            let query = requests().compactMap(\.url).first { $0.lastPathComponent == "set_temperatures" }?.query()
            #expect(query == "temperature=22.0")
        }
    }

    @Test func listedCarProvidesClimateConditionAndReceivesTheTemperatureChange() async throws {
        let timestamp = Int64(Date.now.timeIntervalSince1970 * 1_000)
        let roster = #"{"results":[{"vin":"A","last_state":{"display_name":"Silver"}},{"vin":"B","last_state":{"display_name":"Midnight"}}]}"#
        let state = """
            {"climate_state":{"timestamp":\(timestamp),"inside_temp":30,"driver_temp_setting":20},"gui_settings":{"gui_temperature_units":"F"}}
            """
        try await withIsolatedFleetService(selectedVIN: "A", responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(roster.utf8))
            case "/B/state": (200, Data(state.utf8))
            case "/B/command/start_climate", "/B/command/set_temperatures": (200, FleetKitFixtures.commandResponse())
            default: throw FleetKitError.badResponse
            }
        }) { requests in
            let cars = try #require(try await ListCarsIntent().perform().value)
            let midnight = try #require(cars.first { $0.name == "Midnight" })
            #expect(midnight.isDefaultCar == false)
            let check = GetVehicleInfoIntent(vehicle: midnight, topics: [.climate])
            let status = try #require(try await check.perform().value)
            #expect(status.vin == midnight.id)
            #expect(status.updatedAt == Date(timeIntervalSince1970: Double(timestamp) / 1_000))
            #expect(status.temperatureUnit == "°F")
            #expect(status.targetTemp == 68)
            let measured = try #require(status.insideTemp)
            try #require(measured > 80)
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles", "/B/state"])

            let intent = ControlCarIntent()
            let changes = CarControlSettings()
            changes.cabin = CabinClimateSettings(targetTemperatureCelsius: 22)
            intent.vehicle = midnight
            intent.changes = changes
            let result = try #require(try await intent.perform().value)
            #expect(result.succeeded && result.vin == midnight.id)
            #expect(requests().compactMap { $0.url?.path } == [
                "/vehicles", "/B/state", "/B/command/start_climate", "/B/command/set_temperatures"
            ])
        }
    }

    @Test func validatesAllFieldsBeforeDispatch() async throws {
        try await withIsolatedFleetService(responder: Self.respond) { requests in
            let intent = ControlCarIntent()
            let changes = CarControlSettings()
            changes.climateOn = true
            changes.chargeLimitPercent = 110
            intent.changes = changes
            await #expect(throws: FleetKitError.self) { _ = try await intent.perform() }

            changes.chargeLimitPercent = nil
            changes.climateOn = false
            changes.cabin = CabinClimateSettings(targetTemperatureCelsius: 22)
            intent.changes = changes
            await #expect(throws: FleetKitError.self) { _ = try await intent.perform() }

            intent.changes = CarControlSettings()
            await #expect(throws: FleetKitError.self) { _ = try await intent.perform() }
            #expect(!requests().contains { $0.httpMethod == "POST" })
        }
    }

    @Test func confirmsSensitiveChangesTogetherBeforeFirstWrite() async throws {
        let events = Mutex<[String]>([])
        try await withIsolatedFleetService(responder: { request in
            if request.httpMethod == "POST" {
                let path = request.url?.lastPathComponent ?? ""
                events.withLock { $0.append(path) }
            }
            return Self.respond(request)
        }) { _ in
            let intent = ControlCarIntent()
            intent.vehicle = VehicleEntity(id: "VIN-2", name: "Blue Y")
            let changes = CarControlSettings()
            changes.climateOn = true
            changes.chargeLimitPercent = 85
            changes.charging = true
            changes.locked = false
            intent.changes = changes
            let result = try await FleetIntentService.$sandboxConfirmationRecorder.withValue({ _ in
                events.withLock { $0.append("confirmation") }
            }) {
                try #require(try await intent.perform().value)
            }
            #expect(result.vin == "VIN-2" && result.succeeded)
            #expect(events.withLock { $0 } == ["confirmation", "start_climate", "set_charge_limit", "start_charging", "unlock"])
        }
    }

    @Test func unlockPrecedesActuationAndLockFollowsActuation() async throws {
        try await withIsolatedFleetService(responder: Self.respond) { requests in
            let changes = CarControlSettings()
            changes.openTrunk = .front
            changes.locked = false
            let intent = ControlCarIntent()
            intent.changes = changes
            try await FleetIntentService.$sandboxConfirmationRecorder.withValue({ _ in }) {
                _ = try await intent.perform()
                changes.locked = true
                _ = try await intent.perform()
            }
            #expect(requests().filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent } == ["unlock", "activate_front_trunk", "activate_front_trunk", "lock"])
        }
    }

    @Test func rejectsKnownUnsupportedEquipmentBeforeEarlierValidCommands() async throws {
        let roster = #"{"results":[{"vin":"VIN-1","last_state":{"vehicle_config":{"can_actuate_trunks":false,"can_accept_navigation_requests":false}}}]}"#
        try await withIsolatedFleetService(responder: { _ in (200, Data(roster.utf8)) }) { requests in
            let intent = ControlCarIntent()
            let changes = CarControlSettings()
            changes.climateOn = true
            changes.destination = "Palo Alto"
            intent.changes = changes
            await #expect(throws: FleetKitError.self) { _ = try await intent.perform() }
            changes.destination = nil
            changes.openTrunk = .rear
            await #expect(throws: FleetKitError.self) { _ = try await intent.perform() }
            #expect(!requests().contains { $0.httpMethod == "POST" })
        }
    }

    @Test func ventAndHonkUseImmediateStandalonePolicy() async throws {
        try await withIsolatedFleetService(responder: Self.respond) { requests in
            let intent = ControlCarIntent()
            let changes = CarControlSettings()
            changes.windows = .vent
            changes.honkHorn = true
            intent.changes = changes
            try await FleetIntentService.$sandboxConfirmationRecorder.withValue({ _ in Issue.record("Unexpected confirmation") }) {
                _ = try await intent.perform()
            }
            #expect(requests().filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent } == ["vent_windows", "honk"])
        }
    }

    @Test func reportsAcceptedStepsAndStopsAfterServerError() async throws {
        try await withIsolatedFleetService(responder: { request in
            if request.url?.lastPathComponent == "set_temperatures" { return (503, Data()) }
            return Self.respond(request)
        }) { requests in
            let intent = ControlCarIntent()
            let changes = CarControlSettings()
            changes.cabin = CabinClimateSettings(targetTemperatureCelsius: 22)
            changes.locked = true
            intent.changes = changes
            let value = try #require(try await intent.perform().value)
            #expect(!value.succeeded)
            #expect(value.appliedValue == "climate on")
            #expect(value.summary.contains("22.0°C"))
            #expect(requests().filter { $0.httpMethod == "POST" }.compactMap { $0.url?.lastPathComponent } == ["start_climate", "set_temperatures"])
        }
    }

    @Test func absentExplicitVehicleNeverFallsBackToDefault() async throws {
        try await withIsolatedFleetService(responder: Self.respond) { requests in
            let intent = ControlCarIntent()
            intent.vehicle = VehicleEntity(id: "REMOVED", name: "Removed car")
            let changes = CarControlSettings()
            changes.locked = true
            intent.changes = changes
            await #expect(throws: FleetKitError.self) { _ = try await intent.perform() }
            #expect(!requests().contains { $0.httpMethod == "POST" })
        }
    }
}
