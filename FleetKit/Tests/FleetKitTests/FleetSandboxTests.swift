import AppIntents
import Foundation
import Synchronization
import Testing
@testable import FleetKit

private final class SandboxMockURLProtocol: URLProtocol {
    static let headerName = "X-Sandbox-Test-ID"
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

func withSandboxTestContext<R>(
    mode: FleetSandboxMode,
    preset: FleetDemoPreset? = nil,
    accessToken: String? = "test-token",
    selectedVIN: String? = "VIN-1",
    responder: @escaping (URLRequest) throws -> (Int, Data) = { _ in (500, Data()) },
    body: (_ sandbox: FleetSandboxStore, _ service: FleetIntentService, _ requests: () -> [URLRequest]) async throws -> R
) async throws -> R {
    let testID = UUID().uuidString
    SandboxMockURLProtocol.register(id: testID, responder: responder)
    defer { SandboxMockURLProtocol.unregister(id: testID) }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SandboxMockURLProtocol.self]
    config.httpAdditionalHeaders = [SandboxMockURLProtocol.headerName: testID]
    let session = URLSession(configuration: config)

    let suiteName = "FleetSandboxTests.\(testID)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    if let accessToken {
        defaults.set(accessToken, forKey: FleetKitConfig.accessTokenDefaultsKey)
    }
    if let selectedVIN {
        defaults.set(selectedVIN, forKey: FleetKitConfig.selectedVINDefaultsKey)
    }

    let sandbox = FleetSandboxStore(appGroup: suiteName)
    if let preset {
        sandbox.applyPreset(preset)
    }
    sandbox.setMode(mode)

    let client = FleetIntentClient(
        session: session,
        tokenStore: FleetSharedTokenStore(appGroup: suiteName)
    )
    let service = FleetIntentService(client: client, sandbox: sandbox)

    return try await FleetIntentService.$testingOverride.withValue(service) {
        try await body(sandbox, service) {
            SandboxMockURLProtocol.requests(for: testID)
        }
    }
}

struct FleetSandboxTests {
    @Test func `SetCabinTemperatureIntent starts climate before setting cabin temperature`() async throws {
        try await withSandboxTestContext(mode: .live, responder: { request in
            if request.url?.path == "/vehicles" {
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            }
            return (200, FleetKitFixtures.commandResponse(result: true))
        }) { sandbox, _, requests in
            let intent = SetCabinTemperatureIntent()
            intent.temperature = Measurement(value: 72, unit: .fahrenheit)
            let result = try #require(try await intent.perform().value)

            #expect(result.action == "set_temps")
            #expect(result.succeeded == true)
            #expect(result.summary.contains("Started climate and set Roadrunner's cabin to"))

            let commandPaths = requests()
                .compactMap { $0.url?.path }
                .filter { $0.contains("/command/") }
            #expect(commandPaths == ["/VIN-1/command/start_climate", "/VIN-1/command/set_temperatures"])
            #expect(sandbox.commandLog().isEmpty)
        }
    }

    @Test func `Dry-Run mode reads live telemetry while blocking and logging write commands`() async throws {
        let stateJSON = """
        {
          "display_name": "Roadrunner",
          "drive_state": {"latitude": 37.3317, "longitude": -122.0301, "speed": 0, "timestamp": 1710000000000},
          "charge_state": {"battery_level": 81, "battery_range": 258.0, "charge_limit_soc": 80, "charging_state": "Stopped", "timestamp": 1710000000000},
          "climate_state": {"inside_temp": 19.0, "outside_temp": 14.0, "driver_temp_setting": 20.0, "is_climate_on": false, "timestamp": 1710000000000},
          "vehicle_state": {"locked": true, "sentry_mode": true, "car_version": "2026.8.4", "timestamp": 1710000000000},
          "gui_settings": {"gui_distance_units": "mi/hr", "gui_temperature_units": "F"}
        }
        """

        try await withSandboxTestContext(mode: .dryRun, responder: { request in
            switch request.url?.path {
            case "/vehicles":
                return (200, Data(FleetKitFixtures.tessieVehiclesJSON.utf8))
            case "/VIN-1/state":
                return (200, Data(stateJSON.utf8))
            case "/VIN-1/tire_pressure":
                return (200, Data(FleetKitFixtures.tessieTiresJSON.utf8))
            default:
                throw FleetKitError.badResponse
            }
        }) { sandbox, _, requests in
            let status = try #require(try await GetVehicleStatusIntent().perform().value)
            #expect(status.vehicleName == "Roadrunner")
            #expect(status.batteryPercent == 81)

            let tempIntent = SetCabinTemperatureIntent()
            tempIntent.temperature = Measurement(value: 70, unit: .fahrenheit)
            let tempResult = try #require(try await tempIntent.perform().value)
            #expect(tempResult.succeeded == true)

            let lockResult = try #require(try await LockVehicleIntent().perform().value)
            #expect(lockResult.succeeded == true)

            let paths = requests().compactMap { $0.url?.path }
            #expect(paths.contains("/VIN-1/state"))
            #expect(paths.allSatisfy { !$0.contains("/command/") })

            let log = sandbox.commandLog()
            #expect(log.count == 3)
            #expect(log.map(\.action) == ["door_lock", "set_temps", "auto_conditioning_start"])
            #expect(log.allSatisfy { $0.mode == .dryRun && $0.source == "Siri" && $0.vehicleName == "Roadrunner" })
        }
    }

