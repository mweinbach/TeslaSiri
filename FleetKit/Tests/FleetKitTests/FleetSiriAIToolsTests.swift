import AppIntents
import Foundation
import Testing
@testable import FleetKit

final class SiriToolMockURLProtocol: URLProtocol {
    static let headerName = "X-Siri-Test-ID"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: (URLRequest) throws -> (Int, Data)] = [:]
    nonisolated(unsafe) private static var recordedRequests: [String: [URLRequest]] = [:]

    static func register(
        id: String,
        responder: @escaping (URLRequest) throws -> (Int, Data)
    ) {
        lock.lock()
        defer { lock.unlock() }
        handlers[id] = responder
        recordedRequests[id] = []
    }

    static func requests(for id: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests[id] ?? []
    }

    static func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: id)
        recordedRequests.removeValue(forKey: id)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: headerName) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.headerName) else {
            client?.urlProtocol(self, didFailWithError: FleetKitError.badResponse)
            return
        }

        Self.lock.lock()
        Self.recordedRequests[id, default: []].append(request)
        let handler = Self.handlers[id]
        Self.lock.unlock()

        do {
            guard let handler, let url = request.url else {
                throw FleetKitError.badResponse
            }
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func withIsolatedFleetService<R>(
    selectedVIN: String? = "VIN-1",
    provider: FleetProvider = .tessie,
    responder: @escaping (URLRequest) throws -> (Int, Data),
    body: (_ requests: () -> [URLRequest]) async throws -> R
) async throws -> R {
    let testID = UUID().uuidString
    SiriToolMockURLProtocol.register(id: testID, responder: responder)
    defer { SiriToolMockURLProtocol.unregister(id: testID) }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SiriToolMockURLProtocol.self]
    config.httpAdditionalHeaders = [SiriToolMockURLProtocol.headerName: testID]
    let session = URLSession(configuration: config)

    let suiteName = "FleetSiriAITests.\(testID)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let tokens = FleetSharedTokenStore(appGroup: suiteName, readAccessToken: { provider in
        provider == .teslascope ? "scope-test-token" : "test-token"
    })
    tokens.selectProvider(provider)
    if let selectedVIN { tokens.save(selectedVIN: selectedVIN) }

    let client = FleetIntentClient(session: session, tokenStore: tokens)
    let service = FleetIntentService(client: client)

    return try await FleetIntentService.$testingOverride.withValue(service) {
        try await body {
            SiriToolMockURLProtocol.requests(for: testID)
        }
    }
}

struct FleetSiriAIToolsTests {
    @Test func vehicleOptionsAndControlShareOneVerifiedRoster() async throws {
        try await withIsolatedFleetService { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        } body: { requests in
            let service = FleetIntentService.make()
            async let lookup = service.vehicles()
            async let selected = service.resolvedVehicle("VIN-1")
            _ = try await (lookup, selected)
            _ = try await SelectedVehicleOptionsProvider().results()
            _ = try await LockVehicleIntent().perform()
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles", "/VIN-1/command/lock"])
        }
    }

