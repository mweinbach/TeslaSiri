import FleetKit
import Foundation
import OSLog

protocol FleetAccessTokenProviding {
    func accessToken() async throws -> String
}

struct StaticFleetAccessTokenProvider: FleetAccessTokenProviding {
    var token: String

    func accessToken() async throws -> String {
        token
    }
}

struct MissingFleetAccessTokenProvider: FleetAccessTokenProviding {
    func accessToken() async throws -> String {
        throw FleetAPIError.missingAccessToken
    }
}

enum FleetAPIError: Error, LocalizedError {
    case missingAccessToken
    case invalidURL(String)
    case invalidHistoryRange
    case transport(Error)
    case decoding(Error, requestID: String?)
    case apiFailure(error: String, requiredScope: String?, requestID: String?)
    case missingData(requestID: String?)
    case unacceptableStatus(statusCode: Int, error: String?, requiredScope: String?, requestID: String?)
    case unsupportedFeature(String)
    case keychain(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return String(localized: "A vehicle provider access token is required.", comment: "Error shown when no provider access token is configured")
        case .invalidURL(let path):
            return String(localized: "The Tessie API URL could not be built for \(path).", comment: "Error shown when an API request URL cannot be constructed")
        case .invalidHistoryRange:
            return String(localized: "Tessie history requires a valid start and end time.", comment: "Error shown when requesting drive or telemetry history with an invalid time range")
        case .transport(let error):
            return String(localized: "Network request failed: \(error.localizedDescription)", comment: "Error shown when a network request fails")
        case .decoding(let error, let requestID):
            return withRequestID(
                String(localized: "The Tessie response could not be decoded: \(decodingMessage(error))", comment: "Error shown when an API response cannot be parsed"),
                requestID: requestID
            )
        case .apiFailure(let error, _, let requestID):
            return withRequestID(
                String(localized: "Tessie API error: \(error)", comment: "Error shown when the Tessie API returns an error message"),
                requestID: requestID
            )
        case .missingData(let requestID):
            return withRequestID(
                String(localized: "Tessie returned a success response without data.", comment: "Error shown when the API returns an empty payload"),
                requestID: requestID
            )
        case .unacceptableStatus(let statusCode, let error, _, let requestID):
            let base = error.map {
                String(localized: "Tessie request failed with HTTP \(statusCode): \($0)", comment: "Error shown when an HTTP request fails with a status code and server message")
            } ?? String(localized: "Tessie request failed with HTTP \(statusCode).", comment: "Error shown when an HTTP request fails with a status code")
            return withRequestID(base, requestID: requestID)
        case .unsupportedFeature(let feature):
            return String(localized: "\(feature) is not available through the Tessie API.", comment: "Error shown when an action is unsupported by the Tessie API")
        case .keychain(let status):
            return String(localized: "Keychain operation failed with status \(status).", comment: "Error shown when saving or reading a credential in Keychain fails")
        }
    }

    private func decodingMessage(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing key \(key.stringValue) at \(codingPath(context.codingPath))"
        case DecodingError.typeMismatch(_, let context):
            return "type mismatch at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case DecodingError.valueNotFound(_, let context):
            return "missing value at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "corrupt data at \(codingPath(context.codingPath)): \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private func codingPath(_ path: [CodingKey]) -> String {
        let value = path.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "root" : value
    }

    private func withRequestID(_ message: String, requestID: String?) -> String {
        guard let requestID else { return message }
        return String(localized: "\(message) Request ID: \(requestID).", comment: "Appends an API request identifier to an error message")
    }
}

struct FleetAPIClient {
    private static let logger = Logger(subsystem: "com.maxweinbach.TeslaSiri", category: "TessieAPI")

    struct Configuration {
        var baseURL: URL
        var timeout: TimeInterval

        static var production: Configuration {
            guard let url = URL(string: "https://api.tessie.com") else {
                preconditionFailure("Invalid Tessie API base URL.")
            }
            return Configuration(baseURL: url, timeout: 30)
        }
    }

    private enum HTTPMethod: String {
        case delete = "DELETE"
        case get = "GET"
        case patch = "PATCH"
        case post = "POST"
    }

    private struct Endpoint {
        var method: HTTPMethod
        var path: String
        var queryItems: [URLQueryItem]
        var body: Data?
        var requiresAuthorization: Bool
        var accept: String
        var cachePolicy: URLRequest.CachePolicy
        var timeout: TimeInterval?

        init(
            method: HTTPMethod = .get,
            path: String,
            queryItems: [URLQueryItem] = [],
            body: Data? = nil,
            requiresAuthorization: Bool = true,
            accept: String = "application/json",
            cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
            timeout: TimeInterval? = nil
        ) {
            self.method = method
            self.path = path
            self.queryItems = queryItems
            self.body = body
            self.requiresAuthorization = requiresAuthorization
            self.accept = accept
            self.cachePolicy = cachePolicy
            self.timeout = timeout
        }
    }

    struct Response<Value: Sendable>: Sendable {
        var data: Value
        var requestID: String?
    }

    @MainActor
    private final class VehicleStateScope {
        var vin: String?
        var cached: (token: String, source: String, response: Response<TessieJSONObject>)?

        var readings: FleetSpotlightIndexer.DashboardReadings