    @Test func `Demo Car mode runs without Tessie token and mutates simulated state across Siri tools`() async throws {
        try await withSandboxTestContext(
            mode: .demoVehicle,
            preset: .freezingMorning,
            accessToken: nil,
            selectedVIN: nil,
            responder: { _ in
                throw FleetKitError.badResponse
            }
        ) { sandbox, service, requests in
            let initialStatus = try #require(try await GetVehicleStatusIntent().perform().value)
            #expect(initialStatus.vin == FleetDemoVehicleState.demoVIN)
            #expect(initialStatus.insideTemp == 26.0)
            #expect(initialStatus.outsideTemp == 22.0)
            #expect(initialStatus.isClimateOn == false)
            #expect(initialStatus.frontRightTirePSI == 36.5)
            #expect(initialStatus.tireSummary?.contains("FR 37 PSI") == true)

            let configureIntent = ConfigureCabinClimateIntent()
            configureIntent.settings = CabinClimateSettings(
                targetTemperatureCelsius: 22.0,
                enableMaxDefrost: false,
                driverSeatHeatLevel: 3,
                steeringWheelHeat: true
            )
            let commandResult = try #require(try await configureIntent.perform().value)
            #expect(commandResult.succeeded == true)

            let updatedDemo = sandbox.demoState()
            #expect(updatedDemo.hvacOn == true)
            #expect(updatedDemo.defrostOn == false)
            #expect(updatedDemo.seatHeaterLevels["Driver"] == 3)
            #expect(updatedDemo.steeringWheelHeaterOn == true)
            #expect(abs(updatedDemo.targetTempF - 71.6) < 0.2)

            let refreshedStatus = try #require(try await GetVehicleStatusIntent().perform().value)
            #expect(refreshedStatus.isClimateOn == true)

            try await service.installSoftwareUpdate(vin: FleetDemoVehicleState.demoVIN, offsetSec: 120)
            #expect(sandbox.demoState().softwareStatus == "scheduled")

            try await service.cancelSoftwareUpdate(vin: FleetDemoVehicleState.demoVIN)
            #expect(sandbox.demoState().softwareStatus == "available")

            #expect(requests().isEmpty)
            let actions = sandbox.commandLog().map(\.action)
            #expect(actions.contains("auto_conditioning_start"))
            #expect(actions.contains("set_temps"))
            #expect(actions.contains("remote_defrost"))
            #expect(actions.contains("set_seat_heat"))
            #expect(actions.contains("steering_wheel_heater"))
            #expect(actions.contains("software_install"))
            #expect(actions.contains("software_cancel"))
        }
    }

    @Test func `Demo Car presets cover hot cabin and low-battery road trip scenarios`() {
        let suiteName = "FleetSandboxPresets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sandbox = FleetSandboxStore(appGroup: suiteName)
        let hot = sandbox.applyPreset(.hotCabin)
        #expect(hot.insideTempF == 104)
        #expect(hot.outsideTempF == 93)
        #expect(hot.locked == false)
        #expect(hot.frontDriverWindowOpen == true)

        let trip = sandbox.applyPreset(.roadTripPrep)
        #expect(trip.batteryLevel == 42)
        #expect(trip.chargeLimitSOC == 80)
        #expect(trip.chargePortDoorOpen == true)
    }

    @Test func `GetReleaseNotesIntent expands FSD shorthand to Full Self-Driving in Demo Car mode`() async throws {
        try await withSandboxTestContext(
            mode: .demoVehicle,
            accessToken: nil,
            selectedVIN: nil,
            responder: { _ in throw FleetKitError.badResponse }
        ) { _, _, _ in
            let notesIntent = GetReleaseNotesIntent()
            notesIntent.featureQuery = "FSD"
            let notes = try #require(try await notesIntent.perform().value)
            #expect(notes.count == 1)
            #expect(notes.first?.title.contains("Full Self-Driving") == true)
        }
    }

