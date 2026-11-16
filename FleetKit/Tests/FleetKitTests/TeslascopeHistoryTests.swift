import Foundation
import Testing
@testable import FleetKit

struct TeslascopeHistoryTests {
    private static let vin = "5YJ3E1EA7KF000001"

    private static func fixture<Result>(
        vehicleResponse: @escaping (URLRequest) throws -> String,
        body: (TeslascopeClient, () -> [URLRequest]) async throws -> Result
    ) async throws -> Result {
        try await withTeslascopeFixture(responder: { request in
            let response: String
            switch request.url?.path {
            case "/api/account/tesla-accounts": response = #"[{"id":1}]"#
            case "/api/account/tesla-account/1/vehicles":
                response = #"[{"public_id":"blue","vin":"5YJ3E1EA7KF000001","name":"Blue"}]"#
            default: response = try vehicleResponse(request)
            }
            return (200, Data("{\"code\":200,\"response\":\(response)}".utf8))
        }, body: body)
    }

    @Test func activityUsesNewestFirstFeedAndFollowsPagesOnOriginalHost() async throws {
        try await Self.fixture { request in
            let url = try #require(request.url)
            #expect(url.host == "teslascope.com")
            #expect(url.path == "/api/vehicle/blue/activity")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains(URLQueryItem(name: "limit", value: "20")))
            #expect(query.contains(URLQueryItem(name: "start_at", value: "2024-01-01T00:00:00.000Z")))
            #expect(query.contains(URLQueryItem(name: "end_at", value: "2024-01-08T00:00:00.000Z")))
            if query.contains(URLQueryItem(name: "page", value: "1")) {
                return """
                {"current_page":1,"next_page_url":"https://example.invalid/leak?page=2","data":[
                    {"type":"charge","charge":{"id":22,"created_at":"2024-01-03T00:00:00Z"}},
                    {"type":"drive","drive":{"id":12,"type":"personal","created_at":"2024-01-02T00:00:00Z"}}
                ]}
                """
            }
            return """
            {"current_page":2,"next_page_url":null,"data":[
              {"type":"drive","drive":{"id":11,"type":"business","distance":"4.66","duration":1920,
                "avg_speed":9,"latitude_start":"[redacted]","longitude_start":"-120.5",
                "battery_level_start":49,"battery_level_end":47,"battery_range_start":"145.78","battery_range_end":"139.37",
                "created_at":"2024-01-01T00:00:00.250000Z","updated_at":"2024-08-25T12:00:00Z"}}
            ]}
            """
        } body: { client, requests in
            let start = Date(timeIntervalSince1970: 1_704_067_200)
            let end = start.addingTimeInterval(7 * 86400)
            let drives = try await client.drives(vin: Self.vin, limit: 1, from: start, to: end, tag: "Business")
            let drive = try #require(drives.first)
            #expect(drive.id == "\(Self.vin):teslascope:11")
            #expect(drive.startedAt == 1_704_067_200_250)
            #expect(drive.endedAt == 1_704_069_120_250)
            #expect(drive.distanceMiles == 4.66 && drive.startLatitude == nil && drive.startLongitude == -120.5)
            #expect(drive.batteryUsedPercent == 2 && drive.energyUsedKWH == nil)
            #expect(requests().filter { $0.url?.lastPathComponent == "activity" }.count == 2)
        }
    }

    @Test func detailsMapOnlyAvailableMeasurementsAndKeepRouteEndpoints() async throws {
        try await Self.fixture { request in
            switch request.url?.path {
            case "/api/vehicle/blue/charge/22":
                return """
                {"id":22,"created_at":"2024-01-01T00:00:00Z","updated_at":"2025-03-01T00:00:00Z",
                 "duration":100,"charge_energy_added":"17.69","charge_energy_calculated":"18.4",
                 "cost":"6.12","currency":"EUR","fast_charger_type":"Tesla","name":"Station",
                 "battery_range_start":"42","battery_range_end":"80"}
                """
            case "/api/vehicle/blue/drive/11":
                return """
                {"id":11,"created_at":"2024-01-01T00:00:00Z","progress":[
                  {"created_at":"2024-01-01T00:02:00Z","latitude":"37.2","longitude":"-122","speed":40},
                  {"created_at":"2024-01-01T00:00:00Z","latitude":"37.0","longitude":"-122","odometer":"42.1","speed":0},
                  {"created_at":"2024-01-01T00:01:00Z","latitude":"37.1","longitude":"-122","speed":60,"heading":250},
                  {"created_at":"2024-01-01T00:00:40Z","latitude":"[redacted]","longitude":"[redacted]","battery_level":77}
                ]}
                """
            default: throw FleetKitError.badResponse
            }
        } body: { client, requests in
            let charge = try await client.charge(vin: Self.vin, sessionID: "\(Self.vin):teslascope:22")
            #expect(charge.endedAt == charge.startedAt + 100_000)
            #expect(charge.energyAddedKWH == 17.69 && charge.energyUsedKWH == nil)
            #expect(charge.isSupercharger && charge.cost == 6.12 && charge.currency == "EUR" && charge.milesAdded == 38)
            let id = "\(Self.vin):teslascope:11"
            let samples = try await client.driveTelemetry(vin: Self.vin, sessionID: id)
            #expect(samples.first?.odometerMiles == 42.1 && samples[1].batteryPercent == 77)
            let points = try await client.drivePath(vin: Self.vin, sessionID: id, maxPoints: 2)
            #expect(points.map(\.latitude) == [37, 37.2])
            let count = requests().count
            await #expect(throws: FleetKitError.self) { try await client.drive(vin: Self.vin, sessionID: "\(Self.vin):11") }
            await #expect(throws: FleetKitError.self) { try await client.charge(vin: Self.vin, sessionID: "another:teslascope:22") }
            #expect(requests().count == count)
        }
    }

