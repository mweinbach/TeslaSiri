import Foundation
import Testing
@testable import FleetKit

func withTeslascopeFixture<R>(
    responder: @escaping (URLRequest) throws -> (Int, Data),
    body: (TeslascopeClient, () -> [URLRequest]) async throws -> R
) async throws -> R {
    let id = UUID().uuidString
    SiriToolMockURLProtocol.register(id: id, responder: responder)
    defer { SiriToolMockURLProtocol.unregister(id: id) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SiriToolMockURLProtocol.self]
    configuration.httpAdditionalHeaders = [SiriToolMockURLProtocol.headerName: id]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    return try await body(TeslascopeClient(session: session, token: "teslascope-fixture")) {
        SiriToolMockURLProtocol.requests(for: id)
    }
}

struct TeslascopeVehicleTests {
    private static let vin = "5YJ3E1EA7KF000001"
    private static let secondVIN = "5YJ3E1EA7KF000002"
    private static let accounts = "/api/account/tesla-accounts"
    private static let vehicles = "/api/account/tesla-account/1/vehicles"
    private static let detail = "/api/vehicle/blue/detailed"

    private static func envelope(_ response: String) -> Data {
        Data("{\"code\":200,\"response\":\(response)}".utf8)
    }

    @Test(arguments: [false, true])
    func rosterAndDetailUseDifferentIdentifiersAndNormalizeWireValues(wrapped: Bool) async throws {
        try await withTeslascopeFixture { request in
            #expect(request.url?.host == "teslascope.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer teslascope-fixture")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            switch request.url?.path {
            case Self.accounts: return (200, Self.envelope(#"[{"id":1}]"#))
            case Self.vehicles:
                return (200, Self.envelope("""
                [{"vin":"\(Self.vin)","public_id":"blue","name":"Demo","vehicle_config":{"car_type":"model3","can_actuate_trunks":1}}]
                """))
            case Self.detail:
                let detail = """
                {"public_id":"blue","vin":"\(Self.vin)","name":"Demo",
                 "charge_state":{"battery_level":45,"battery_range":"124.44","updated_at":"2024-01-01T00:00:00.250000Z"},
                 "climate_state":{"inside_temp":"13.50","updated_at":"2023-12-31T23:59:01Z"},
                 "vehicle_state":{"tpms_pressure_fl":"2.875","locked":1,"car_version":"2026.20.1 abc",
                   "software_update_status":"available","software_update_version":"2026.20.2",
                   "software_update_expected_duration":2700,"updated_at":"2024-01-01T00:00:00Z"}}
                """
                return (200, wrapped ? Self.envelope(detail) : Data(detail.utf8))
            default: throw FleetKitError.badResponse
            }
        } body: { client, requests in
            let vehicles = try await client.vehicles()
            #expect(vehicles.map(\.vin) == [Self.vin])
            #expect(vehicles.first?.canActuateTrunks == true)
            let state = try await client.stateData(vin: Self.vin)
            let (snapshot, software) = try FleetIntentClient.spotlightState(state, tires: nil, vin: Self.vin)
            #expect(snapshot.batteryLevel == 45 && snapshot.batteryRangeMiles == 124.44)
            #expect(snapshot.updatedAt == 1_704_067_200_250)
            #expect(snapshot.insideTemp == (TeslascopeClient.displayUnits == "imperial" ? 56.3 : 13.5))
            let pressure = try #require(snapshot.tires?.frontLeftPSI)
            #expect(abs(pressure - 41.7) < 0.1)
            #expect(snapshot.locked == true)
            #expect(software.currentVersion == "2026.20.1" && software.availableVersion == "2026.20.2")
            #expect(software.expectedDurationMinutes == 45)
            #expect(requests().compactMap(\.url?.path) == [Self.accounts, Self.vehicles, Self.detail])
        }
    }

    @Test(arguments: [false, true])
    func multipleAccountsResolveVINFromOwnedDetailWhenAbsentFromList(wrapped: Bool) async throws {
        try await withTeslascopeFixture { request in
            switch request.url?.path {
            case Self.accounts: return (200, Self.envelope(#"[{"id":1,"scope_vehicle_cmds":true,"scope_vehicle_charging_cmds":false},{"id":2,"scope_vehicle_cmds":false},{"id":3,"enabled":false}]"#))
            case Self.vehicles: return (200, Self.envelope(#"[{"public_id":"blue"}]"#))
            case Self.detail:
                let detail = """
                {"public_id":"blue","vin":"\(Self.vin)","name":"Blue","vehicle_config":null}
                """
                return (200, wrapped ? Self.envelope(detail) : Data(detail.utf8))
            case "/api/account/tesla-account/2/vehicles":
                return (200, Self.envelope("[{\"public_id\":\"green\",\"vin\":\"\(Self.secondVIN)\",\"name\":\"Green\"}]"))
            default: throw FleetKitError.badResponse
            }
        } body: { client, requests in
            let vehicles = try await client.vehicles()
            let greenID = try await client.publicID(vin: Self.secondVIN)
            #expect(vehicles.map(\.displayName) == ["Blue", "Green"])
            #expect(greenID == "green")
            #expect(vehicles.first?.allowsVehicleCommands == true && vehicles.first?.allowsChargingCommands == false)
            #expect(vehicles.last?.allowsVehicleCommands == false && vehicles.last?.allowsChargingCommands == nil)
            #expect(requests().count == 4)
        }
    }

    @Test(arguments: ["..", "../blue", "%2Fblue", "bad?name", ""])
    func malformedIdentifierCannotLeaveItsResource(_ publicID: String) async throws {
        try await withTeslascopeFixture { request in
            switch request.url?.path {
            case Self.accounts: (200, Self.envelope(#"[{"id":1}]"#))
            case Self.vehicles: (200, Self.envelope("[{\"public_id\":\"\(publicID)\",\"vin\":\"\(Self.vin)\"}]"))
            default: throw FleetKitError.badResponse
            }
        } body: { client, requests in
            await #expect(throws: FleetKitError.self) { try await client.publicID(vin: Self.vin) }
            #expect(requests().count == 2)
        }
    }

    @Test func inconsistentVINsDoNotProduceVehicleState() async throws {
        try await withTeslascopeFixture { request in
            switch request.url?.path {
            case Self.accounts: (200, Self.envelope(#"[{"id":1}]"#))
            case Self.vehicles: (200, Self.envelope("[{\"public_id\":\"blue\",\"vin\":\"\(Self.vin)\"}]"))
            case Self.detail: (200, Self.envelope("{\"public_id\":\"blue\",\"vin\":\"\(Self.secondVIN)\"}"))
            default: throw FleetKitError.badResponse
            }
        } body: { client, _ in
            _ = await #expect(throws: FleetKitError.self) { try await client.stateData(vin: Self.vin) }
        }
    }

    @Test func unsuccessfulEnvelopeIsRejectedEvenWithHTTPSuccess() async throws {
        try await withTeslascopeFixture { _ in
            (200, Data(#"{"code":403,"response":"Insufficient scopes."}"#.utf8))
        } body: { client, requests in
            await #expect(throws: FleetKitError.self) { try await client.vehicles() }
            #expect(requests().count == 1)
        }
    }
}