    @Test func `VehicleEntity and VehicleStatusEntity resolve natural 'my car' queries and Spotlight aliases without 'Tesla'`() async throws {
        try await withSandboxTestContext(
            mode: .demoVehicle,
            accessToken: nil,
            selectedVIN: nil,
            responder: { _ in throw FleetKitError.badResponse }
        ) { _, _, _ in
            let carMatches = try await VehicleEntityQuery().entities(matching: "my car")
            #expect(carMatches.count == 1)
            let car = try #require(carMatches.first)
            #expect(car.id == FleetDemoVehicleState.demoVIN)

            let synonyms = car.displayRepresentation.synonyms.map { String(localized: $0) }
            #expect(synonyms.contains("my car"))
            #expect(synonyms.contains("the car"))
            #expect(car.attributeSet.alternateNames?.contains("My Car") == true)
            #expect(car.attributeSet.keywords?.contains("warm up my car") == true)

            let statusMatches = try await VehicleStatusEntityQuery().entities(matching: "warm up my car")
            #expect(statusMatches.first?.vin == FleetDemoVehicleState.demoVIN)
        }
    }

    @Test func `snippet notifications identify the changed card and skip unchanged selections`() {
        let key = UUID().uuidString
        let changes = Mutex<[SiriSnippetStateStore.Change]>([])
        let name = SiriSnippetStateStore.stateDidChangeNotification
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
            let change = SiriSnippetStateStore.Change(notification: notification)
            switch change {
            case .selection(let value), .mapStyle(let value), .vehicleStatus(let value):
                if value == key { changes.withLock { $0.append(change) } }
            case .all:
                break
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let store = SiriSnippetStateStore.shared
        store.setSelectedDriveIndex(0, for: key)
        store.setSelectedDriveIndex(1, for: key)
        store.setSelectedDriveIndex(1, for: key)
        store.toggleMapStyle(for: key)
        store.notifyChanged(.vehicleStatus(vin: key))

        let recorded = changes.withLock { $0 }
        #expect(recorded == [.selection(sessionKey: key), .mapStyle(scope: key), .vehicleStatus(vin: key)])
        #expect(SiriSnippetStateStore.Change(notification: Notification(name: name)) == .all)
    }

    @Test func `Interactive Siri route charge and climate widgets resolve GPS paths Apple Maps URLs and live controls`() async throws {
        try await withSandboxTestContext(
            mode: .demoVehicle,
            preset: .freezingMorning,
            accessToken: nil,
            selectedVIN: nil,
            responder: { _ in throw FleetKitError.badResponse }
        ) { sandbox, service, _ in
            let drives = try #require(try await GetRecentDrivesIntent().perform().value)
            #expect(drives.count == 2)

            let latestDrive = drives[0]
            #expect(latestDrive.startLatitude != nil && latestDrive.endLatitude != nil)
            #expect(latestDrive.appleMapsRouteURL?.absoluteString.contains("maps.apple.com") == true)

            let routePoints = await SiriMapSnapshotRenderer.resolveRoutePoints(
                for: latestDrive,
                service: service,
                allowGeocoding: false
            )
            #expect(routePoints.count >= 6)
            #expect(routePoints.contains { $0.isAutopilotActive })

            let sessionKey = "unit-test-route-\(UUID().uuidString)"
            let routeSnippet = DriveRouteSnippetIntent(drives: drives, vehicleName: "Midnight", sessionKey: sessionKey)
            _ = try await routeSnippet.perform()
            #expect(SiriSnippetStateStore.shared.selectedDriveIndex(for: sessionKey, count: drives.count) == 0)

            _ = try await SelectSnippetItemIntent(sessionKey: sessionKey, targetIndex: 1).perform()
            #expect(SiriSnippetStateStore.shared.selectedDriveIndex(for: sessionKey, count: drives.count) == 1)

            let scopeKey = "unit-test-style-\(UUID().uuidString)"
            #expect(SiriSnippetStateStore.shared.mapStyle(for: scopeKey) == .standard)
            _ = try await ToggleSnippetMapStyleIntent(scope: scopeKey).perform()
            #expect(SiriSnippetStateStore.shared.mapStyle(for: scopeKey) == .hybrid)

            let charges = try #require(try await GetRecentChargesIntent().perform().value)
            #expect(charges.count == 2)
            #expect(charges.first?.appleMapsLocationURL?.absoluteString.contains("maps.apple.com") == true)
            _ = try await ChargeSessionSnippetIntent(
                sessions: charges,
                vehicleName: "Midnight",
                sessionKey: "unit-test-charge-\(UUID().uuidString)"
            ).perform()

            let vehicleEntity = VehicleEntity(id: FleetDemoVehicleState.demoVIN, name: "Midnight")
            _ = try await ClimateControlSnippetIntent(vehicle: vehicleEntity, appliedSummary: "Climate on").perform()
            _ = try await AdjustSnippetClimateIntent(vehicle: vehicleEntity, targetFahrenheit: 72, turnOff: false).perform()
            #expect(sandbox.demoState().hvacOn == true)
            #expect(abs(sandbox.demoState().targetTempF - 71.6) < 0.5)

            _ = try await AdjustSnippetClimateIntent(vehicle: vehicleEntity, targetFahrenheit: 72, turnOff: true).perform()
            #expect(sandbox.demoState().hvacOn == false)
        }
    }
}