    @Test func teslascopeRoutesReadsAndWritesUsingItsOwnTokenAndVerifiedPublicID() async throws {
        let vin = "5YJ3E1EA7KF000001"
        try await withIsolatedFleetService(selectedVIN: vin, provider: .teslascope) { request in
            #expect(request.url?.host == "teslascope.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer scope-test-token")
            switch request.url?.path {
            case "/api/account/tesla-accounts":
                return (200, Data(#"{"code":200,"response":[{"id":1,"scope_vehicle_cmds":true,"scope_vehicle_charging_cmds":false}]}"#.utf8))
            case "/api/account/tesla-account/1/vehicles":
                return (200, Data(#"{"code":200,"response":[{"public_id":"blue","vin":"5YJ3E1EA7KF000001","name":"Blue"}]}"#.utf8))
            case "/api/vehicle/blue/detailed":
                return (200, Data(#"{"code":200,"response":{"public_id":"blue","vin":"5YJ3E1EA7KF000001","charge_state":{"battery_level":64},"vehicle_state":{"fd_window":0,"fp_window":0,"rd_window":0,"rp_window":0}}}"#.utf8))
            case "/api/vehicle/blue/command/lock":
                return (200, Data(#"{"code":200,"response":"The vehicle has been locked."}"#.utf8))
            default:
                Issue.record("Unexpected request \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (404, Data())
            }
        } body: { requests in
            let service = FleetIntentService.make()
            let car = try #require(try await VehicleEntityQuery().allEntities().first)
            #expect(car.id == vin)
            #expect(car.controls?.joined().contains("Start or stop charging") == false)
            let available = try await service.controlActions()
            #expect(available.supports("door_lock"))
            #expect(!available.supports("charge_start"))
            let combined = ControlCarIntent()
            let changes = CarControlSettings()
            changes.climateOn = true
            changes.charging = true
            combined.changes = changes
            await #expect(throws: FleetKitError.self) { _ = try await combined.perform() }
            #expect(!requests().contains { $0.httpMethod == "POST" })
            let snapshot = try await service.snapshot(vin: vin)
            #expect(snapshot.batteryLevel == 64)
            #expect(snapshot.openClosures == nil)
            #expect(try await LockVehicleIntent().perform().value?.succeeded == true)
            let coolSeat = SetSeatClimateIntent(seat: .driver, level: 3, mode: .cool)
            await #expect(throws: FleetKitError.self) { _ = try await coolSeat.perform() }
            let wheel = SetSteeringWheelHeaterIntent()
            wheel.on = true
            await #expect(throws: FleetKitError.self) { _ = try await wheel.perform() }

            FleetSharedTokenStore(appGroup: service.appGroupIdentifier).selectProvider(.tessie)
            #expect(service.sessionScopeID == nil)
            await #expect(throws: FleetKitError.self) { _ = try await service.snapshot(vin: vin) }
            await #expect(throws: FleetKitError.self) {
                try await service.runControl(action: "door_lock", vin: vin, humanName: "locking")
            }
            #expect(requests().filter { $0.httpMethod == "POST" }.map { $0.url?.path } == ["/api/vehicle/blue/command/lock"])
        }
    }

    @Test func unknownExplicitVehicleRefreshesAndNeverControlsFallback() async throws {
        try await withIsolatedFleetService { _ in
            (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
        } body: { requests in
            let service = FleetIntentService.make()
            _ = try await service.vehicles()
            await #expect(throws: FleetKitError.self) {
                try await service.runControl(action: "door_lock", vin: "REMOVED", humanName: "locking")
            }
            #expect(requests().compactMap { $0.url?.path } == ["/vehicles", "/vehicles"])
        }
    }

    @Test func rosterExpiryAndScopeChangesRequireFreshLoads() async throws {
        let car = FleetVehicleInfo(vin: "FIRST", displayName: "First")
        let next = FleetVehicleInfo(vin: "SECOND", displayName: "Second")
        let expired = FleetRosterCache(lifetime: .zero)
        _ = try await expired.load(scope: "A", requiring: nil) { .init(vehicles: [car], units: nil) }
        let refreshed = try await expired.load(scope: "A", requiring: nil) { .init(vehicles: [next], units: nil) }
        #expect(refreshed.vehicles.map(\.vin) == ["SECOND"])

        let cache = FleetRosterCache()
        _ = try await cache.load(scope: "A", requiring: nil) { .init(vehicles: [car], units: nil) }
        let secondAccount = try await cache.load(scope: "B", requiring: nil) { .init(vehicles: [next], units: nil) }
        #expect(secondAccount.vehicles.map(\.vin) == ["SECOND"])
        #expect(await cache.cachedVehicle(vin: "FIRST", scope: "A") == nil)
    }

    @Test func anOutstandingOldRosterCannotRepopulateTheCacheAfterAccountSwitch() async throws {
        let cache = FleetRosterCache()
        let (started, start) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        let old = Task {
            try await cache.load(scope: "A", requiring: nil) {
                start.yield()
                start.finish()
                for await _ in released { break }
                return .init(vehicles: [FleetVehicleInfo(vin: "OLD", displayName: nil)], units: nil)
            }
        }
        for await _ in started { break }
        let current = try await cache.load(scope: "B", requiring: nil) {
            .init(vehicles: [FleetVehicleInfo(vin: "NEW", displayName: nil)], units: nil)
        }
        release.yield()
        release.finish()
        #expect(current.vehicles.map(\.vin) == ["NEW"])
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(await cache.cachedVehicle(vin: "NEW", scope: "B")?.vin == "NEW")
    }

    @Test func authorizationFailureInvalidatesTheVerifiedRoster() async throws {
        try await withIsolatedFleetService { request in
            if request.url?.path == "/vehicles" { return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8)) }
            return (401, Data())
        } body: { requests in
            let service = FleetIntentService.make()
            let originalScope = service.sessionScopeID
            _ = try await service.vehicles()
            await #expect(throws: FleetKitError.self) {
                try await service.runControl(action: "door_lock", vin: "VIN-1", humanName: "locking")
            }
            #expect(service.sessionScopeID != originalScope)
            await #expect(throws: FleetKitError.self) { try await service.vehicles() }
            #expect(requests().count == 2)
        }
    }

    @Test func changingModeAfterResolutionCancelsTheWrite() async throws {
        try await withIsolatedFleetService { _ in
            (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
        } body: { requests in
            let service = FleetIntentService.make()
            let group = service.appGroupIdentifier
            let sandbox = FleetSandboxStore(appGroup: group)
            sandbox.setMode(.demoVehicle)
            let isolated = FleetIntentService(sandbox: sandbox)
            let vehicle = try await isolated.resolvedVehicle(nil)
            let scope = isolated.sessionScopeID
            sandbox.setMode(.dryRun)
            sandbox.setMode(.demoVehicle)
            #expect(isolated.sessionScopeID != scope)
            await #expect(throws: FleetKitError.self) {
                try await isolated.runControl(action: "door_lock", vin: vehicle.vin, humanName: "locking")
            }
            #expect(requests().isEmpty)
            #expect(sandbox.commandLog().isEmpty)
        }
    }

    @Test func `warm up and send a destination execute together for the selected vehicle`() async throws {
        try await withIsolatedFleetService(responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { requests in
            let climate = try #require(try await StartClimateIntent().perform().value)
            let navigation = SendNavigationIntent()
            navigation.destination = "Yuki Kitchen, Westport"
            let destination = try #require(try await navigation.perform().value)

            #expect(climate.succeeded)
            #expect(destination.succeeded)
            #expect(climate.vin == destination.vin)
            #expect(destination.appliedValue == "Yuki Kitchen, Westport")

            let commands = requests().filter { $0.httpMethod == "POST" }
            #expect(commands.compactMap { $0.url?.path } == [
                "/VIN-1/command/start_climate",
                "/VIN-1/command/share"
            ])
            let navigationURL = try #require(commands.last?.url)
            let query = URLComponents(url: navigationURL, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first { $0.name == "value" }?.value == "Yuki Kitchen, Westport")
        }
    }

    @Test func `climate authentication failure keeps its Siri readable recovery message`() async throws {
        try await withIsolatedFleetService(responder: { _ in
            (401, Data())
        }) { requests in
            do {
                _ = try await StartClimateIntent().perform()
                Issue.record("Expected an expired-session error.")
            } catch let error as FleetKitError {
                let siriError: any CustomLocalizedStringResourceConvertible = error
                #expect(String(localized: siriError.localizedStringResource) == "Your vehicle provider access token is invalid or revoked. Open Wattie to replace it.")
            }
            #expect(!requests().contains { $0.httpMethod == "POST" })
        }
    }

    @Test func `new Siri AI workflow tools default to no explicit vehicle`() {
        #expect(StartChargingIntent().vehicle == nil)
        #expect(StopChargingIntent().vehicle == nil)
        #expect(SetChargePortIntent().vehicle == nil)
        #expect(SetSentryModeIntent().vehicle == nil)
        #expect(ConfigureCabinClimateIntent().vehicle == nil)
        #expect(FindDrivesIntent().vehicle == nil)
        #expect(GetReleaseNotesIntent().vehicle == nil)
        #expect(CloseWindowsIntent().vehicle == nil)
    }

    @Test func `snapshot decodes range charger power charge port sentry and target temperature`() async throws {
        let richStateJSON = """
        {
          "display_name": "Roadrunner",
          "drive_state": {"latitude": 37.3317, "longitude": -122.0301, "speed": 0, "timestamp": 1710000000000},
          "charge_state": {
            "battery_level": 78,
            "battery_range": 246.5,
            "charge_limit_soc": 80,
            "charging_state": "Charging",
            "charger_power": 11.4,
            "charge_port_door_open": true,
            "charge_rate": 44.0,
            "time_to_full_charge": 0.35,
            "timestamp": 1710000000000
          },
          "climate_state": {
            "inside_temp": 21.0,
            "outside_temp": 12.0,
            "driver_temp_setting": 20.0,
            "is_climate_on": true,
            "climate_keeper_mode": "off",
            "defrost_mode": 0,
            "timestamp": 1710000000000
          },
          "vehicle_state": {
            "locked": true,
            "sentry_mode": true,
            "odometer": 15420.2,
            "car_version": "2026.8.4",
            "timestamp": 1710000000000
          },
          "gui_settings": {"gui_distance_units": "mi/hr", "gui_temperature_units": "F"}
        }
        """

        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state":
                return (200, Data(richStateJSON.utf8))
            case "/VIN-1/tire_pressure":
                return (200, Data(FleetKitFixtures.tessieTiresJSON.utf8))
            default:
                return (404, Data())
            }
        }) { _ in
            let output = try await GetVehicleStatusIntent().perform()
            let entity = try #require(output.value)
            #expect(entity.vehicleName == "Roadrunner")
            #expect(entity.batteryPercent == 78)
            #expect(entity.batteryRangeMiles == 246.5)
            #expect(entity.chargeLimitPercent == 80)
            #expect(entity.chargerPowerKW == 11.4)
            #expect(entity.chargePortDoorOpen == true)
            #expect(entity.isLocked == true)
            #expect(entity.sentryModeOn == true)
            #expect(entity.isClimateOn == true)
            #expect(entity.targetTemp == 68.0)
            #expect(entity.tireSummary?.contains("39") == true)
        }
    }

    @Test func `charging charge port sentry and close windows commands map to Tessie endpoints`() async throws {
        try await withIsolatedFleetService(responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { requests in
            let lockResult = try #require(try await LockVehicleIntent().perform().value)
            #expect(lockResult.action == "door_lock")
            #expect(lockResult.succeeded == true)
            #expect(lockResult.vin == "VIN-1")
            #expect(lockResult.vehicleName == "Roadrunner")

            let chargeResult = try #require(try await StartChargingIntent().perform().value)
            #expect(chargeResult.action == "charge_start")

            let closePort = SetChargePortIntent()
            closePort.action = .close
            let portResult = try #require(try await closePort.perform().value)
            #expect(portResult.action == "charge_port_door_close")
            #expect(portResult.appliedValue == "close")

            let enableSentry = SetSentryModeIntent()
            enableSentry.on = true
            let sentryResult = try #require(try await enableSentry.perform().value)
            #expect(sentryResult.action == "set_sentry_mode")
            #expect(sentryResult.appliedValue == "on")

            let service = try #require(FleetIntentService.testingOverride)
            try await service.runControl(action: "charge_stop", vin: "VIN-1", humanName: "stopping charging")
            try await service.runControl(action: "charge_port_door_open", vin: "VIN-1", humanName: "opening charge port")
            try await service.runControl(
                action: "set_sentry_mode",
                vin: "VIN-1",
                params: ["on": .bool(false)],
                humanName: "disabling Sentry Mode"
            )
            try await service.runControl(
                action: "window_control",
                vin: "VIN-1",
                params: ["command": .string("close")],
                humanName: "closing windows"
            )

            let paths = requests().compactMap { $0.url?.path }
            #expect(paths.contains("/VIN-1/command/lock"))
            #expect(paths.contains("/VIN-1/command/start_charging"))
            #expect(paths.contains("/VIN-1/command/close_charge_port"))
            #expect(paths.contains("/VIN-1/command/enable_sentry"))
            #expect(paths.contains("/VIN-1/command/stop_charging"))
            #expect(paths.contains("/VIN-1/command/open_charge_port"))
            #expect(paths.contains("/VIN-1/command/disable_sentry"))
            #expect(paths.contains("/VIN-1/command/close_windows"))
        }
    }

    @Test func `ConfigureCabinClimateIntent orchestrates generable CabinClimateSettings in one call`() async throws {
        try await withIsolatedFleetService(responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { requests in
            let intent = ConfigureCabinClimateIntent()
            intent.settings = CabinClimateSettings(
                targetTemperatureCelsius: 21.26,
                enableMaxDefrost: true,
                enablePetMode: true,
                enableBioweaponDefenseMode: true
            )

            let output = try await intent.perform()
            let value = try #require(output.value)
            #expect(value.action == "configure_cabin_climate")
            #expect(value.succeeded == true)
            #expect(value.appliedValue?.contains("21.5°C") == true)
            #expect(value.appliedValue?.contains("max defrost on") == true)
            #expect(value.appliedValue?.contains("Dog Mode on") == true)
            #expect(value.appliedValue?.contains("Bioweapon Defense on") == true)

            let commandURLs = requests().compactMap { $0.url?.absoluteString }
            #expect(commandURLs.contains { $0.contains("/VIN-1/command/start_climate") })
            #expect(commandURLs.contains { $0.contains("/VIN-1/command/set_temperatures") && $0.contains("temperature=21.5") })
            #expect(commandURLs.contains { $0.contains("/VIN-1/command/start_max_defrost") })
            #expect(commandURLs.contains { $0.contains("/VIN-1/command/set_climate_keeper_mode") && $0.contains("mode=2") })
            #expect(commandURLs.contains { $0.contains("/VIN-1/command/set_bioweapon_mode") })
        }
    }

    @Test func `FindDrivesIntent filters drives with generable DriveFilterCriteria`() async throws {
        let drivesJSON = """
        {
          "results": [
            {
              "id": 101,
              "started_at": 1710000000,
              "ended_at": 1710001800,
              "starting_location": "Home Garage, San Jose",
              "ending_location": "SFO International Airport",
              "odometer_distance": 34.8,
              "average_speed": 58.0,
              "max_speed": 72.0,
              "energy_used": 9.1
            },
            {
              "id": 102,
              "started_at": 1710010000,
              "ended_at": 1710010600,
              "starting_location": "Home Garage, San Jose",
              "ending_location": "Corner Grocery",
              "odometer_distance": 2.1,
              "average_speed": 22.0,
              "max_speed": 35.0,
              "energy_used": 0.5
            }
          ]
        }
        """

        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/drives":
                return (200, Data(drivesJSON.utf8))
            default:
                return (404, Data())
            }
        }) { _ in
            let intent = FindDrivesIntent()
            intent.filter = DriveFilterCriteria(
                locationQuery: "airport",
                minimumDistanceMiles: 10.0,
                maximumResults: 5
            )
            let matches = try #require(try await intent.perform().value)
            #expect(matches.count == 1)
            #expect(matches.first?.endAddress == "SFO International Airport")
            #expect(matches.first?.distanceMiles == 34.8)

            intent.filter = DriveFilterCriteria(maximumResults: 1)
            let latest = try #require(try await intent.perform().value)
            #expect(latest.map(\.id) == ["VIN-1:102"])

            intent.filter = DriveFilterCriteria(minimumDurationMinutes: 11, sortBy: .longestDuration, maximumResults: 1)
            let longer = try #require(try await intent.perform().value)
            #expect(longer.map(\.id) == ["VIN-1:101"])
        }
    }

