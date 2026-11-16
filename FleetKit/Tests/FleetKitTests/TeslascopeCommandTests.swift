import Foundation
import Testing
@testable import FleetKit

struct TeslascopeCommandTests {
    private let vin = "5YJ3E1EA7KF000001"
    private let acknowledged = Data(#"{"code":200,"response":"Command accepted by vehicle."}"#.utf8)

    private func rosterOrCommand(
        _ request: URLRequest,
        command: (URLRequest) throws -> (Int, Data)
    ) throws -> (Int, Data) {
        switch request.url?.path {
        case "/api/account/tesla-accounts":
            return (200, Data(#"{"code":200,"response":[{"id":1}]}"#.utf8))
        case "/api/account/tesla-account/1/vehicles":
            let json = #"{"code":200,"response":[{"public_id":"example-car","vin":"\#(vin)","name":"My car"}]}"#
            return (200, Data(json.utf8))
        default:
            return try command(request)
        }
    }

    @Test func mapsActionsToPublicIDAndTypedBodies() async throws {
        try await withTeslascopeFixture(responder: { request in
            try rosterOrCommand(request) { request in
                #expect(request.url?.host == "teslascope.com")
                #expect(request.httpMethod == "POST")
                #expect(request.url?.query == nil)
                let data = try requestBodyData(request)
                switch request.url?.path {
                case "/api/vehicle/example-car/command/setChargeLimit":
                    #expect(try JSONDecoder().decode([String: Int].self, from: data) == ["limit": 80])
                case "/api/vehicle/example-car/command/setTemps":
                    #expect(try JSONDecoder().decode([String: Double].self, from: data) == ["driver": 21.5, "passenger": 22])
                case "/api/vehicle/example-car/command/setSeatHeater":
                    #expect(try JSONDecoder().decode([String: Int].self, from: data) == ["seat": 4, "level": 2])
                case "/api/vehicle/example-car/command/stopDogMode", "/api/vehicle/example-car/command/scheduleSoftwareUpdate",
                     "/api/vehicle/example-car/command/closeTrunk", "/api/vehicle/example-car/command/openTrunk":
                    #expect(data.isEmpty)
                default:
                    Issue.record("Unexpected command \(request.url?.path ?? "")")
                }
                return (200, acknowledged)
            }
        }) { client, requests in
            try await client.runControl(action: "set_charge_limit", vin: vin, params: ["percent": .int(80)])
            try await client.runControl(action: "set_temps", vin: vin, params: [
                "driver_temp": .double(21.5), "passenger_temp": .int(22)
            ])
            try await client.runControl(action: "set_seat_heat", vin: vin, params: ["seat": .string("rear_center"), "level": .int(2)])
            try await client.runControl(action: "set_pet_mode", vin: vin, params: ["on": .bool(false)])
            try await client.installSoftwareUpdate(vin: vin, offsetSec: 0)
            try await client.runControl(action: "actuate_trunk", vin: vin, params: ["which_trunk": .string("rear")])
            try await client.runControl(action: "actuate_trunk", vin: vin, params: ["which_trunk": .string("rear"), "command": .string("close")])
            #expect(requests().filter { $0.httpMethod == "POST" }.count == 7)
            #expect(requests().suffix(2).compactMap(\.url?.lastPathComponent) == ["openTrunk", "closeTrunk"])
        }
    }

    @Test func linkedAccountPermissionsAreAppliedToTheTargetCar() async throws {
        let chargeVIN = "5YJ3E1EA7KF000002"
        try await withTeslascopeFixture(responder: { request in
            switch request.url?.path {
            case "/api/account/tesla-accounts":
                return (200, Data("""
                {"code":200,"response":[
                  {"id":1,"scope_vehicle_cmds":true,"scope_vehicle_charging_cmds":false},
                  {"id":2,"scope_vehicle_cmds":false,"scope_vehicle_charging_cmds":true}
                ]}
                """.utf8))
            case "/api/account/tesla-account/2/vehicles":
                return (200, Data(#"{"code":200,"response":[{"public_id":"charging-car","vin":"\#(chargeVIN)"}]}"#.utf8))
            default:
                return try rosterOrCommand(request) { _ in (200, acknowledged) }
            }
        }) { client, requests in
            let cars = try await client.vehicles()
            let generalCar = try #require(cars.first { $0.vin == vin })
            let chargeCar = try #require(cars.first { $0.vin == chargeVIN })
            let general = TeslascopeClient.controlActions(for: generalCar)
            let charging = TeslascopeClient.controlActions(for: chargeCar)
            #expect(general.supports("honk_horn"))
            #expect(general.chargeActions.isEmpty)
            #expect(!general.supports("charge_port_door_open"))
            #expect(general.schemas["set_charge_limit"] == nil)
            #expect(charging.supports("charge_port_door_open"))
            #expect(!charging.supports("door_lock"))
            #expect(charging.schemas["navigation_request"] == nil)

            await #expect(throws: FleetKitError.self) {
                try await client.runControl(action: "charge_start", vin: vin, params: [:])
            }
            await #expect(throws: FleetKitError.self) {
                try await client.runControl(action: "door_lock", vin: chargeVIN, params: [:])
            }
            await #expect(throws: FleetKitError.self) {
                try await client.installSoftwareUpdate(vin: chargeVIN, offsetSec: 0)
            }
            try await client.runControl(action: "charge_start", vin: chargeVIN, params: [:])
            try await client.runControl(action: "door_lock", vin: vin, params: [:])
            try await client.installSoftwareUpdate(vin: vin, offsetSec: 0)
            #expect(requests().filter { $0.httpMethod == "POST" }.compactMap(\.url?.path) == [
                "/api/vehicle/charging-car/command/startCharging",
                "/api/vehicle/example-car/command/lock",
                "/api/vehicle/example-car/command/scheduleSoftwareUpdate"
            ])
        }
    }