    @Test func releaseNotesAcceptDocumentedTitlesAndLiveFeatureObjects() async throws {
        try await Self.fixture { request in
            if request.url?.path == "/api/vehicle/blue/detailed" {
                return #"{"vin":"5YJ3E1EA7KF000001","public_id":"blue","vehicle_state":{"car_version":"2026.40 abc"}}"#
            }
            #expect(request.url?.path == "/api/software/2026.39.100")
            return """
            {"version":"2026.39.100","features":["New controls",
              {"title":"Naming Update","subtitle":null,"description":"Updated terminology.","customer_version":"2026.39.99"},
              {"title":"Other cars only","countries":["fi"],"car_types":["model3_TeslaAP4"]}]}
            """
        } body: { client, _ in
            let notes = try await client.releaseNotes(vin: Self.vin, version: "2026.39.100 buildhash")
            #expect(notes.map(\.title) == ["New controls", "Naming Update"])
            #expect(notes.first?.customerVersion == "2026.39.100")
            #expect(notes.last?.customerVersion == "2026.39.99" && notes.last?.details == "Updated terminology.")
        }
    }

    @Test func vehicleNotesSelectTheRequestedInstalledOrStagedVersion() async throws {
        try await Self.fixture { request in
            switch request.url?.path {
            case "/api/vehicle/blue/release-notes":
                return #"{"response":{"deployed_version":"2026.39","release_notes":[{"title":"Installed"}]}}"#
            case "/api/vehicle/blue/staged-release-notes":
                return #"{"staged_version":"2026.40","release_notes":[{"title":"Upcoming"}]}"#
            default: throw FleetKitError.badResponse
            }
        } body: { client, _ in
            let installed = try await client.releaseNotes(vin: Self.vin, version: "2026.39", staged: false)
            let staged = try await client.releaseNotes(vin: Self.vin, version: "2026.40", staged: true)
            #expect(installed.first?.title == "Installed")
            #expect(staged.first?.title == "Upcoming")
        }
    }

    @Test func dateOnlyPathKeepsSamplesInsideTheRequestedDriveWindow() async throws {
        try await Self.fixture { request in
            switch request.url?.path {
            case "/api/vehicle/blue/activity":
                return #"{"current_page":1,"data":[{"type":"drive","drive":{"id":12,"created_at":"2024-01-01T00:00:00Z"}}]}"#
            case "/api/vehicle/blue/drive/12":
                return """
                {"id":12,"progress":[
                   {"latitude":0,"longitude":0,"created_at":"2024-01-01T00:00:00Z"},
                   {"latitude":1,"longitude":1,"created_at":"2024-01-01T00:05:00Z"},
                   {"latitude":2,"longitude":2,"created_at":"2024-01-01T00:20:00Z"}]}
                """
            default: throw FleetKitError.badResponse
            }
        } body: { client, _ in
            let start = Date(timeIntervalSince1970: 1_704_067_200)
            let points = try await client.drivePath(vin: Self.vin, from: start, to: start.addingTimeInterval(300))
            #expect(points.map(\.latitude) == [0, 1])
        }
    }

    @Test func chargingStatsOnlyTotalCompatibleCurrencies() {
        func session(_ id: Int, cost: Double?, currency: String?) -> FleetChargeInfo {
            FleetChargeInfo(
                sessionID: "\(Self.vin):teslascope:\(id)", vin: Self.vin, startedAt: 0, endedAt: nil,
                location: nil, isSupercharger: false, energyAddedKWH: 10, milesAdded: nil,
                startingBatteryPercent: nil, endingBatteryPercent: nil, cost: cost, currency: currency
            )
        }
        let car = FleetVehicleInfo(vin: Self.vin, displayName: "Blue", vehicleTag: nil)
        let euro = session(1, cost: 8, currency: "EUR")
        let dollar = session(2, cost: 5, currency: "USD")
        let mixed = ChargingStatsEntity(vehicle: car, period: .last7Days, sessions: [euro, dollar])
        #expect(mixed.totalCost == nil && mixed.averageCostPerKWH == nil && mixed.formattedCost == nil)
        let same = ChargingStatsEntity(vehicle: car, period: .last7Days, sessions: [euro, session(3, cost: 2, currency: "EUR")])
        #expect(same.totalCost == 10 && same.currency == "EUR" && same.averageCostPerKWH == 0.5)
        #expect(ChargeSessionEntity(info: euro).formattedCost == 8.0.formatted(.currency(code: "EUR")))
        let missing = ChargeSessionEntity(info: session(4, cost: nil, currency: nil))
        #expect(missing.formattedCost == nil)
    }
}