    @Test func `GetReleaseNotesIntent resolves pending software version when version is omitted`() async throws {
        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state":
                return (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            case "/VIN-1/release_notes/2026.8.4":
                let notesJSON = """
                {
                  "release_notes": [
                    {
                      "title": "Adaptive High Beams",
                      "subtitle": "Vision",
                      "description": "Curves light around oncoming traffic.",
                      "customer_version": "2026.8.4"
                    }
                  ]
                }
                """
                return (200, Data(notesJSON.utf8))
            default:
                return (404, Data())
            }
        }) { _ in
            let notes = try #require(try await GetReleaseNotesIntent().perform().value)
            #expect(notes.count == 1)
            #expect(notes.first?.title == "Adaptive High Beams")
            #expect(notes.first?.version == "2026.8.4")
            #expect(notes.first?.details == "Curves light around oncoming traffic.")
        }
    }

    @Test func `GetReleaseNotesIntent filters by featureQuery strips markup and produces spoken digest`() async throws {
        let notesJSON = """
        {
          "release_notes": [
            {
              "title": "Full Self-Driving (Supervised)",
              "subtitle": "v14.2",
              "description": "<p>**Smoother** highway merges and lane changes.</p>\\n* Improved parking lot routing.",
              "customer_version": "2026.8.4"
            },
            {
              "title": "Dashcam Viewer",
              "subtitle": "Security",
              "description": "Scrub through Sentry clips faster.",
              "customer_version": "2026.8.4"
            }
          ]
        }
        """

        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state":
                return (200, Data(FleetKitFixtures.tessieStateJSON.utf8))
            case "/VIN-1/release_notes/2026.8.4":
                return (200, Data(notesJSON.utf8))
            default:
                return (404, Data())
            }
        }) { _ in
            let allNotes = try #require(try await GetReleaseNotesIntent().perform().value)
            #expect(allNotes.count == 2)
            #expect(allNotes.first?.subtitle == "v14.2")
            #expect(allNotes.first?.details?.contains("<p>") == false)
            #expect(allNotes.first?.details?.contains("**") == false)

            let digest = ReleaseNoteEntity.spokenDigest(
                for: allNotes,
                version: "2026.8.4",
                vehicleName: "Roadrunner"
            )
            #expect(digest.contains("Full Self-Driving (Supervised) (v14.2)"))
            #expect(digest.contains("Dashcam Viewer (Security)"))

            let filteredIntent = GetReleaseNotesIntent()
            filteredIntent.featureQuery = "dashcam"
            let filtered = try #require(try await filteredIntent.perform().value)
            #expect(filtered.count == 1)
            #expect(filtered.first?.title == "Dashcam Viewer")

            let queryMatches = try await ReleaseNoteEntityQuery().entities(matching: "Self-Driving")
            #expect(queryMatches.count == 1)
            #expect(queryMatches.first?.title == "Full Self-Driving (Supervised)")
        }
    }

    @Test func `FindDrivesIntent advanced filters sorting DriveEntityQuery and GetDriveDetailsIntent`() async throws {
        let nowSec = Int64(Date.now.timeIntervalSince1970)
        let richDrivesJSON = """
        {
          "results": [
            {
              "id": 201,
              "started_at": \(nowSec - 7_200),
              "ended_at": \(nowSec - 3_600),
              "starting_location": "Palo Alto, CA",
              "ending_location": "Truckee, CA",
              "starting_battery": 88,
              "ending_battery": 32,
              "odometer_distance": 185.0,
              "autopilot_distance": 162.5,
              "rated_range_used": 195.0,
              "average_speed": 61.5,
              "max_speed": 76.0,
              "average_inside_temperature": 69.5,
              "average_outside_temperature": 48.0,
              "energy_used": 51.8,
              "tag": "Road Trip"
            },
            {
              "id": 202,
              "started_at": \(nowSec - 1_800),
              "ended_at": \(nowSec - 600),
              "starting_location": "Truckee, CA",
              "ending_location": "Tahoe City, CA",
              "starting_battery": 78,
              "ending_battery": 73,
              "odometer_distance": 14.5,
              "autopilot_distance": 8.0,
              "average_speed": 43.5,
              "max_speed": 55.0,
              "energy_used": 3.4,
              "tag": "Personal"
            }
          ]
        }
        """

        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/drives":
                return (200, Data(richDrivesJSON.utf8))
            default:
                return (404, Data())
            }
        }) { requests in
            let findLongest = FindDrivesIntent()
            findLongest.filter = DriveFilterCriteria(
                endLocationQuery: "truckee",
                tagQuery: "Road Trip",
                minimumDurationMinutes: 45,
                sortBy: .longestDistance,
                maximumResults: 5
            )
            let matches = try #require(try await findLongest.perform().value)
            #expect(matches.count == 1)
            let trip = try #require(matches.first)
            #expect(trip.id == "VIN-1:201")
            #expect(trip.startingBatteryPercent == 88)
            #expect(trip.endingBatteryPercent == 32)
            #expect(trip.batteryUsedPercent == 56)
            #expect(trip.autopilotDistanceMiles == 162.5)
            #expect(trip.tag == "Road Trip")
            #expect((trip.efficiencyWhPerMile ?? 0) > 279 && (trip.efficiencyWhPerMile ?? 0) < 281)

            // Inspect that specific DriveEntity via GetDriveDetailsIntent
            let detailsIntent = GetDriveDetailsIntent()
            detailsIntent.drive = trip
            let inspected = try #require(try await detailsIntent.perform().value)
            #expect(inspected.id == "VIN-1:201")
            let spoken = inspected.spokenSummary(vehicleName: "Roadrunner")
            #expect(spoken.contains("Palo Alto, CA to Truckee, CA"))
            #expect(spoken.contains("88% to 32%"))
            #expect(spoken.contains("162.5 miles on Autopilot"))
            #expect(spoken.contains("Road Trip"))

            // Fallback to latest drive when drive parameter is nil
            let latestInspected = try #require(try await GetDriveDetailsIntent().perform().value)
            #expect(latestInspected.id == "VIN-1:202")

            // String query matching on DriveEntityQuery
            let stringMatches = try await DriveEntityQuery().entities(matching: "Tahoe City")
            #expect(stringMatches.map(\.id) == ["VIN-1:202"])

            let driveURLs = requests().compactMap { $0.url?.absoluteString }
            #expect(driveURLs.contains { $0.contains("temperature_format=f") })
        }
    }

    @Test func `GetDrivingStatsIntent GetChargingStatsIntent GetRecentChargesIntent and GetBatteryHealthIntent aggregate stats`() async throws {
        let nowSec = Int64(Date.now.timeIntervalSince1970)
        let drivesJSON = """
        {
          "results": [
            {
              "id": 301,
              "started_at": \(nowSec - 3_600),
              "ended_at": \(nowSec - 1_800),
              "starting_location": "Home",
              "ending_location": "Office",
              "odometer_distance": 20.0,
              "autopilot_distance": 15.0,
              "average_speed": 40.0,
              "max_speed": 65.0,
              "energy_used": 5.0
            }
          ]
        }
        """
        let consumptionJSON = """
        {
          "last_charge_at": \(nowSec - 10_000),
          "distance_driven": 20.0,
          "battery_percent_used": 8.0,
          "battery_percent_used_by_driving": 6.5,
          "rated_range_used": 24.0,
          "rated_range_used_by_driving": 20.0,
          "energy_used": 6.2,
          "energy_used_by_driving": 5.0
        }
        """
        let chargesJSON = """
        {
          "results": [
            {
              "id": 401,
              "started_at": \(nowSec - 20_000),
              "ended_at": \(nowSec - 18_200),
              "location": "Kettleman City Supercharger",
              "is_supercharger": true,
              "energy_added": 48.5,
              "miles_added": 192.0,
              "starting_battery": 15,
              "ending_battery": 80,
              "cost": 18.43
            },
            {
              "id": 402,
              "started_at": \(nowSec - 80_000),
              "ended_at": \(nowSec - 65_000),
              "location": "Home Wall Connector",
              "is_supercharger": false,
              "energy_added": 22.0,
              "miles_added": 88.0,
              "starting_battery": 50,
              "ending_battery": 80,
              "cost": 5.50
            }
          ]
        }
        """
        let batteryHealthJSON = """
        {
          "results": [
            {
              "vin": "VIN-1",
              "odometer": 18420.5,
              "max_range": 308.0,
              "max_ideal_range": 315.0,
              "capacity": 76.4,
              "original_capacity": 80.0,
              "degradation_percent": 4.5,
              "health_percent": 95.5
            }
          ]
        }
        """
        let batteryPackJSON = """
        {
          "timestamp": \(nowSec),
          "battery_level": 72,
          "energy_remaining": 55.0,
          "lifetime_energy_used": 5420.0,
          "phantom_drain_percent": 0.8,
          "pack_voltage": 388.4,
          "pack_current": -1.2,
          "module_temp_min": 20.0,
          "module_temp_max": 25.0
        }
        """

        try await withIsolatedFleetService(responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/drives":
                return (200, Data(drivesJSON.utf8))
            case "/VIN-1/consumption_since_charge":
                return (200, Data(consumptionJSON.utf8))
            case "/VIN-1/charges":
                return (200, Data(chargesJSON.utf8))
            case "/battery_health":
                return (200, Data(batteryHealthJSON.utf8))
            case "/VIN-1/battery":
                return (200, Data(batteryPackJSON.utf8))
            default:
                return (404, Data())
            }
        }) { _ in
            // 1. Driving stats since last charge
            let drivingIntent = GetDrivingStatsIntent()
            drivingIntent.period = .sinceLastCharge
            let drivingStats = try #require(try await drivingIntent.perform().value)
            #expect(drivingStats.driveCount == 1)
            #expect(drivingStats.totalDistanceMiles == 20.0)
            #expect(drivingStats.totalEnergyUsedKWH == 5.0)
            #expect(drivingStats.averageEfficiencyWhPerMile == 250.0)
            #expect(drivingStats.milesPerKWH == 4.0)
            #expect(drivingStats.autopilotDistanceMiles == 15.0)
            #expect(drivingStats.autopilotSharePercent == 75.0)
            #expect(abs((drivingStats.idleEnergySinceChargeKWH ?? 0) - 1.2) < 0.01)

            // 2. Charging stats over last 30 days
            let chargingIntent = GetChargingStatsIntent()
            chargingIntent.period = .last30Days
            let chargingStats = try #require(try await chargingIntent.perform().value)
            #expect(chargingStats.sessionCount == 2)
            #expect(chargingStats.superchargerCount == 1)
            #expect(chargingStats.acSessionCount == 1)
            #expect(abs(chargingStats.totalEnergyAddedKWH - 70.5) < 0.01)
            let chargingCost = try #require(chargingStats.totalCost)
            #expect(abs(chargingCost - 23.93) < 0.01)

            // 3. Filtered recent Supercharger sessions
            let recentChargesIntent = GetRecentChargesIntent()
            recentChargesIntent.superchargersOnly = true
            let scSessions = try #require(try await recentChargesIntent.perform().value)
            #expect(scSessions.count == 1)
            #expect(scSessions.first?.location == "Kettleman City Supercharger")

            // 4. Battery health & pack stats
            let batteryStats = try #require(try await GetBatteryHealthIntent().perform().value)
            #expect(batteryStats.healthPercent == 95.5)
            #expect(batteryStats.degradationPercent == 4.5)
            #expect(batteryStats.usableCapacityKWH == 76.4)
            #expect(batteryStats.originalCapacityKWH == 80.0)
            #expect(batteryStats.maxRangeMiles == 308.0)
            #expect(batteryStats.energyRemainingKWH == 55.0)
            #expect(batteryStats.lifetimeEnergyUsedKWH == 5420.0)
            #expect(batteryStats.phantomDrainPercent == 0.8)
            #expect(batteryStats.moduleTempMinF == 68.0)
            #expect(batteryStats.moduleTempMaxF == 77.0)
            #expect(batteryStats.spokenSummary.contains("95.5%"))
        }
    }
}
