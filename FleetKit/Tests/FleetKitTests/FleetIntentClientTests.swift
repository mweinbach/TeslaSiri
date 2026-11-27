import Foundation
import Testing
@testable import FleetKit

// Serialized: every test routes through the shared MockURLProtocol responder,
// so parallel execution would cross-wire fixtures between tests.
@Suite(.serialized)
struct FleetIntentClientTests {
    @Test func `vehicles request uses Tessie bearer token and active query`() async throws {
        let client = makeMockClient { request in
            #expect(request.url?.path == "/vehicles")
            #expect(request.url?.query?.contains("only_active=true") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
        }

        let vehicles = try await client.vehicles()

        #expect(vehicles.map(\.vin) == ["VIN-1", "VIN-2"])
        #expect(vehicles[1].name == "Blue Y")
        #expect(MockURLProtocol.requests.count == 1)
    }

    @Test func `snapshot maps Tessie state and optional tire pressure`() async throws {
        let client = makeMockClient { request in
            switch request.url?.path(percentEncoded: true) {
            case "/VIN%2FABC%20123/state":
                return (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            case "/VIN%2FABC%20123/tire_pressure":
                #expect(request.url?.query?.contains("pressure_format=psi") == true)
                return (200, Data(FleetKitFixtures.tessieTiresJSON.utf8))
            default:
                Issue.record("Unexpected path: \(request.url?.absoluteString ?? "nil")")
                return (404, Data())
            }
        }

        let snapshot = try await client.snapshot(vin: "VIN/ABC 123")

        #expect(MockURLProtocol.requests.compactMap { $0.url?.path(percentEncoded: true) }.sorted() == [
            "/VIN%2FABC%20123/state",
            "/VIN%2FABC%20123/tire_pressure"
        ])
        #expect(snapshot.vin == "VIN/ABC 123")
        #expect(snapshot.batteryLevel == 82.4)
        #expect(abs((snapshot.insideTemp ?? 0) - 68.9) < 0.001)
        #expect(snapshot.outsideTemp == 50)
        #expect(snapshot.petModeOn == true)
        #expect(abs((snapshot.tires?.frontLeftPSI ?? 0) - 39.4) < 0.001)
    }

    @Test func rosterDecodesOnlyVehicleIdentityAndAccountUnits() async throws {
        let json = """
            {"results":[
              {"vin":"A","last_state":{"display_name":42,"vehicle_state":{"vehicle_name":"ignored"},
                "vehicle_config":{"car_type":"modely","exterior_color":true},
                "gui_settings":{"gui_temperature_units":"F","gui_distance_units":"km"},
                "unknown":{"telemetry":[0,1,null]}}},
              {"vin":"B","last_state":{"vehicle_state":{"vehicle_name":"Fallback"},"vehicle_config":false}},
              {"vin":"C","last_state":null}
            ]}
            """
        let client = makeMockClient { _ in (200, Data(json.utf8)) }
        let vehicles = try await client.vehicles()
        #expect(vehicles.map(\.vin) == ["A", "B", "C"])
        #expect(vehicles.map(\.displayName) == ["42", "Fallback", nil])
        #expect(vehicles.map(\.carType) == ["modely", nil, nil])
        #expect(vehicles.map(\.exteriorColor) == ["true", nil, nil])
        #expect(try await client.user().units == "imperial")
    }

    @Test func drivePathPreservesScalarCoercionsAndSampledEndpoints() async throws {
        let json = """
            {"results":[
              {"latitude":"3","longitude":-3,"autopilot":true,"timestamp":1710000002000},
              {"latitude":0,"longitude":"-1","heading":"340","speed":"12.5","timestamp":"1710000000",
               "extra":{"payload":[true,false,null]}},
              {"latitude":2,"longitude":-2,"timestamp":1710000001,"autopilot":2},
              {"latitude":"NaN","longitude":-9}, {"latitude":[],"longitude":1}
            ]}
            """
        let client = makeMockClient { _ in (200, Data(json.utf8)) }
        let start = Date(timeIntervalSince1970: 1710000000)
        let end = start.addingTimeInterval(3)
        let full = try await client.drivePath(vin: "A", from: start, to: end, maxPoints: 1)
        #expect(full.map(\.latitude) == [0, 2, 3])
        #expect(full.map(\.timestampMS) == [1710000000000, 1710000001000, 1710000002000])
        #expect(full.map(\.autopilotState) == [nil, "2", "true"])
        #expect(full.first?.speedMPH == 12.5 && full.first?.heading == 340)
        let sampled = try await client.drivePath(vin: "A", from: start, to: end, maxPoints: 2)
        #expect(sampled == [full[0], full[2]])
    }

    @Test func snapshotPreservesRequiredStateErrorWhenBothReadsFail() async {
        let client = makeMockClient { request in
            request.url?.lastPathComponent == "state"
                ? (503, Data(#"{"error":"state unavailable"}"#.utf8))
                : (401, Data())
        }
        let error = await #expect(throws: FleetKitError.self) {
            try await client.snapshot(vin: "A")
        }
        #expect(error?.localizedDescription == "state unavailable")
    }

    @Test func routeImageIdentityIncludesGeometryAndVisibleAutopilotSegments() {
        let a = FleetDriveRoutePoint(latitude: 1, longitude: 2)
        func key(_ b: FleetDriveRoutePoint, width: Double = 380) -> SiriMapImageKey {
            .route(driveID: "A:1", style: .standard, size: CGSize(width: width, height: 172),
                   points: [a, b].map(SiriMapImageKey.Point.init))
        }
        let original = key(a)
        #expect(key(FleetDriveRoutePoint(latitude: 1, longitude: 3)) != original)
        #expect(key(FleetDriveRoutePoint(latitude: 1, longitude: 2, autopilotState: "FSD")) != original)
        #expect(key(a, width: 380.5) != original)
        #expect(key(FleetDriveRoutePoint(latitude: 1, longitude: 2, speedMPH: 50)) == original)
    }

    @Test func spotlightStatusAndSoftwareUseOneStateResponse() async throws {
        let client = makeMockClient { request in
            if request.url?.path == "/VIN-1/state" {
                return (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            }
            return (200, Data(FleetKitFixtures.tessieTiresJSON.utf8))
        }
        let result = try await FleetIntentService(client: client).snapshotAndSoftware(vin: "VIN-1")
        #expect(result.snapshot.batteryLevel == 82.4)
        #expect(result.software.availableVersion == "2026.8.4")
        // The request log is shared across this suite, and an earlier test's cancelled read
        // can still land in it, so count only this car's requests.
        let paths = MockURLProtocol.requests.compactMap { $0.url?.path }.filter { $0.hasPrefix("/VIN-1/") }
        #expect(paths.sorted() == ["/VIN-1/state", "/VIN-1/tire_pressure"])
    }

    @Test(arguments: [200, 401, 503])
    func batteryHealthPreservesPartialDataAndAuthenticationErrors(batteryStatus: Int) async throws {
        try await withIsolatedFleetService { request in
            if request.url?.path == "/battery_health" {
                return (200, Data(#"{"results":[{"vin":"VIN-1","health_percent":94}]}"#.utf8))
            }
            return (batteryStatus, Data(#"{"energy_remaining":42}"#.utf8))
        } body: { requests in
            let service = FleetIntentService.make()
            if batteryStatus == 401 {
                let error = await #expect(throws: FleetKitError.self) {
                    try await service.batteryHealth(vin: "VIN-1")
                }
                #expect(error?.localizedDescription == FleetKitError.sessionExpired.localizedDescription)
            } else {
                let health = try await service.batteryHealth(vin: "VIN-1")
                #expect(health.healthPercent == 94)
                #expect(health.energyRemainingKWH == (batteryStatus == 200 ? 42 : nil))
            }
            #expect(requests().compactMap { $0.url?.path }.sorted() == ["/VIN-1/battery", "/battery_health"])
        }
    }

    @Test func `control request maps action and parameters to Tessie command`() async throws {
        let client = makeMockClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/VIN-1/command/set_charge_limit")
            #expect(request.url?.query?.contains("percent=80") == true)
            #expect(request.httpBody == nil)
            return (200, FleetKitFixtures.commandResponse())
        }

        try await client.runControl(
            action: "set_charge_limit",
            vin: "VIN-1",
            params: ["percent": .int(80)]
        )
    }

    @Test func `parameterless controls map to direct Tessie commands`() async throws {
        let client = makeMockClient { request in
            #expect(request.url?.path == "/VIN-1/command/honk")
            #expect(request.url?.query == nil)
            return (200, FleetKitFixtures.commandResponse())
        }

        try await client.runControl(action: "honk_horn", vin: "VIN-1", params: [:])
    }

    @Test func `401 responses surface session expired`() async throws {
        let client = makeMockClient { _ in
            (401, Data("{\"error\":\"invalid token\"}".utf8))
        }

        let error = await #expect(throws: FleetKitError.self) {
            try await client.user()
        }
        #expect(error?.localizedDescription == FleetKitError.sessionExpired.localizedDescription)
    }

    @Test func `Tessie errors surface API message`() async throws {
        let client = makeMockClient { _ in
            (400, Data("{\"error\":\"not ready\"}".utf8))
        }

        let error = await #expect(throws: FleetKitError.self) {
            try await client.cancelSoftwareUpdate(vin: "VIN-1")
        }
        #expect(error?.localizedDescription == "not ready")
    }

    @Test func `software state maps Tessie version and progress`() async throws {
        let client = makeMockClient { request in
            #expect(request.url?.path == "/VIN-1/state")
            return (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
        }

        let software = try await client.software(vin: "VIN-1")

        #expect(software.currentVersion == "2026.2.1")
        #expect(software.availableVersion == "2026.8.4")
        #expect(software.updateAvailable)
        #expect(software.expectedDurationMinutes == 25)
    }

    @Test func `snapshot falls back to state tire pressures in bar`() async throws {
        let client = makeMockClient { request in
            switch request.url?.path {
            case "/VIN-1/state":
                return (200, Data("""
                    {"vehicle_state":{"tpms_pressure_fl":"2.7","tpms_pressure_fr":"NaN","tpms_pressure_rr":2.9}}
                    """.utf8))
            case "/VIN-1/tire_pressure":
                return (404, Data())
            default:
                Issue.record("Unexpected request")
                return (404, Data())
            }
        }

        let snapshot = try await client.snapshot(vin: "VIN-1")
        let tires = try #require(snapshot.tires)
        #expect(abs((tires.frontLeftPSI ?? 0) - 39.16) < 0.01)
        #expect(abs((tires.rearRightPSI ?? 0) - 42.06) < 0.01)
        #expect(tires.frontRightPSI == nil)
        #expect(tires.lastMeasuredAt == nil)
    }

    @Test func `snapshot reports an expired session from the tire pressure request`() async throws {
        let client = makeMockClient { request in
            if request.url?.path == "/VIN-1/state" {
                return (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            }
            #expect(request.url?.path == "/VIN-1/tire_pressure")
            return (401, Data())
        }

        let error = await #expect(throws: FleetKitError.self) {
            try await client.snapshot(vin: "VIN-1")
        }
        #expect(error?.localizedDescription == FleetKitError.sessionExpired.localizedDescription)
    }

    @Test func `drives requests a miles based limit and returns newest sessions first`() async throws {
        let client = makeMockClient { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/VIN-1/drives")
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
            #expect(query?.contains(URLQueryItem(name: "distance_format", value: "mi")) == true)
            #expect(query?.contains(URLQueryItem(name: "limit", value: "10")) == true)
            return (200, Data("""
                {"results":[
                    {"id":1,"started_at":1710000000,"ended_at":1710000600},
                    {"id":2,"started_at":1710001200,"ended_at":1710001500,"odometer_distance":12.5,
                     "average_speed":30,"max_speed":60,"energy_used":4.2}
                ]}
                """.utf8))
        }

        let drives = try await client.drives(vin: "VIN-1", limit: 10)
        #expect(drives.map(\.sessionID) == ["VIN-1:2", "VIN-1:1"])
        let latest = try #require(drives.first)
        #expect(latest.startedAt == 1_710_001_200_000)
        #expect(latest.durationMS == 300_000)
        #expect(latest.distanceMiles == 12.5)
        #expect(latest.avgSpeedMPH == 30)
        #expect(latest.energyUsedKWH == 4.2)
    }

    @Test(.serialized, arguments: ["2026.8.4", ""])
    func `release note suggestions use staged or installed software version`(stagedVersion: String) async throws {
        let expectedVersion = stagedVersion.isEmpty ? "2026.2.1" : stagedVersion
        let client = makeMockClient { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state":
                return (200, Data("""
                    {"vehicle_state":{"car_version":"2026.2.1 build","software_update":{"version":"\(stagedVersion)"}}}
                    """.utf8))
            case "/VIN-1/release_notes/\(expectedVersion)":
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
                return (200, Data("""
                    {"release_notes":[{"title":"Route updates","subtitle":null,"description":"Better directions",
                                       "customer_version":"\(expectedVersion)"}]}
                    """.utf8))
            default:
                Issue.record("Unexpected request")
                return (404, Data())
            }
        }
        let query = ReleaseNoteEntityQuery(service: FleetIntentService(client: client))

        let notes = try await query.suggestedEntities()
        let note = try #require(notes.first)
        #expect(notes.count == 1)
        #expect(note.version == expectedVersion)
        #expect(note.title == "Route updates")
        #expect(note.details == "Better directions")
    }

    @Test func `saved release notes resolve by exact version for authorized vehicles`() async throws {
        let client = makeMockClient { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-2/release_notes/2025.44":
                return (200, Data("""
                    {"release_notes":[
                        {"title":"Changes: Navigation","customer_version":"2025.44"},
                        {"title":"Changes: Navigation","customer_version":"2025.40"}
                    ]}
                    """.utf8))
            default:
                Issue.record("Unexpected request")
                return (404, Data())
            }
        }
        let query = ReleaseNoteEntityQuery(service: FleetIntentService(client: client))
        let id = "VIN-2:2025.44:2025.40:Changes: Navigation"

        let notes = try await query.entities(for: [id, "UNKNOWN:2025.44:Missing"])
        #expect(notes.map(\.id) == [id])
        #expect(MockURLProtocol.requests.map { $0.url?.path } == ["/vehicles", "/VIN-2/release_notes/2025.44"])
    }

    @Test(.serialized, arguments: ["", ".", ".."])
    func `release notes rejects empty and dot segment versions`(invalidVersion: String) async {
        let client = makeMockClient { request in
            Issue.record("Unexpected request: \(request.url?.absoluteString ?? "nil")")
            return (500, Data())
        }

        await #expect(throws: FleetKitError.self) {
            _ = try await client.releaseNotes(vin: "VIN-1", version: invalidVersion)
        }
        #expect(MockURLProtocol.requests.isEmpty)
    }
}
