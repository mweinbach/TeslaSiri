import AppIntents
import Foundation
import Testing
@testable import FleetKit

/// Coverage for what Siri hears when a request fails in transit, and for reaching drives
/// beyond the newest page of history.
struct FleetSiriToolReliabilityTests {
    private static func siriMessage(_ error: any Error) -> String? {
        (error as? any CustomLocalizedStringResourceConvertible).map { String(localized: $0.localizedStringResource) }
    }

    // MARK: - Errors Siri can read

    @Test(arguments: [
        (URLError.Code.timedOut, "Your vehicle provider didn't respond in time. Try again in a moment."),
        (.notConnectedToInternet, "This device appears to be offline. Check the internet connection and try again."),
        (.cannotFindHost, "Couldn't reach your vehicle provider. Try again in a moment.")
    ])
    func `transport failures leave an intent with a message Siri can read`(code: URLError.Code, expected: String) {
        let log = FleetIntentLog(GetVehicleInfoIntent.self)
        #expect(Self.siriMessage(log.failure(URLError(code))) == expected)
    }

    @Test func `undecodable responses read as an unexpected response`() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))
        #expect(Self.siriMessage(FleetKitError.readableBySiri(decoding)) == "Your vehicle provider returned an unexpected response.")
    }

    @Test func `cancellation and errors that already carry a message pass through unchanged`() {
        #expect(FleetKitError.readableBySiri(CancellationError()) is CancellationError)
        #expect((FleetKitError.readableBySiri(URLError(.cancelled)) as? URLError)?.code == .cancelled)
        #expect(Self.siriMessage(FleetKitError.readableBySiri(FleetKitError.api("The vehicle is offline."))) == "The vehicle is offline.")
    }

    @Test func `a command that times out says the request could not be confirmed`() async throws {
        try await withIsolatedFleetService(responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            if request.httpMethod == "POST" { throw URLError(.timedOut) }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { requests in
            let intent = SendNavigationIntent()
            intent.destination = "1 Infinite Loop, Cupertino"
            do {
                _ = try await intent.perform()
                Issue.record("Expected the timed-out command to throw.")
            } catch {
                #expect(Self.siriMessage(error) == "Roadrunner didn't respond in time, so the request couldn't be confirmed. Check the car before trying again.")
            }
            #expect(requests().filter { $0.httpMethod == "POST" }.count == 1)
        }
    }

    @Test func `a partial failure summary ends with a single period`() {
        let outcome = CarControlRunOutcome(
            accepted: [CarControlStep("auto_conditioning_start", "climate on")],
            failure: .init(step: CarControlStep("set_temps", "72°F"), error: FleetKitError.api("Tessie did not accept the vehicle command.")),
            notSent: []
        )
        #expect(outcome.partialFailureSummary(vehicleName: "Roadrunner") == "Roadrunner accepted: climate on. I couldn't confirm 72°F: Tessie did not accept the vehicle command.")
    }

    // MARK: - Location stays behind authentication

    @Test func `only Locate Car returns where the car is`() async throws {
        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles": (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state": (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            case "/VIN-1/tire_pressure": (200, Data(FleetKitFixtures.tessieTiresJSON.utf8))
            default: (404, Data())
            }
        }) { requests in
            // These two run from the Lock Screen, so they drop the position the car reported.
            let info = try #require(try await GetVehicleInfoIntent(topics: [.battery, .security]).perform().value)
            #expect(info.batteryPercent == 82)
            #expect(info.latitude == nil && info.longitude == nil && info.locationAddress == nil)
            let status = try #require(try await GetVehicleStatusIntent().perform().value)
            #expect(status.isLocked == true)
            #expect(status.latitude == nil && status.longitude == nil && status.locationAddress == nil)

            let tireReads = requests().filter { $0.url?.path == "/VIN-1/tire_pressure" }.count
            let located = try #require(try await LocateCarIntent().perform().value)
            #expect(located.latitude == 37.3317 && located.longitude == -122.0301)
            #expect(located.spokenAnswer(for: [], includingLocation: true).contains("Roadrunner is parked at the location shown in the Wattie app."))
            // Locating the car reads its state once and skips the tire request.
            #expect(requests().filter { $0.url?.path == "/VIN-1/tire_pressure" }.count == tireReads)
        }
    }

    // MARK: - Control Car settings summary

    @Test func `control car settings describe the requested changes`() {
        let changes = CarControlSettings()
        changes.targetTemperature = 72
        changes.locked = true
        #expect(String(localized: changes.displayRepresentation.title) == "climate on, 72°F, and lock doors")
        #expect(String(localized: CarControlSettings().displayRepresentation.title) == "Car Control Settings")
    }

    // MARK: - Drive history beyond the newest page

    private static let newestStart = Int(Date.now.timeIntervalSince1970) - 3_600
    private static let oldestStartOnFirstPage = newestStart - 99 * 3_600

    /// `count` Tessie drive rows, newest first: ids count down from `firstID` and each drive
    /// starts an hour before the one above it.
    private static func drivesPage(firstID: Int, count: Int, newestStart: Int, destination: String) -> Data {
        let rows = (0..<count).map { offset -> String in
            let start = newestStart - offset * 3_600
            return """
            {"id":\(firstID - offset),"started_at":\(start),"ended_at":\(start + 600),"ending_location":"\(destination)","odometer_distance":3.0}
            """
        }
        return Data("{\"results\":[\(rows.joined(separator: ","))]}".utf8)
    }

    /// Serves a full first page (ids 1000…901) and, for a request bounded by `to`, a short
    /// second page (ids 900…861) of drives that ended at Lake Tahoe.
    private static func pagedHistoryRouter(_ request: URLRequest) throws -> (Int, Data) {
        guard let url = request.url else { return (404, Data()) }
        switch url.path {
        case "/vehicles":
            return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
        case "/VIN-1/drives":
            if queryValue("to", in: request) == nil {
                return (200, drivesPage(firstID: 1_000, count: 100, newestStart: newestStart, destination: "Corner Grocery"))
            }
            return (200, drivesPage(firstID: 900, count: 40, newestStart: oldestStartOnFirstPage - 3_600, destination: "Lake Tahoe"))
        default:
            return (404, Data())
        }
    }

    private static func queryValue(_ name: String, in request: URLRequest) -> String? {
        request.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    private static func driveRequests(_ requests: [URLRequest]) -> [URLRequest] {
        requests.filter { $0.url?.path == "/VIN-1/drives" }
    }

    @Test func `a saved drive older than the newest page still resolves`() async throws {
        try await withIsolatedFleetService(responder: Self.pagedHistoryRouter) { requests in
            let matches = try await DriveEntityQuery().entities(for: ["VIN-1:880"])
            #expect(matches.map(\.id) == ["VIN-1:880"])
            #expect(matches.first?.vehicleName == "Roadrunner")

            let pages = Self.driveRequests(requests())
            #expect(pages.count == 2)
            #expect(Self.queryValue("limit", in: pages[1]) == "100")
            #expect(Self.queryValue("to", in: pages[1]) == String(Self.oldestStartOnFirstPage - 1))
        }
    }

    @Test func `a saved drive on the newest page takes one request`() async throws {
        try await withIsolatedFleetService(responder: Self.pagedHistoryRouter) { requests in
            let matches = try await DriveEntityQuery().entities(for: ["VIN-1:1000"])
            #expect(matches.map(\.id) == ["VIN-1:1000"])
            #expect(Self.driveRequests(requests()).count == 1)
        }
    }

    @Test func `finding drives by place searches past the newest page`() async throws {
        try await withIsolatedFleetService(responder: Self.pagedHistoryRouter) { requests in
            let intent = FindDrivesIntent()
            intent.filter = DriveFilterCriteria(endLocationQuery: "tahoe", maximumResults: 1)
            let found = try #require(try await intent.perform().value)
            #expect(found.map(\.id) == ["VIN-1:900"])
            #expect(found.first?.vehicleName == "Roadrunner")
            #expect(Self.driveRequests(requests()).count == 2)
        }
    }

    @Test func `listing recent drives takes one request`() async throws {
        try await withIsolatedFleetService(responder: Self.pagedHistoryRouter) { requests in
            let intent = FindDrivesIntent()
            intent.filter = DriveFilterCriteria(maximumResults: 3)
            let recent = try #require(try await intent.perform().value)
            #expect(recent.map(\.id) == ["VIN-1:1000", "VIN-1:999", "VIN-1:998"])
            #expect(Self.driveRequests(requests()).count == 1)
        }
    }

    @Test func `driving stats count every drive in a busy period`() async throws {
        try await withIsolatedFleetService(responder: Self.pagedHistoryRouter) { _ in
            let intent = GetDrivingStatsIntent()
            intent.period = .last30Days
            let stats = try #require(try await intent.perform().value)
            #expect(stats.driveCount == 140)
            #expect(stats.totalDistanceMiles == 420)
        }
    }

    @Test func `a strict history read rejects a malformed row on any page`() async throws {
        try await withIsolatedFleetService(responder: { request in
            guard request.url?.path == "/VIN-1/drives", Self.queryValue("to", in: request) != nil else {
                return try Self.pagedHistoryRouter(request)
            }
            return (200, Data(#"{"results":[{"id":900,"started_at":5},{"started_at":4}]}"#.utf8))
        }) { _ in
            let service = FleetIntentService.make()
            await #expect(throws: FleetKitError.self) {
                try await service.driveHistory(vin: "VIN-1", requireCompleteRows: true)
            }
            // The read the Spotlight indexer falls back to keeps every row it can decode.
            let decodable = try await service.driveHistory(vin: "VIN-1")
            #expect(decodable.count == 101)
        }
    }

    // MARK: - The status card and location

    @MainActor
    @Test func `the status card shows where the car is only when its presenter asks`() {
        // What `VehicleStatusEntityQuery` returns when the system fetches a card's status again:
        // it carries the car's position whatever the presenting intent left out.
        let refetched = VehicleStatusEntity(
            snapshot: FleetSnapshotInfo(vin: "VIN-1", locked: true, latitude: 37.3317, longitude: -122.0301),
            vehicleName: "Roadrunner"
        )
        #expect(refetched.latitude != nil)
        #expect(!VehicleStatusSnippetView(status: refetched).hasLocationCard)
        #expect(VehicleStatusSnippetView(status: refetched, showsLocation: true).hasLocationCard)

        #expect(!VehicleStatusSnippetIntent().showsLocation)
        #expect(!VehicleStatusSnippetIntent(status: refetched, topics: [.battery]).showsLocation)
        #expect(VehicleStatusSnippetIntent(status: refetched, topics: [.security], showsLocation: true).showsLocation)
    }

    // MARK: - States with a fixed set of values

    @Test func `charging state is a known case and keeps the car's wording for display`() {
        func status(_ reported: String?) -> VehicleStatusEntity {
            VehicleStatusEntity(snapshot: FleetSnapshotInfo(vin: "VIN-1", chargingState: reported), vehicleName: "Roadrunner")
        }
        let known: [(String, VehicleChargingState)] = [
            ("Charging", .charging), ("Starting", .starting), ("Complete", .complete),
            ("Stopped", .stopped), ("NoPower", .noPower), ("Disconnected", .disconnected)
        ]
        for (reported, expected) in known {
            #expect(status(reported).chargingState == expected)
        }
        #expect(status("NoPower").chargingStateLabel == "No Power")
        #expect(status("NoPower").spokenAnswer(for: [.charging]).contains("It's plugged in but not charging."))

        // A state the app has no case for is still shown and spoken in the car's words.
        let unknown = status("Calibrating")
        #expect(unknown.chargingState == nil)
        #expect(unknown.chargingStateLabel == "Calibrating")
        #expect(unknown.statusSummary.contains("Calibrating"))
        #expect(unknown.spokenAnswer(for: [.charging]).contains("Charging state: Calibrating."))

        #expect(status(nil).chargingState == nil)
        #expect(status(nil).chargingStateLabel == nil)
    }

    @Test func `software update status is a known case and keeps the car's wording for search`() {
        func update(_ status: String?) -> SoftwareUpdateEntity {
            SoftwareUpdateEntity(
                info: FleetSoftwareInfo(
                    currentVersion: "2026.2.1", availableVersion: "2026.8.4", updateAvailable: true,
                    installable: status == "available", status: status,
                    downloadPercent: nil, installPercent: nil, expectedDurationMinutes: nil
                ),
                vin: "VIN-1",
                vehicleName: "Roadrunner"
            )
        }
        #expect(update("available").status == .available)
        #expect(update("Scheduled").status == .scheduled)
        #expect(update("downloading").status == .downloading)
        #expect(update("downloading_wifi_wait").status == .waitingForWiFi)
        #expect(update("downloading_wifi_wait").detailText == "Waiting for Wi-Fi")
        #expect(update("installing").spokenStatus == "Software update 2026.8.4 is installing on Roadrunner.")

        let unknown = update("downloaded")
        #expect(unknown.status == nil)
        #expect(unknown.reportedStatus == "downloaded")
        #expect(unknown.detailText == "Downloaded")
        #expect(unknown.spokenStatus == "Software update 2026.8.4 is available for Roadrunner.")
        #expect(update(nil).status == nil)
    }

    // MARK: - Generable values

    @Test func `only values a Siri tool takes are generable`() {
        #expect((CarControlSettings() as Any) is any GenerableEntity)
        #expect((DriveFilterCriteria() as Any) is any GenerableEntity)
        // Only the Configure Tesla Cabin Climate shortcut action takes this one.
        #expect(!((CabinClimateSettings() as Any) is any GenerableEntity))
    }
}
