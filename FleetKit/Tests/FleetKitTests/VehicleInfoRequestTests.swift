import AppIntents
import Foundation
import Testing
@testable import FleetKit

struct VehicleInfoRequestTests {
    @Test func freshBatteryAndRangeComeFromTheRoster() async throws {
        let timestamp = Int64(Date.now.timeIntervalSince1970 * 1_000) - 1_000
        let roster = """
        {"results":[{"vin":"VIN-1","last_state":{"charge_state":{"timestamp":\(timestamp),"battery_level":"73","battery_range":221.5}}}]}
        """
        try await withIsolatedFleetService(responder: { request in
            guard request.url?.path == "/vehicles" else { throw FleetKitError.badResponse }
            return (200, Data(roster.utf8))
        }) { requests in
            let info = try #require(try await GetVehicleInfoIntent(topics: [.battery, .range]).perform().value)
            #expect(info.batteryPercent == 73)
            #expect(info.batteryRangeMiles == 221.5)
            #expect(info.updatedAt == Date(timeIntervalSince1970: Double(timestamp) / 1_000))
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles"])
        }
    }

    @Test func liveClimateReceiptReadsAmbientDataWithoutAnotherGET() async throws {
        let timestamp = Int64(Date.now.timeIntervalSince1970 * 1_000) - 1_000
        let roster = """
        {"results":[{"vin":"VIN-1","last_state":{"charge_state":{"timestamp":\(timestamp),"battery_level":75},"climate_state":{"timestamp":\(timestamp),"inside_temp":20,"outside_temp":5,"driver_temp_setting":21,"is_climate_on":false},"gui_settings":{"gui_temperature_units":"F"}}}]}
        """
        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(roster.utf8))
            case "/VIN-1/command/start_climate": (200, FleetKitFixtures.commandResponse(result: true))
            default: throw FleetKitError.badResponse
            }
        }) { requests in
            let service = FleetIntentService.make()
            _ = try await service.resolvedVehicle("VIN-1")
            let initial = await service.cachedClimateSnapshot(vin: "VIN-1")
            #expect(initial?.hvacOn == false)
            #expect(initial?.insideTemp == 68)
            try await service.runControl(action: "auto_conditioning_start", vin: "VIN-1", humanName: "starting climate")
            let after = await service.cachedClimateSnapshot(vin: "VIN-1")
            #expect(after?.insideTemp == 68)
            #expect(after?.outsideTemp == 41)
            #expect(after?.updatedAt == timestamp)
            #expect(after?.hvacOn == nil)
            #expect(after?.targetTemp == nil)
            let battery = try #require(try await GetVehicleInfoIntent(topics: [.battery]).perform().value)
            #expect(battery.batteryPercent == 75)
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles", "/VIN-1/command/start_climate"])
        }
    }

    @Test(arguments: [true, false])
    func incompleteOrStaleChargeFallsBackToStateOnly(stale: Bool) async throws {
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        let chargeTime = now - 3_700_000
        let rosterCharge = stale
            ? "\"timestamp\":\(chargeTime),\"battery_level\":10,\"battery_range\":20"
            : "\"timestamp\":\(now),\"battery_level\":10"
        let roster = """
        {"results":[{"vin":"VIN-1","last_state":{"charge_state":{\(rosterCharge)},"drive_state":{"timestamp":\(now)}}}]}
        """
        let state = """
        {"charge_state":{"battery_level":62,"battery_range":202,"timestamp":\(chargeTime)},"drive_state":{"timestamp":\(now)}}
        """
        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(roster.utf8))
            case "/VIN-1/state": (200, Data(state.utf8))
            default: throw FleetKitError.badResponse
            }
        }) { requests in
            let info = try #require(try await GetVehicleInfoIntent(topics: [.battery, .range]).perform().value)
            #expect(info.batteryPercent == 62)
            #expect(info.updatedAt == Date(timeIntervalSince1970: Double(chargeTime) / 1_000))
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles", "/VIN-1/state"])
        }
    }

    @Test(arguments: [[], [.tirePressure], [.climate]] as [[VehicleInfoTopic]])
    func dedicatedTiresAreRequestedOnlyForTiresOrFullStatus(topics: [VehicleInfoTopic]) async throws {
        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/tire_pressure": (200, Data(#"{"front_left":40.5}"#.utf8))
            case "/VIN-1/state": (200, Data(#"{"climate_state":{"inside_temp":20},"gui_settings":{"gui_temperature_units":"C"}}"#.utf8))
            default: throw FleetKitError.badResponse
            }
        }) { requests in
            let info = try #require(try await GetVehicleInfoIntent(topics: topics).perform().value)
            var expectedPaths = ["/vehicles", "/VIN-1/state"]
            if topics.isEmpty || topics.contains(.tirePressure) {
                expectedPaths.append("/VIN-1/tire_pressure")
                #expect(info.frontLeftTirePSI == 40.5)
            }
            #expect(info.insideTemp == 20)
            #expect(requests().compactMap { $0.url?.path }.sorted() == expectedPaths.sorted())
        }
    }
}