        init(vin: String) {
            self.vin = vin
            self.readings = .init(vin: vin)
        }

        func record(_ data: Data, endpoint: Endpoint) {
            guard let vin, endpoint.method == .get else { return }
            let path = endpoint.path.split(separator: "/")
            guard path.count >= 2, path[0].removingPercentEncoding == vin else { return }
            let limit = endpoint.queryItems.first { $0.name == "limit" }?.value.flatMap(Int.init)
            switch path[1] {
            case "state": readings.state = data
            case "tire_pressure": readings.tires = data
            case "drives":
                readings.drives = data
                readings.driveLimit = limit
            case "charges":
                readings.charges = data
                readings.chargeLimit = limit
            case "release_notes":
                readings.notes = data
                readings.notesVersion = path.last?.removingPercentEncoding
            default: break
            }
        }
    }

    @TaskLocal private static var vehicleStateScope: VehicleStateScope?

    @MainActor
    static func withSharedVehicleState(for vin: String, operation: @MainActor () async -> Void) async -> FleetSpotlightIndexer.DashboardReadings {
        let scope = VehicleStateScope(vin: vin)
        defer {
            scope.vin = nil
            scope.cached = nil
        }
        await $vehicleStateScope.withValue(scope) {
            await operation()
        }
        return scope.readings
    }

    private static let pathComponentAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private var configuration: Configuration
    private var session: URLSession
    private var accessTokenProvider: any FleetAccessTokenProviding

    init(
        configuration: Configuration = .production,
        session: URLSession = .shared,
        accessTokenProvider: any FleetAccessTokenProviding
    ) {
        self.configuration = configuration
        self.session = session
        self.accessTokenProvider = accessTokenProvider
    }

    // MARK: - Account and synchronization

    func currentUser() async throws -> FleetAPIPage<FleetUser> {
        let response = try await vehicleRecords()
        return page(TessieModelAdapter.user(from: response.data.first?.lastState), requestID: response.requestID)
    }

    func capabilities() async throws -> FleetAPIPage<FleetCapabilities> {
        page(TessieModelAdapter.capabilities)
    }

    func bootstrap() async throws -> FleetAPIPage<FleetBootstrap> {
        let response = try await vehicleRecords()
        let vehicles = response.data.map(TessieModelAdapter.vehicle)
        let activeCharging = response.data.compactMap { record in
            record.lastState.flatMap { TessieModelAdapter.activeCharge(vin: record.vin, state: $0) }
        }
        let bootstrap = FleetBootstrap(
            activeCharging: activeCharging,
            capabilities: TessieModelAdapter.capabilities,
            recentDrives: [],
            user: TessieModelAdapter.user(from: response.data.first?.lastState),
            vehicles: vehicles
        )
        return page(bootstrap, cursor: Self.currentTimeMilliseconds(), requestID: response.requestID)
    }

    func changes(since cursor: Int64, refresh: Bool = false) async throws -> FleetAPIPage<FleetSyncChanges> {
        let cachePolicy: URLRequest.CachePolicy = refresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        let response = try await vehicleRecords(cachePolicy: cachePolicy)
        let vehicles = response.data.map(TessieModelAdapter.vehicle)
        return page(
            FleetSyncChanges(latest: vehicles.compactMap(\.latest), vehicles: vehicles),
            cursor: max(Self.currentTimeMilliseconds(), cursor + 1),
            requestID: response.requestID
        )
    }

    // MARK: - Vehicles and history

    func vehicles(includeLive: Bool = true) async throws -> FleetAPIPage<[FleetVehicle]> {
        let response = try await vehicleRecords()
        return page(response.data.map(TessieModelAdapter.vehicle), requestID: response.requestID)
    }

    func vehicleSummary(vin: String) async throws -> FleetAPIPage<FleetVehicle> {
        let response = try await snapshotState(vin: vin)
        let vehicle = FleetVehicle(
            displayName: response.state.displayName,
            latest: TessieModelAdapter.snapshot(vin: vin, state: response.state, tireState: response.tireState),
            permissions: ["read", "control"],
            vin: vin
        )
        return page(vehicle, requestID: response.requestID)
    }

    func wakeVehicle(vin: String) async throws {
        let response: Response<TessieCommandResponse> = try await send(Endpoint(
            method: .post,
            path: "/\(encoded(vin))/wake",
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeout: max(configuration.timeout, FleetKitConfig.commandTimeout)
        ))
        guard response.data.result else {
            throw FleetAPIError.apiFailure(
                error: String(
                    localized: "The vehicle did not wake up in time.",
                    comment: "Error shown when a wake request times out before the vehicle comes online"
                ),
                requiredScope: nil,
                requestID: response.requestID
            )
        }
    }

    func latestSnapshot(vin: String, includingTires: Bool = true, refresh: Bool = false) async throws -> FleetAPIPage<FleetLatestSnapshot> {
        let cachePolicy: URLRequest.CachePolicy = refresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        if !includingTires {
            let response = try await vehicleState(vin: vin, cachePolicy: cachePolicy)
            return page(TessieModelAdapter.snapshot(vin: vin, state: response.data), requestID: response.requestID)
        }
        let response = try await snapshotState(vin: vin, cachePolicy: cachePolicy)
        return page(
            TessieModelAdapter.snapshot(vin: vin, state: response.state, tireState: response.tireState),
            requestID: response.requestID
        )
    }