    @Test func rejectsUnsupportedOperationsBeforeSending() async throws {
        for unsupported in ["set_charging_amps", "set_seat_cool", "steering_wheel_heater", "set_bioweapon_mode"] {
            #expect(!TeslascopeClient.controlActions.supports(unsupported))
        }
        try await withTeslascopeFixture(responder: { _ in
            Issue.record("An unsupported or invalid operation reached the network.")
            throw FleetKitError.badResponse
        }) { client, requests in
            await #expect(throws: FleetKitError.self) {
                try await client.runControl(action: "set_seat_cool", vin: vin, params: [:])
            }
            await #expect(throws: FleetKitError.self) {
                try await client.runControl(action: "actuate_trunk", vin: vin, params: ["which_trunk": .string("unknown")])
            }
            await #expect(throws: FleetKitError.self) {
                try await client.installSoftwareUpdate(vin: vin, offsetSec: 600)
            }
            await #expect(throws: FleetKitError.self) {
                try await client.runControl(action: "actuate_trunk", vin: vin, params: ["which_trunk": .string("front"), "command": .string("close")])
            }
            #expect(requests().isEmpty)
        }
    }

    @Test(arguments: [
        #"{"code":200,"response":""}"#,
        #"{"code":403,"response":"Premium membership required."}"#,
        #"{"code":200,"response":{"result":false,"reason":"unavailable"}}"#,
        #"{"response":"No result code."}"#
    ])
    func requiresCommandAcknowledgement(_ reply: String) async throws {
        try await withTeslascopeFixture(responder: { request in
            try rosterOrCommand(request) { _ in (200, Data(reply.utf8)) }
        }) { client, requests in
            await #expect(throws: FleetKitError.self) {
                try await client.runControl(action: "honk_horn", vin: vin, params: [:])
            }
            #expect(requests().filter { $0.httpMethod == "POST" }.count == 1)
        }
    }
}