    func locations(
        vin: String,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int? = nil
    ) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        let range = try historyRange(startTime: startTime, endTime: endTime)
        let response = try await routePoints(vin: vin, range: range, simplify: true)
        let points = limit.map { Array(response.data.suffix(max($0, 0))) } ?? response.data
        return page(points, requestID: response.requestID)
    }

    func telemetrySeries(
        vin: String,
        topic: String? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int? = nil,
        maxPoints: Int? = nil,
        fields: [String] = []
    ) async throws -> FleetAPIPage<[FleetTelemetrySeriesPoint]> {
        let range = try historyRange(startTime: startTime, endTime: endTime)
        let pointLimit = [limit, maxPoints].compactMap { $0 }.min() ?? 100
        guard pointLimit > 0 else { return page([]) }
        let interval = max((range.to - range.from) / Int64(pointLimit), 1)
        let response: Response<TessieResults<FleetTelemetrySeriesPoint>> = try await send(Endpoint(
            path: "/\(encoded(vin))/states",
            queryItems: [
                URLQueryItem(name: "from", value: String(range.from)),
                URLQueryItem(name: "to", value: String(range.to)),
                URLQueryItem(name: "interval", value: String(interval)),
                URLQueryItem(name: "condense", value: "false"),
                URLQueryItem(name: "distance_format", value: "mi"),
                URLQueryItem(name: "temperature_format", value: "f")
            ]
        ))
        let points = response.data.results.sorted {
            ($0["timestamp"]?.tessieInt64Value ?? 0) < ($1["timestamp"]?.tessieInt64Value ?? 0)
        }
        return page(Array(points.suffix(pointLimit)), requestID: response.requestID)
    }

    // MARK: - Drives and charging

    func drives(vin: String, limit: Int? = nil, includeRoute: Bool = true) async throws -> FleetAPIPage<[FleetDriveSession]> {
        var query = [URLQueryItem(name: "distance_format", value: "mi")]
        if Self.vehicleStateScope != nil { query.append(URLQueryItem(name: "temperature_format", value: "f")) }
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let response: Response<TessieResults<TessieSelectedObject<TessieDriveField>>> = try await send(Endpoint(
            path: "/\(encoded(vin))/drives",
            queryItems: query
        ))
        return page(
            response.data.results
                .compactMap { TessieModelAdapter.drive(from: $0.fields, vin: vin) }
                .sorted { $0.startedAt > $1.startedAt },
            requestID: response.requestID
        )
    }

    func activeDrive(
        vin: String,
        includeRoute: Bool = false,
        routeMaxPoints: Int? = nil
    ) async throws -> FleetAPIPage<FleetActiveDriveSession> {
        let stateResponse = try await vehicleState(vin: vin)
        let gear = stateResponse.data.object("drive_state").string("shift_state")?.uppercased()
        let isActive = gear.map { $0 != "P" } ?? false
        var route: [FleetRoutePoint] = []
        var requestID = stateResponse.requestID
        if isActive, includeRoute {
            let routePage = try await locations(
                vin: vin,
                startTime: Self.currentTimeMilliseconds() - 7_200_000,
                endTime: nil,
                limit: routeMaxPoints
            )
            route = routePage.data
            requestID = routePage.requestID ?? requestID
        }
        return page(
            TessieModelAdapter.activeDrive(vin: vin, state: stateResponse.data, route: route),
            requestID: requestID
        )
    }

    func driveSession(
        sessionID: String,
        includeRoute: Bool = false,
        maxPoints: Int? = nil
    ) async throws -> FleetAPIPage<FleetDriveSession> {
        guard let vin = vin(fromSessionID: sessionID) else {
            throw FleetAPIError.missingData(requestID: nil)
        }
        let drivesPage = try await drives(vin: vin, limit: 100, includeRoute: false)
        guard var drive = drivesPage.data.first(where: { $0.sessionID == sessionID }) else {
            throw FleetAPIError.missingData(requestID: drivesPage.requestID)
        }
        if includeRoute {
            drive.route = try await driveRoute(
                sessionID: sessionID,
                startTime: drive.startedAt,
                endTime: drive.endedAt,
                limit: nil,
                maxPoints: maxPoints
            ).data
        }
        return page(drive, requestID: drivesPage.requestID)
    }

    func driveRoute(
        sessionID: String,
        startTime: Int64? = nil,
        endTime: Int64? = nil,
        limit: Int? = nil,
        maxPoints: Int? = nil
    ) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        guard let vin = vin(fromSessionID: sessionID) else {
            throw FleetAPIError.missingData(requestID: nil)
        }
        guard let from = apiSeconds(startTime), let to = apiSeconds(endTime),
              from > 0, to >= from else {
            throw FleetAPIError.invalidHistoryRange
        }
        let response = try await routePoints(vin: vin, range: (from, to), simplify: false)
        let points = response.data
        guard let cap = maxPoints ?? limit, points.count > cap else {
            return page(points, requestID: response.requestID)
        }
        guard cap > 1 else {
            return page(Array(points.prefix(max(cap, 0))), requestID: response.requestID)
        }
        // Sample across the whole drive so the map and scrubber keep both endpoints.
        let sampled = (0..<cap).map { points[$0 * (points.count - 1) / (cap - 1)] }
        return page(sampled, requestID: response.requestID)
    }

    func chargingSessions(vin: String, limit: Int? = nil) async throws -> FleetAPIPage<[FleetChargeSession]> {
        var query = [URLQueryItem(name: "distance_format", value: "mi")]
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        async let stateResponse = vehicleState(vin: vin)
        let charges: Response<TessieResults<TessieSelectedObject<TessieChargeField>>> = try await send(
            Endpoint(path: "/\(encoded(vin))/charges", queryItems: query)
        )
        let state = try? await stateResponse
        try Task.checkCancellation()

        var sessions = state.flatMap { TessieModelAdapter.activeCharge(vin: vin, state: $0.data) }.map { [$0] } ?? []
        sessions.append(contentsOf: charges.data.results
            .compactMap { TessieModelAdapter.completedCharge(from: $0.fields, vin: vin) }
            .sorted { $0.startedAt > $1.startedAt })
        if let limit {
            sessions = Array(sessions.prefix(max(limit, 0)))
        }
        return page(sessions, requestID: charges.requestID ?? state?.requestID)
    }

    func chargingOptions(vin: String) async throws -> FleetAPIPage<FleetChargingOptions> {
        let vehiclePage = try await vehicleSummary(vin: vin)
        return page(
            FleetChargingOptions(
                actions: TessieModelAdapter.chargeActions,
                chargeState: vehiclePage.data.latest,
                vehicle: vehiclePage.data
            ),
            requestID: vehiclePage.requestID
        )
    }

    func chargingCurve(sessionID: String, limit: Int? = nil) async throws -> FleetAPIPage<[FleetTelemetrySeriesPoint]> {
        throw FleetAPIError.unsupportedFeature(
            String(
                localized: "Per-session charging curves",
                comment: "Feature name interpolated into the unsupported feature error message"
            )
        )
    }

    // MARK: - Software and commands

    func controlActions() async throws -> FleetAPIPage<FleetControlActions> {
        page(TessieModelAdapter.controlActionInfo)
    }

    func softwareUpdate(
        vin: String,
        includeReleaseNotes: Bool = true,
        refresh: Bool = false
    ) async throws -> FleetAPIPage<FleetSoftwareUpdate> {
        let cachePolicy: URLRequest.CachePolicy = refresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        let response = try await vehicleState(vin: vin, cachePolicy: cachePolicy)
        var update = TessieModelAdapter.software(from: response.data)
        if includeReleaseNotes,
           let version = Self.sanitizedReleaseVersion(update.availableVersion)
               ?? Self.sanitizedReleaseVersion(update.currentVersion) {
            do {
                let notes: Response<TessieReleaseNotes> = try await send(
                    releaseNotesEndpoint(vin: vin, version: version, cachePolicy: cachePolicy)
                )
                update.releaseNotes = notes.data.releaseNotes
                update.releaseNotesCount = notes.data.releaseNotes.count
            } catch {
                // The software state is still usable when Tessie has no notes for this version.
                try Task.checkCancellation()
            }
        }
        return page(update, requestID: response.requestID)
    }

    func installSoftwareUpdate(vin: String, offsetSec: Int = 0) async throws -> FleetAPIPage<[String: JSONValue]> {
        try await command(
            path: "/\(encoded(vin))/command/schedule_software_update",
            queryItems: [URLQueryItem(name: "in_seconds", value: String(max(offsetSec, 0)))]
        )
    }

    func cancelSoftwareUpdate(vin: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        try await command(path: "/\(encoded(vin))/command/cancel_software_update")
    }

    func runControl(
        action: String,
        vin: String,
        params: [String: JSONValue] = [:]
    ) async throws -> FleetAPIPage<[String: JSONValue]> {
        let commandName: String
        var queryItems: [URLQueryItem] = []

        switch action {
        case "door_lock": commandName = "lock"
        case "door_unlock": commandName = "unlock"
        case "auto_conditioning_start": commandName = "start_climate"
        case "auto_conditioning_stop": commandName = "stop_climate"
        case "window_control":
            guard params["command"]?.tessieStringValue == "vent" else {
                throw FleetAPIError.unsupportedFeature(
                    String(
                        localized: "That window command",
                        comment: "Feature phrase interpolated into the unsupported feature error message when an unsupported window action is requested"
                    )
                )
            }
            commandName = "vent_windows"
        case "actuate_trunk":
            commandName = params["which_trunk"]?.tessieStringValue == "front"
                ? "activate_front_trunk"
                : "activate_rear_trunk"
        case "set_charge_limit":
            commandName = "set_charge_limit"
            queryItems = [try queryItem("percent", params: params)]
        case "set_temps":
            commandName = "set_temperatures"
            guard let temperature = params["driver_temp"] ?? params["passenger_temp"] else {
                throw FleetAPIError.missingData(requestID: nil)
            }
            queryItems = [URLQueryItem(name: "temperature", value: temperature.tessieStringValue)]
        case "remote_defrost":
            commandName = params["on"]?.tessieBoolValue == false ? "stop_max_defrost" : "start_max_defrost"
        case "set_pet_mode":
            commandName = "set_climate_keeper_mode"
            queryItems = [URLQueryItem(name: "mode", value: params["on"]?.tessieBoolValue == false ? "0" : "2")]
        case "set_bioweapon_mode":
            commandName = "set_bioweapon_mode"
            queryItems = [try queryItem("on", params: params)]
        case "charge_port_door_open": commandName = "open_charge_port"
        case "charge_port_door_close": commandName = "close_charge_port"
        case "charge_start": commandName = "start_charging"
        case "charge_stop": commandName = "stop_charging"
        case "set_sentry_mode":
            commandName = params["on"]?.tessieBoolValue == false ? "disable_sentry" : "enable_sentry"
        case "flash_lights": commandName = "flash"
        case "honk_horn": commandName = "honk"
        case "navigation_request":
            commandName = "share"
            queryItems = [try queryItem("value", params: params)]
        default:
            throw FleetAPIError.unsupportedFeature(action)
        }

        return try await command(
            path: "/\(encoded(vin))/command/\(commandName)",
            queryItems: queryItems
        )
    }

    // MARK: - Raw export

    func rawVehicleDataExport(vin: String) async throws -> FleetRawDataExport {
        let accessToken = try await accessTokenProvider.accessToken()
        let vehiclePath = "/\(encoded(vin))"
        let state = try await fetchRawResponse(for: Endpoint(path: "\(vehiclePath)/state"), accessToken: accessToken)
        let software = state.body?.tessieObjectValue.map(TessieModelAdapter.software)
        let version = Self.sanitizedReleaseVersion(software?.availableVersion)
            ?? Self.sanitizedReleaseVersion(software?.currentVersion)

        let now = Int64(Date().timeIntervalSince1970)
        let lastDay = historyQuery(from: now - 86_400, to: now)
        let lastMonth = historyQuery(from: now - 30 * 86_400, to: now)
        let miles = URLQueryItem(name: "distance_format", value: "mi")
        let activeVehicles = URLQueryItem(name: "only_active", value: "true")
        let sessionHistory = lastMonth + [miles, URLQueryItem(name: "limit", value: "10")]

        // The documented Vehicle Data GET endpoints. Account-wide routes have no VIN in the path.
        let endpoints = [
            Endpoint(path: "/vehicles", queryItems: [activeVehicles]),
            Endpoint(path: "\(vehiclePath)/states", queryItems: lastDay + [
                URLQueryItem(name: "interval", value: "300"),
                URLQueryItem(name: "condense", value: "false"),
                miles,
                URLQueryItem(name: "temperature_format", value: "f")
            ]),
            Endpoint(path: "\(vehiclePath)/battery"),
            Endpoint(path: "/battery_health", queryItems: lastMonth + [miles, activeVehicles]),
            Endpoint(path: "\(vehiclePath)/battery_health", queryItems: lastMonth + [miles]),
            Endpoint(path: "\(vehiclePath)/location"),
            Endpoint(path: "\(vehiclePath)/firmware_alerts", queryItems: lastMonth),
            releaseNotesEndpoint(vin: vin, version: version),
            Endpoint(path: "\(vehiclePath)/map", accept: "image/png"),
            Endpoint(path: "\(vehiclePath)/consumption_since_charge"),
            Endpoint(path: "\(vehiclePath)/weather"),
            Endpoint(path: "\(vehiclePath)/drives", queryItems: sessionHistory),
            Endpoint(path: "\(vehiclePath)/path", queryItems: lastDay + [
                URLQueryItem(name: "details", value: "true"),
                URLQueryItem(name: "simplify", value: "true")
            ]),
            Endpoint(path: "\(vehiclePath)/charges", queryItems: sessionHistory),
            Endpoint(path: "/charging_invoices", queryItems: lastMonth + [URLQueryItem(name: "vin", value: vin)]),
            Endpoint(path: "\(vehiclePath)/idles", queryItems: sessionHistory),
            Endpoint(path: "\(vehiclePath)/last_idle_state"),
            Endpoint(path: "\(vehiclePath)/tire_pressure", queryItems: [URLQueryItem(name: "pressure_format", value: "psi")]),
            Endpoint(path: "\(vehiclePath)/status"),
            Endpoint(path: "\(vehiclePath)/plate")
        ]

        // Bound simultaneous downloads, particularly the map and two history payloads.
        let responses = try await withThrowingTaskGroup(of: (Int, FleetRawAPIResponse).self) { group in
            var ordered = [FleetRawAPIResponse?](repeating: nil, count: endpoints.count)
            for (index, endpoint) in endpoints.enumerated() {
                if index >= 3, let (finished, response) = try await group.next() {
                    ordered[finished] = response
                }
                try Task.checkCancellation()
                group.addTask { @MainActor in
                    let response = try await fetchRawResponse(for: endpoint, accessToken: accessToken)
                    return (index, response)
                }
            }
            for try await (index, response) in group {
                ordered[index] = response
            }
            try Task.checkCancellation()
            return [state] + ordered.compactMap { $0 }
        }

        return FleetRawDataExport(
            apiBaseURL: configuration.baseURL.absoluteString,
            appSchemaVersion: 3,
            generatedAt: Self.currentTimeMilliseconds(),
            responses: responses,
            vin: vin
        )
    }

    // MARK: - Features not exposed by Tessie

    func webhooks(includeDisabled: Bool = false) async throws -> FleetAPIPage<[FleetWebhook]> {
        throw FleetAPIError.unsupportedFeature("Webhook management")
    }

    func createWebhook(_ request: FleetWebhookCreateRequest) async throws -> FleetAPIPage<FleetWebhook> {
        throw FleetAPIError.unsupportedFeature("Webhook management")
    }

    func updateWebhook(id: String, request: FleetWebhookUpdateRequest) async throws -> FleetAPIPage<FleetWebhook> {
        throw FleetAPIError.unsupportedFeature("Webhook management")
    }

    func deleteWebhook(id: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        throw FleetAPIError.unsupportedFeature("Webhook management")
    }

    func testWebhook(id: String) async throws -> FleetAPIPage<FleetWebhookDeliveryResult> {
        throw FleetAPIError.unsupportedFeature("Webhook management")
    }

    func notificationWebhooks(deviceID: String? = nil, includeDisabled: Bool = false) async throws -> FleetAPIPage<[FleetDeviceNotificationWebhook]> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func createNotificationWebhook(_ request: FleetDeviceNotificationWebhookCreateRequest) async throws -> FleetAPIPage<FleetDeviceNotificationWebhook> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func updateNotificationWebhook(id: String, request: FleetDeviceNotificationWebhookUpdateRequest) async throws -> FleetAPIPage<FleetDeviceNotificationWebhook> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func deleteNotificationWebhook(id: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func testNotificationWebhook(id: String, request: FleetDeviceNotificationWebhookTestRequest? = nil) async throws -> FleetAPIPage<FleetWebhookDeliveryResult> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func notificationWebhooks(forDeviceID deviceID: String, includeDisabled: Bool = false) async throws -> FleetAPIPage<[FleetDeviceNotificationWebhook]> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func createNotificationWebhook(forDeviceID deviceID: String, request: FleetDeviceNotificationWebhookCreateForDeviceRequest) async throws -> FleetAPIPage<FleetDeviceNotificationWebhook> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func updateNotificationWebhook(forDeviceID deviceID: String, id: String, request: FleetDeviceNotificationWebhookUpdateRequest) async throws -> FleetAPIPage<FleetDeviceNotificationWebhook> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func deleteNotificationWebhook(forDeviceID deviceID: String, id: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func testNotificationWebhook(forDeviceID deviceID: String, id: String, request: FleetDeviceNotificationWebhookTestRequest? = nil) async throws -> FleetAPIPage<FleetWebhookDeliveryResult> {
        throw FleetAPIError.unsupportedFeature("Notification webhooks")
    }

    func streamURL(vin: String? = nil, includeDrive: Bool = true, includeRoute: Bool = false, routeMaxPoints: Int? = nil) throws -> URL {
        throw FleetAPIError.unsupportedFeature("The legacy websocket stream")
    }

    func streamRequest(vin: String? = nil, includeDrive: Bool = true, includeRoute: Bool = false, routeMaxPoints: Int? = nil) async throws -> URLRequest {
        throw FleetAPIError.unsupportedFeature("The legacy websocket stream")
    }

    // MARK: - Transport

    private func routePoints(
        vin: String,
        range: (from: Int64, to: Int64),
        simplify: Bool
    ) async throws -> Response<[FleetRoutePoint]> {
        let response: Response<TessieResults<TessiePathSample>> = try await send(Endpoint(
            path: "/\(encoded(vin))/path",
            queryItems: historyQuery(from: range.from, to: range.to) + [
                URLQueryItem(name: "details", value: "true"),
                URLQueryItem(name: "simplify", value: simplify ? "true" : "false")
            ]
        ))
        let points = response.data.results
            .compactMap(\.routePoint)
            .sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        return Response(data: points, requestID: response.requestID)
    }

    private func historyQuery(from: Int64, to: Int64) -> [URLQueryItem] {
        [
            URLQueryItem(name: "from", value: String(from)),
            URLQueryItem(name: "to", value: String(to))
        ]
    }

    private func releaseNotesEndpoint(
        vin: String,
        version: String?,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) -> Endpoint {
        let safeVersion = Self.sanitizedReleaseVersion(version) ?? ""
        return Endpoint(
            path: "/\(encoded(vin))/release_notes/\(encoded(safeVersion))",
            cachePolicy: cachePolicy
        )
    }

    private static func sanitizedReleaseVersion(_ version: String?) -> String? {
        guard let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != ".",
              trimmed != ".." else {
            return nil
        }
        return trimmed
    }

    @MainActor
    private func vehicleState(
        vin: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> Response<TessieJSONObject> {
        let endpoint = Endpoint(path: "/\(encoded(vin))/state", cachePolicy: cachePolicy)
        func readState(accessToken: String? = nil) async throws -> Response<TessieJSONObject> {
            let response: Response<TessieVehicleState> = try await send(endpoint, accessToken: accessToken)
            return Response(data: response.data.fields, requestID: response.requestID)
        }
        guard let scope = Self.vehicleStateScope, scope.vin == vin else {
            return try await readState()
        }
        if cachePolicy != .useProtocolCachePolicy {
            scope.cached = nil
        }

        let token = try await accessTokenProvider.accessToken()
        try Task.checkCancellation()
        return try await Self.sharedVehicleState(vin: vin, token: token, source: configuration.baseURL.absoluteString) {
            try await readState(accessToken: token)
        }
    }

    @MainActor
    static func sharedVehicleState(
        vin: String, token: String, source: String, load: () async throws -> Response<TessieJSONObject>
    ) async throws -> Response<TessieJSONObject> {
        guard let scope = vehicleStateScope, scope.vin == vin else { return try await load() }
        if let cached = scope.cached, cached.token == token, cached.source == source { return cached.response }
        let response = try await load()
        try Task.checkCancellation()
        if scope.vin == vin { scope.cached = (token, source, response) }
        return response
    }

    static func recordDashboardState(_ data: Data, vin: String) {
        guard let scope = vehicleStateScope, scope.vin == vin else { return }
        scope.readings.state = data
    }

    private func snapshotState(
        vin: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> (state: TessieJSONObject, tireState: TessieJSONObject?, requestID: String?) {
        let vehiclePath = "/\(encoded(vin))"
        async let tireRequest: Response<TessieJSONObject> = send(Endpoint(
            path: "\(vehiclePath)/tire_pressure",
            queryItems: [URLQueryItem(name: "pressure_format", value: "psi")],
            cachePolicy: cachePolicy
        ))
        let stateResponse = try await vehicleState(vin: vin, cachePolicy: cachePolicy)
        let tireState: TessieJSONObject?
        do {
            tireState = try await tireRequest.data
        } catch FleetAPIError.missingAccessToken {
            throw FleetAPIError.missingAccessToken
        } catch let error as FleetAPIError {
            if case .unacceptableStatus(statusCode: 401, _, _, _) = error {
                throw error
            }
            try Task.checkCancellation()
            tireState = nil
        } catch {
            try Task.checkCancellation()
            tireState = nil
        }
        return (stateResponse.data, tireState, stateResponse.requestID)
    }

    private func vehicleRecords(cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> Response<[TessieVehicleRecord]> {
        let response: Response<TessieResults<TessieVehicleRecord>> = try await send(Endpoint(
            path: "/vehicles",
            queryItems: [URLQueryItem(name: "only_active", value: "true")],
            cachePolicy: cachePolicy
        ))
        return Response(data: response.data.results, requestID: response.requestID)
    }

    private func command(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> FleetAPIPage<[String: JSONValue]> {
        let response: Response<TessieCommandResponse> = try await send(Endpoint(
            method: .post,
            path: path,
            queryItems: queryItems,
            timeout: max(configuration.timeout, FleetKitConfig.commandTimeout)
        ))
        guard response.data.result else {
            throw FleetAPIError.apiFailure(
                error: "Tessie did not accept the vehicle command.",
                requiredScope: nil,
                requestID: response.requestID
            )
        }
        return page(["result": .bool(true)], requestID: response.requestID)
    }

    private func queryItem(_ name: String, params: [String: JSONValue]) throws -> URLQueryItem {
        guard let value = params[name]?.tessieStringValue else {
            throw FleetAPIError.missingData(requestID: nil)
        }
        return URLQueryItem(name: name, value: value)
    }

    @concurrent
    private static func decode<Value: Decodable & Sendable>(_ type: Value.Type, from data: Data) async throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }

    private func send<Value: Decodable & Sendable>(
        _ endpoint: Endpoint,
        accessToken: String? = nil
    ) async throws -> Response<Value> {
        let request = try await makeRequest(for: endpoint, accessToken: accessToken)
        let (data, response) = try await perform(request, endpoint: endpoint)
        do {
            let decoded = try await Self.decode(Value.self, from: data)
            Self.vehicleStateScope?.record(data, endpoint: endpoint)
            return Response(data: decoded, requestID: requestID(from: response))
        } catch {
            let requestID = requestID(from: response)
            Self.logger.error("Tessie decoding failed: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .private) error \(error.localizedDescription, privacy: .private)")
            throw FleetAPIError.decoding(error, requestID: requestID)
        }
    }

    private func perform(_ request: URLRequest, endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        Self.logger.debug("Tessie request preparing: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .private)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("Tessie transport failed: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .private) error \(error.localizedDescription, privacy: .private)")
            throw FleetAPIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FleetAPIError.transport(URLError(.badServerResponse))
        }
        let requestID = requestID(from: httpResponse)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorObject = try? await Self.decode(TessieJSONObject.self, from: data)
            let responseMessage = errorObject?.string("error") ?? errorObject?.string("message")
            let message = httpResponse.statusCode == 401
                ? "The Tessie access token is invalid or revoked."
                : responseMessage
            Self.logger.warning("Tessie request failed: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .private) status \(httpResponse.statusCode, privacy: .public)")
            throw FleetAPIError.unacceptableStatus(
                statusCode: httpResponse.statusCode,
                error: message,
                requiredScope: nil,
                requestID: requestID
            )
        }

        Self.logger.info("Tessie request completed: \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .private) status \(httpResponse.statusCode, privacy: .public)")
        return (data, httpResponse)
    }

    private func makeRequest(for endpoint: Endpoint, accessToken: String? = nil) async throws -> URLRequest {
        let url = try makeURL(path: endpoint.path, queryItems: endpoint.queryItems)
        var request = URLRequest(
            url: url,
            cachePolicy: endpoint.cachePolicy,
            timeoutInterval: endpoint.timeout ?? configuration.timeout
        )
        request.httpMethod = endpoint.method.rawValue
        request.setValue(endpoint.accept, forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuthorization {
            let token = if let accessToken { accessToken } else { try await accessTokenProvider.accessToken() }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw FleetAPIError.invalidURL(path)
        }
        components.percentEncodedPath = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw FleetAPIError.invalidURL(path)
        }
        return url
    }

    private func fetchRawResponse(for endpoint: Endpoint, accessToken: String) async throws -> FleetRawAPIResponse {
        try Task.checkCancellation()
        let request = try await makeRequest(for: endpoint, accessToken: accessToken)
        let startedAt = Self.currentTimeMilliseconds()
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            let payload = await Self.rawPayload(data, contentType: httpResponse.mimeType)
            try Task.checkCancellation()
            return rawResponse(
                endpoint: endpoint,
                request: request,
                startedAt: startedAt,
                statusCode: httpResponse.statusCode,
                cacheControl: httpResponse.value(forHTTPHeaderField: "Cache-Control"),
                requestID: requestID(from: httpResponse),
                body: payload.body,
                bodyText: payload.text,
                errorMessage: nil
            )
        } catch {
            try Task.checkCancellation()
            return rawResponse(
                endpoint: endpoint,
                request: request,
                startedAt: startedAt,
                statusCode: nil,
                cacheControl: nil,
                requestID: nil,
                body: nil,
                bodyText: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    @concurrent
    static func rawPayload(_ data: Data, contentType: String?) async -> (body: JSONValue?, text: String?) {
        if let contentType, contentType.hasPrefix("image/") {
            return (.object([
                "content_type": .string(contentType),
                "base64": .string(data.base64EncodedString())
            ]), nil)
        }
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return (json, nil)
        }
        return (nil, String(data: data, encoding: .utf8))
    }

    private func rawResponse(
        endpoint: Endpoint,
        request: URLRequest,
        startedAt: Int64,
        statusCode: Int?,
        cacheControl: String?,
        requestID: String?,
        body: JSONValue?,
        bodyText: String?,
        errorMessage: String?
    ) -> FleetRawAPIResponse {
        FleetRawAPIResponse(
            apiVersion: "tessie-v1",
            body: body,
            bodyText: bodyText,
            cacheControl: cacheControl,
            durationMS: max(Self.currentTimeMilliseconds() - startedAt, 0),
            errorMessage: errorMessage,
            method: endpoint.method.rawValue,
            path: endpoint.path,
            query: Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") }),
            requestID: requestID,
            statusCode: statusCode,
            timestamp: startedAt,
            url: request.url?.absoluteString ?? endpoint.path
        )
    }

    private func requestID(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "X-Request-Id")
            ?? response.value(forHTTPHeaderField: "CF-Ray")
    }

    private func historyRange(startTime: Int64?, endTime: Int64?) throws -> (from: Int64, to: Int64) {
        let now = Int64(Date().timeIntervalSince1970)
        let to = apiSeconds(endTime) ?? now
        let from = apiSeconds(startTime) ?? (to - 86_400)
        guard from > 0, to >= from else {
            throw FleetAPIError.invalidHistoryRange
        }
        return (from, to)
    }

    private func apiSeconds(_ timestamp: Int64?) -> Int64? {
        guard let timestamp else { return nil }
        return timestamp.magnitude >= 10_000_000_000 ? timestamp / 1_000 : timestamp
    }

    private func vin(fromSessionID sessionID: String) -> String? {
        guard let separator = sessionID.firstIndex(of: ":") else { return nil }
        let vin = String(sessionID[..<separator])
        return vin.isEmpty ? nil : vin
    }

    private func page<Value: Decodable>(
        _ data: Value,
        cursor: Int64? = nil,
        requestID: String? = nil
    ) -> FleetAPIPage<Value> {
        FleetAPIPage(
            data: data,
            cursor: cursor,
            cached: false,
            stale: false,
            requestID: requestID
        )
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowedCharacters) ?? value
    }

    private static func currentTimeMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

enum FleetBackend {
    static func makeAPIClient(
        provider: FleetProvider, accessTokenProvider: (any FleetAccessTokenProviding)? = nil
    ) -> any FleetDataLoading {
        let tokens = accessTokenProvider ?? makeAccessTokenStore(provider: provider)
        switch provider {
        case .tessie: return FleetAPIClient(accessTokenProvider: tokens)
        case .teslascope: return TeslascopeFleetDataClient(accessTokenProvider: tokens)
        }
    }

    static func makeDataStore(provider: FleetProvider) -> FleetDataStore {
        FleetDataStore(
            apiClient: FleetSandboxDataClient(liveClient: makeAPIClient(provider: provider)),
            cache: FleetDiskCache(fileName: provider == .tessie ? "fleet-cache.json" : "teslascope-fleet-cache.json"),
            provider: provider
        )
    }

    static func makeDeviceIdentity() -> FleetDeviceIdentity {
        FleetDeviceIdentity()
    }

    static func makeAccessTokenStore(provider: FleetProvider) -> FleetProviderTokenStore {
        FleetProviderTokenStore(provider: provider)
    }
}
