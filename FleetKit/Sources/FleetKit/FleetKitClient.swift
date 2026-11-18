import Foundation
import OSLog

public enum FleetKitError: Swift.Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case sessionExpired
    case api(String?)
    case badResponse
    case unsupportedAction(String)

    public var errorDescription: String? {
        String(localized: localizedStringResource)
    }

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            return "Open Wattie and add an access token for your vehicle provider."
        case .sessionExpired:
            return "Your vehicle provider access token is invalid or revoked. Open Wattie to replace it."
        case .api(let message):
            if let message {
                return "\(message)"
            }
            return "Your vehicle provider returned an error."
        case .badResponse:
            return "Your vehicle provider returned an unexpected response."
        case .unsupportedAction(let action):
            return "Your vehicle doesn't support \(action) right now."
        }
    }
}

/// A control parameter value that can be translated to Tessie's command query items.
public enum FleetControlValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    var queryValue: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        }
    }

    fileprivate var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

/// Live wake/sleep status returned by Tessie's sleep-safe `/{vin}/status` endpoint.
public enum FleetVehicleSleepState: String, Sendable, Equatable {
    case awake
    case asleep
    case waitingForSleep = "waiting_for_sleep"

    public var needsWake: Bool {
        self == .asleep || self == .waitingForSleep
    }
}

/// Extension-safe provider routing for App Intents, Spotlight, and widgets.
public struct FleetIntentClient: Sendable {
    private static let sharedRoster = FleetRosterCache()
    private let rosterCache: FleetRosterCache
    private let session: URLSession
    let tokenStore: FleetSharedTokenStore
    let provider: FleetProvider
    private let teslascopeClient: TeslascopeClient?
    @TaskLocal static var validateRequest: (@Sendable (String) throws -> Void)?

    public init(session: URLSession = .shared, tokenStore: FleetSharedTokenStore = .shared) {
        self.session = session
        self.tokenStore = tokenStore
        let provider = tokenStore.provider
        self.provider = provider
        if provider == .teslascope, let token = tokenStore.accessToken(for: provider) {
            let scope = tokenStore.sessionScope(for: token)
            self.teslascopeClient = TeslascopeClient(session: session, token: token, onUnauthorized: {
                if tokenStore.provider == provider, tokenStore.sessionScope(for: token) == scope {
                    tokenStore.invalidateSession()
                }
            }) {
                guard tokenStore.provider == provider,
                      tokenStore.sessionScope(for: token) == scope,
                      tokenStore.accessToken(for: provider) == token else {
                    throw FleetKitError.sessionExpired
                }
                try Self.validateRequest?(token)
            }
        } else {
            self.teslascopeClient = nil
        }
        self.rosterCache = session === URLSession.shared ? Self.sharedRoster : FleetRosterCache()
    }

    private var teslascope: TeslascopeClient? {
        get throws {
            guard tokenStore.provider == provider else { throw FleetKitError.sessionExpired }
            guard provider == .teslascope else { return nil }
            guard let teslascopeClient else { throw FleetKitError.notSignedIn }
            return teslascopeClient
        }
    }

    // MARK: - Reads

    public func vehicles() async throws -> [FleetVehicleInfo] {
        try await directRoster().vehicles
    }

    func vehicles(requiring vin: String?, scope: String) async throws -> [FleetVehicleInfo] {
        try await roster(requiring: vin, scope: scope).vehicles
    }

    func cachedVehicle(vin: String, scope: String) async -> FleetVehicleInfo? {
        await rosterCache.cachedVehicle(vin: vin, scope: scope)
    }

    func invalidateRosterTelemetry(vin: String, scope: String, action: String) async {
        let topic: FleetRosterCache.ChangedTelemetry
        switch action {
        case "charge_start", "charge_stop", "charge_port_door_close", "charge_port_door_open", "set_charge_limit", "set_charging_amps":
            topic = .charge
        case "auto_conditioning_start", "auto_conditioning_stop", "set_temps", "remote_defrost", "set_pet_mode", "set_bioweapon_mode", "set_seat_heat", "set_seat_cool", "steering_wheel_heater":
            topic = .climate
        default:
            return
        }
        await rosterCache.invalidateTelemetry(vin: vin, scope: scope, topic: topic)
    }

    private func directRoster() async throws -> FleetRosterCache.Roster {
        guard tokenStore.provider == provider else { throw FleetKitError.sessionExpired }
        guard let token = tokenStore.accessToken(for: provider) else { throw FleetKitError.notSignedIn }
        let fingerprint = FleetSharedTokenStore.fingerprint(for: token)
        let account = tokenStore.sessionScope(fingerprint: fingerprint)
        let result = try await Self.$validateRequest.withValue({ actual in
            guard actual == token else { throw FleetKitError.sessionExpired }
        }) { try await roster(scope: account) }
        guard tokenStore.sessionScope(fingerprint: fingerprint) == account else {
            throw FleetKitError.sessionExpired
        }
        return result
    }

    private func roster(requiring vin: String? = nil, scope: String) async throws -> FleetRosterCache.Roster {
        try await rosterCache.load(scope: scope, requiring: vin) {
            if let client = try teslascope {
                return FleetRosterCache.Roster(vehicles: try await client.vehicles(), units: TeslascopeClient.displayUnits)
            }
            let response: TessieResults<TessieVehicle> = try await get(
                "/vehicles", query: [URLQueryItem(name: "only_active", value: "true")]
            )
            return FleetRosterCache.Roster(vehicles: response.results.map(\.vehicleInfo), units: response.results.first?.lastState?.units)
        }
    }

    public func snapshot(vin: String) async throws -> FleetSnapshotInfo {
        try await snapshotState(vin: vin).snapshot
    }

    func snapshot(vin: String, topics: [VehicleInfoTopic]) async throws -> FleetSnapshotInfo {
        try await snapshotState(vin: vin, topics: topics).snapshot
    }

    func snapshotAndSoftware(vin: String) async throws -> (snapshot: FleetSnapshotInfo, software: FleetSoftwareInfo) {
        let (snapshot, state) = try await snapshotState(vin: vin)
        return (snapshot, state.software)
    }

    private func snapshotState(
        vin: String,
        topics: [VehicleInfoTopic]? = nil
    ) async throws -> (snapshot: FleetSnapshotInfo, state: TessieObject) {
        if let client = try teslascope {
            let data = try await client.stateData(vin: vin)
            let state = try JSONDecoder().decode(TessieObject.self, from: data)
            return (state.snapshot(vin: vin, tireState: nil, topics: topics), state)
        }
        if let topics, !topics.contains(.tirePressure) {
            let state: TessieObject = try await get("/\(encoded(vin))/state")
            return (state.snapshot(vin: vin, tireState: nil, topics: topics), state)
        }
        async let tireRead: TessieObject = get(
            "/\(encoded(vin))/tire_pressure",
            query: [URLQueryItem(name: "pressure_format", value: "psi")]
        )
        let state: TessieObject = try await get("/\(encoded(vin))/state")
        let tireState: TessieObject?
        do {
            tireState = try await tireRead
        } catch FleetKitError.sessionExpired {
            throw FleetKitError.sessionExpired
        } catch FleetKitError.notSignedIn {
            throw FleetKitError.notSignedIn
        } catch {
            try Task.checkCancellation()
            tireState = nil
        }
        return (state.snapshot(vin: vin, tireState: tireState, topics: topics), state)
    }

    public func user() async throws -> FleetUserInfo {
        try await FleetUserInfo(units: directRoster().units)
    }

    func units(scope: String) async throws -> String? {
        try await roster(scope: scope).units
    }

    public func drives(
        vin: String,
        limit: Int,
        from: Date? = nil,
        to: Date? = nil,
        tag: String? = nil,
        requireCompleteRows: Bool = false
    ) async throws -> [FleetDriveInfo] {
        if let client = try teslascope {
            return try await client.drives(vin: vin, limit: limit, from: from, to: to, tag: tag, requireCompleteRows: requireCompleteRows)
        }
        var query = [
            URLQueryItem(name: "distance_format", value: "mi"),
            URLQueryItem(name: "temperature_format", value: "f"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let from {
            query.append(URLQueryItem(name: "from", value: String(Int64(from.timeIntervalSince1970))))
        }
        if let to {
            query.append(URLQueryItem(name: "to", value: String(Int64(to.timeIntervalSince1970))))
        }
        if let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        let response: TessieResults<TessieObject> = try await get(
            "/\(encoded(vin))/drives",
            query: query
        )
        let drives = response.results.compactMap { $0.drive(vin: vin) }.sorted { $0.startedAt > $1.startedAt }
        if requireCompleteRows, Set(drives.map(\.id)).count != response.results.count { throw FleetKitError.badResponse }
        return drives
    }

    func driveDetails(vin: String, id: String) async throws -> FleetDriveInfo? {
        guard let client = try teslascope else { return nil }
        return try await client.drive(vin: vin, sessionID: id)
    }

    public func drivePath(
        vin: String,
        driveID: String? = nil,
        from: Date,
        to: Date,
        maxPoints: Int = 72
    ) async throws -> [FleetDriveRoutePoint] {
        if let client = try teslascope {
            if let driveID { return try await client.drivePath(vin: vin, sessionID: driveID, maxPoints: maxPoints) }
            return try await client.drivePath(vin: vin, from: from, to: to, maxPoints: maxPoints)
        }
        let fromSec = Int64(from.timeIntervalSince1970)
        let toSec = max(Int64(to.timeIntervalSince1970), fromSec + 1)
        let response: TessieResults<TessiePathSample> = try await get(
            "/\(encoded(vin))/path",
            query: [
                URLQueryItem(name: "from", value: String(fromSec)),
                URLQueryItem(name: "to", value: String(toSec)),
                URLQueryItem(name: "details", value: "true"),
                URLQueryItem(name: "simplify", value: "true")
            ]
        )
        let points = response.results
            .compactMap(\.routePoint)
            .sorted { ($0.timestampMS ?? 0) < ($1.timestampMS ?? 0) }
        guard maxPoints > 1, points.count > maxPoints else {
            return points
        }
        return (0..<maxPoints).map { idx in
            points[idx * (points.count - 1) / (maxPoints - 1)]
        }
    }

    public func charges(
        vin: String,
        limit: Int,
        from: Date? = nil,
        to: Date? = nil,
        requireCompleteRows: Bool = false
    ) async throws -> [FleetChargeInfo] {
        if let client = try teslascope {
            return try await client.charges(vin: vin, limit: limit, from: from, to: to, requireCompleteRows: requireCompleteRows)
        }
        var query = [
            URLQueryItem(name: "distance_format", value: "mi"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let from {
            query.append(URLQueryItem(name: "from", value: String(Int64(from.timeIntervalSince1970))))
        }
        if let to {
            query.append(URLQueryItem(name: "to", value: String(Int64(to.timeIntervalSince1970))))
        }
        let response: TessieResults<TessieObject> = try await get(
            "/\(encoded(vin))/charges",
            query: query
        )
        let charges = response.results.compactMap { $0.charge(vin: vin) }.sorted { $0.startedAt > $1.startedAt }
        if requireCompleteRows, Set(charges.map(\.id)).count != response.results.count { throw FleetKitError.badResponse }
        return charges
    }

    func chargeDetails(vin: String, id: String) async throws -> FleetChargeInfo? {
        guard let client = try teslascope else { return nil }
        return try await client.charge(vin: vin, sessionID: id)
    }

    public func batteryHealth(vin: String) async throws -> FleetBatteryHealthInfo {
        if try teslascope != nil { throw FleetKitError.api("Teslascope does not report battery pack health.") }
        async let battery: TessieObject = get("/\(encoded(vin))/battery")
        var healthObject: TessieObject?
        var healthError: Error?
        do {
            let response: TessieResults<TessieObject> = try await get(
                "/battery_health",
                query: [
                    URLQueryItem(name: "distance_format", value: "mi"),
                    URLQueryItem(name: "only_active", value: "true")
                ]
            )
            healthObject = response.results.first { $0.string("vin") == vin }
        } catch let error as FleetKitError {
            if case .sessionExpired = error { throw error }
            if case .notSignedIn = error { throw error }
            healthError = error
        } catch {
            healthError = error
        }

        var batteryObject: TessieObject?
        do {
            batteryObject = try await battery
        } catch let error as FleetKitError {
            if case .sessionExpired = error { throw error }
            if case .notSignedIn = error { throw error }
            if healthObject == nil {
                throw healthError ?? error
            }
        } catch {
            if healthObject == nil {
                throw healthError ?? error
            }
        }

        return TessieObject.mergedBatteryHealth(vin: vin, health: healthObject, battery: batteryObject)
    }

    public func consumptionSinceCharge(vin: String) async throws -> FleetConsumptionInfo {
        if let client = try teslascope {
            let latest = try await client.charges(vin: vin, limit: 1).first
            return FleetConsumptionInfo(lastChargeAt: latest?.endedAt)
        }
        let response: TessieObject = try await get(
            "/\(encoded(vin))/consumption_since_charge",
            query: [URLQueryItem(name: "distance_format", value: "mi")]
        )
        return response.consumptionSinceCharge
    }

    public func software(vin: String) async throws -> FleetSoftwareInfo {
        if try teslascope != nil { return try await snapshotState(vin: vin).state.software }
        let state: TessieObject = try await get("/\(encoded(vin))/state")
        return state.software
    }

    public func releaseNotes(vin: String, version: String) async throws -> [FleetReleaseNoteInfo] {
        guard !version.isEmpty, version != ".", version != ".." else {
            throw FleetKitError.badResponse
        }
        if let client = try teslascope { return try await client.releaseNotes(vin: vin, version: version) }
        let response: TessieReleaseNotes = try await get("/\(encoded(vin))/release_notes/\(encoded(version))")
        return response.releaseNotes ?? []
    }

    public func controlActions() async throws -> FleetControlActionsInfo {
        if provider == .teslascope { return TeslascopeClient.controlActions }
        return FleetControlActionsInfo(
            actions: [
                "actuate_trunk",
                "auto_conditioning_start",
                "auto_conditioning_stop",
                "charge_port_door_close",
                "charge_port_door_open",
                "charge_start",
                "charge_stop",
                "door_lock",
                "door_unlock",
                "flash_lights",
                "honk_horn",
                "navigation_request",
                "remote_defrost",
                "set_bioweapon_mode",
                "set_pet_mode",
                "set_seat_cool",
                "set_seat_heat",
                "set_sentry_mode",
                "set_temps",
                "steering_wheel_heater",
                "window_control"
            ],
            chargeActions: [
                "charge_port_door_close",
                "charge_port_door_open",
                "charge_start",
                "charge_stop",
                "set_charge_limit",
                "set_charging_amps"
            ],
            schemas: [
                "actuate_trunk": ["which_trunk"],
                "navigation_request": ["value"],
                "remote_defrost": ["on"],
                "set_bioweapon_mode": ["on"],
                "set_charge_limit": ["percent"],
                "set_charging_amps": ["amps"],
                "set_pet_mode": ["on"],
                "set_seat_cool": ["seat", "level"],
                "set_seat_heat": ["seat", "level"],
                "steering_wheel_heater": ["on"],
                "set_sentry_mode": ["on"],
                "set_temps": ["driver_temp", "passenger_temp"],
                "window_control": ["command"]
            ]
        )
    }

    /// Queries Tessie's sleep-safe `/{vin}/status` endpoint without waking the car.
    /// Returns `nil` for Teslascope or when status cannot be determined so callers
    /// can safely fall back to synchronous command execution.
    public func vehicleSleepState(vin: String) async throws -> FleetVehicleSleepState? {
        if try teslascope != nil { return nil }
        do {
            let response: TessieVehicleStatusResponse = try await get("/\(encoded(vin))/status")
            return FleetVehicleSleepState(rawValue: response.status.lowercased())
        } catch FleetKitError.sessionExpired {
            throw FleetKitError.sessionExpired
        } catch FleetKitError.notSignedIn {
            throw FleetKitError.notSignedIn
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    // MARK: - Writes

    public func runControl(
        action: String,
        vin: String,
        params: [String: FleetControlValue],
        waitForCompletion: Bool = true
    ) async throws {
        if let client = try teslascope { return try await client.runControl(action: action, vin: vin, params: params) }
        let command: String
        var query: [URLQueryItem] = []

        switch action {
        case "door_lock":
            command = "lock"
        case "door_unlock":
            command = "unlock"
        case "auto_conditioning_start":
            command = "start_climate"
        case "auto_conditioning_stop":
            command = "stop_climate"
        case "window_control":
            switch params["command"]?.queryValue {
            case "vent":
                command = "vent_windows"
            case "close":
                command = "close_windows"
            default:
                throw FleetKitError.unsupportedAction("that window command")
            }
        case "actuate_trunk":
            command = params["which_trunk"]?.queryValue == "front"
                ? "activate_front_trunk"
                : "activate_rear_trunk"
        case "charge_start":
            command = "start_charging"
        case "charge_stop":
            command = "stop_charging"
        case "charge_port_door_open":
            command = "open_charge_port"
        case "charge_port_door_close":
            command = "close_charge_port"
        case "set_charge_limit":
            command = "set_charge_limit"
            query = requiredQuery("percent", from: params)
        case "set_charging_amps":
            command = "set_charging_amps"
            query = requiredQuery("amps", from: params)
        case "set_seat_heat", "set_seat_cool":
            command = action
            query = requiredQuery("seat", from: params) + requiredQuery("level", from: params)
        case "steering_wheel_heater":
            command = params["on"]?.boolValue == false ? "stop_steering_wheel_heater" : "start_steering_wheel_heater"
        case "set_temps":
            command = "set_temperatures"
            let temperature = params["driver_temp"] ?? params["passenger_temp"]
            guard let temperature else { throw FleetKitError.badResponse }
            query = [URLQueryItem(name: "temperature", value: temperature.queryValue)]
        case "remote_defrost":
            command = params["on"]?.boolValue == false ? "stop_max_defrost" : "start_max_defrost"
        case "set_pet_mode":
            command = "set_climate_keeper_mode"
            query = [URLQueryItem(name: "mode", value: params["on"]?.boolValue == false ? "0" : "2")]
        case "set_bioweapon_mode":
            command = "set_bioweapon_mode"
            query = requiredQuery("on", from: params)
        case "set_sentry_mode":
            command = params["on"]?.boolValue == false ? "disable_sentry" : "enable_sentry"
        case "flash_lights":
            command = "flash"
        case "honk_horn":
            command = "honk"
        case "navigation_request":
            command = "share"
            query = requiredQuery("value", from: params)
            if let locale = params["locale"]?.queryValue, !locale.isEmpty {
                query.append(URLQueryItem(name: "locale", value: locale))
            }
        default:
            throw FleetKitError.unsupportedAction(action)
        }

        if !waitForCompletion {
            query.append(URLQueryItem(name: "wait_for_completion", value: "false"))
        }

        try await postCommand(
            "/\(encoded(vin))/command/\(command)",
            query: query,
            timeout: waitForCompletion ? FleetKitConfig.vehicleCommandTimeout : FleetKitConfig.requestTimeout
        )
    }

    public func installSoftwareUpdate(vin: String, offsetSec: Int) async throws {
        if let client = try teslascope { return try await client.installSoftwareUpdate(vin: vin, offsetSec: offsetSec) }
        try await postCommand(
            "/\(encoded(vin))/command/schedule_software_update",
            query: [URLQueryItem(name: "in_seconds", value: String(max(offsetSec, 0)))]
        )
    }

    public func cancelSoftwareUpdate(vin: String) async throws {
        if try teslascope != nil { throw FleetKitError.api("Teslascope does not support canceling software updates.") }
        try await postCommand("/\(encoded(vin))/command/cancel_software_update")
    }

    // MARK: - Transport

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Value {
        let request = try authorizedRequest(path: path, query: query, method: "GET")
        let data = try await execute(request)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            FleetKitLog.client.error("GET \(Self.logPath(path), privacy: .public) decode failed — \(error.localizedDescription, privacy: .private)")
            throw FleetKitError.badResponse
        }
    }

    private func postCommand(
        _ path: String,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = FleetKitConfig.vehicleCommandTimeout
    ) async throws {
        let request = try authorizedRequest(path: path, query: query, method: "POST", timeout: timeout)
        let data = try await execute(request)
        guard let response = try? JSONDecoder().decode(TessieCommandResponse.self, from: data), response.result else {
            FleetKitLog.client.error("POST \(Self.logPath(path), privacy: .public) command was not accepted")
            throw FleetKitError.api("Tessie did not accept the vehicle command.")
        }
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let path = Self.logPath(request.url?.path(percentEncoded: true) ?? "?")
        let signposter = FleetKitLog.signposter
        let interval = signposter.beginInterval("Tessie request", id: signposter.makeSignpostID(), "\(method, privacy: .public) \(path, privacy: .public)")
        defer { signposter.endInterval("Tessie request", interval) }
        let start = ContinuousClock.now
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FleetKitError.badResponse
            }

            let elapsed = FleetKitLog.milliseconds(since: start)
            FleetKitLog.client.info("\(method, privacy: .public) \(path, privacy: .public) → \(http.statusCode, privacy: .public) in \(elapsed, privacy: .public) ms")

            if http.statusCode == 401 {
                FleetKitLog.client.warning("Received 401 from Tessie — the saved access token is invalid or revoked")
                if tokenStore.provider == .tessie, let active = tokenStore.accessToken(for: .tessie),
                   request.value(forHTTPHeaderField: "Authorization") == "Bearer \(active)" {
                    tokenStore.invalidateSession()
                }
                throw FleetKitError.sessionExpired
            }
            guard (200..<300).contains(http.statusCode) else {
                throw FleetKitError.api(Self.errorMessage(from: data) ?? "Tessie request failed with HTTP \(http.statusCode).")
            }
            return data
        } catch let error as FleetKitError {
            throw error
        } catch {
            let elapsed = FleetKitLog.milliseconds(since: start)
            FleetKitLog.client.error("\(method, privacy: .public) \(path, privacy: .public) failed after \(elapsed, privacy: .public) ms — \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: FleetKitConfig.baseURL, resolvingAgainstBaseURL: false) else {
            throw FleetKitError.badResponse
        }

        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + endpointPath
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else {
            throw FleetKitError.badResponse
        }
        return url
    }

    private func authorizedRequest(
        path: String,
        query: [URLQueryItem],
        method: String,
        timeout: TimeInterval = FleetKitConfig.requestTimeout
    ) throws -> URLRequest {
        guard tokenStore.provider == provider else { throw FleetKitError.sessionExpired }
        guard let token = tokenStore.accessToken(for: provider) else { throw FleetKitError.notSignedIn }
        try Self.validateRequest?(token)
        guard provider == .tessie else { throw FleetKitError.badResponse }
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func requiredQuery(_ key: String, from params: [String: FleetControlValue]) -> [URLQueryItem] {
        guard let value = params[key] else { return [] }
        return [URLQueryItem(name: key, value: value.queryValue)]
    }

    private static func logPath(_ path: String) -> String {
        guard let separator = path.dropFirst().firstIndex(of: "/") else { return path }
        return "/{vin}" + path[separator...]
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONDecoder().decode(TessieObject.self, from: data) else { return nil }
        return object.string("error") ?? object.string("message")
    }

    private func encoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}


extension FleetIntentClient {
    static func spotlightState(_ data: Data, tires: Data?, vin: String) throws -> (FleetSnapshotInfo, FleetSoftwareInfo) {
        let decoder = JSONDecoder()
        let state = try decoder.decode(TessieObject.self, from: data)
        let pressures = try tires.map { try decoder.decode(TessieObject.self, from: $0) }
        return (state.snapshot(vin: vin, tireState: pressures), state.software)
    }

    static func spotlightDrives(_ data: Data, vin: String) throws -> ([FleetDriveInfo], Int) {
        let rows = try JSONDecoder().decode(TessieResults<TessieObject>.self, from: data).results
        return (rows.compactMap { $0.drive(vin: vin) }.sorted { $0.startedAt > $1.startedAt }, rows.count)
    }

    static func spotlightCharges(_ data: Data, vin: String) throws -> ([FleetChargeInfo], Int) {
        let rows = try JSONDecoder().decode(TessieResults<TessieObject>.self, from: data).results
        return (rows.compactMap { $0.charge(vin: vin) }.sorted { $0.startedAt > $1.startedAt }, rows.count)
    }

    static func spotlightNotes(_ data: Data) throws -> [FleetReleaseNoteInfo] {
        guard let notes = try JSONDecoder().decode(TessieReleaseNotes.self, from: data).releaseNotes else {
            throw FleetKitError.badResponse
        }
        return notes
    }
}

private typealias TessieObject = [String: TessieValue]

private struct TessieResults<Value: Decodable>: Decodable {
    let results: [Value]
}

private struct TessieVehicle: Decodable {
    let vin: String
    let lastState: RosterState?

    var vehicleInfo: FleetVehicleInfo {
        var vehicle = FleetVehicleInfo(
            vin: vin,
            displayName: lastState?.displayName,
            carType: lastState?.carType,
            exteriorColor: lastState?.exteriorColor
        )
        vehicle.hasSeatCooling = lastState?.hasSeatCooling
        vehicle.canActuateTrunks = lastState?.canActuateTrunks
        vehicle.canAcceptNavigationRequests = lastState?.canAcceptNavigationRequests
        if let charge = lastState?.charge, let timestamp = charge.int64("timestamp") {
            vehicle.rosterCharge = FleetSnapshotInfo(
                vin: vin,
                batteryLevel: charge.double("battery_level"),
                batteryRangeMiles: charge.double("battery_range"),
                updatedAt: TessieObject.milliseconds(timestamp)
            )
        }
        if let state = lastState, let climate = state.climate, let timestamp = climate.int64("timestamp") {
            let fahrenheit = state.units != "metric"
            func temperature(_ field: String) -> Double? {
                climate.double(field).map { fahrenheit ? $0 * 9 / 5 + 32 : $0 }
            }
            vehicle.rosterClimate = FleetSnapshotInfo(
                vin: vin,
                insideTemp: temperature("inside_temp"),
                outsideTemp: temperature("outside_temp"),
                targetTemp: temperature("driver_temp_setting"),
                hvacOn: climate.bool("is_climate_on") ?? climate.bool("is_auto_conditioning_on"),
                updatedAt: TessieObject.milliseconds(timestamp),
                temperatureInFahrenheit: fahrenheit
            )
        }
        if lastState?.state?.lowercased() == "online" {
            let latestMS = [
                lastState?.climate?.int64("timestamp"),
                lastState?.charge?.int64("timestamp"),
                lastState?.vehicleTimestamp
            ].compactMap { $0 }.map(TessieObject.milliseconds).max()
            if let latestMS {
                vehicle.rosterAwakeObservedAt = Date(timeIntervalSince1970: TimeInterval(latestMS) / 1_000)
            }
        }
        return vehicle
    }

    enum CodingKeys: String, CodingKey {
        case vin
        case lastState = "last_state"
    }
}

private struct RosterState: Decodable {
    let state: String?
    let displayName: String?
    let carType: String?
    let exteriorColor: String?
    let units: String?
    let hasSeatCooling: Bool?
    let canActuateTrunks: Bool?
    let canAcceptNavigationRequests: Bool?
    let charge: TessieObject?
    let climate: TessieObject?
    let vehicleTimestamp: Int64?

    private enum Field: String, CodingKey {
        case state
        case charge = "charge_state", climate = "climate_state", timestamp
        case battery = "battery_level", range = "battery_range"
        case inside = "inside_temp", outside = "outside_temp", target = "driver_temp_setting"
        case climateOn = "is_climate_on", autoConditioning = "is_auto_conditioning_on"
        case displayName = "display_name", vehicleState = "vehicle_state", vehicleName = "vehicle_name"
        case config = "vehicle_config", carType = "car_type", exteriorColor = "exterior_color"
        case seatCooling = "has_seat_cooling", actuateTrunks = "can_actuate_trunks"
        case acceptNavigation = "can_accept_navigation_requests"
        case settings = "gui_settings", temperature = "gui_temperature_units", distance = "gui_distance_units"
    }

    init(from decoder: Decoder) throws {
        let state = try decoder.container(keyedBy: Field.self)
        let vehicle = try? state.nestedContainer(keyedBy: Field.self, forKey: .vehicleState)
        let config = try? state.nestedContainer(keyedBy: Field.self, forKey: .config)
        let settings = try? state.nestedContainer(keyedBy: Field.self, forKey: .settings)
        func string(_ field: Field, in container: KeyedDecodingContainer<Field>?) throws -> String? {
            try container?.decodeIfPresent(TessieValue.self, forKey: field)?.stringValue
        }
        func readings(_ section: Field, fields: [Field]) -> TessieObject? {
            guard let values = try? state.nestedContainer(keyedBy: Field.self, forKey: section) else { return nil }
            var selected: TessieObject = [:]
            for field in fields {
                selected[field.rawValue] = try? values.decodeIfPresent(TessieValue.self, forKey: field)
            }
            return selected
        }
        self.state = try string(.state, in: state)
        charge = readings(.charge, fields: [.timestamp, .battery, .range])
        climate = readings(.climate, fields: [.timestamp, .inside, .outside, .target, .climateOn, .autoConditioning])
        vehicleTimestamp = try? vehicle?.decodeIfPresent(TessieValue.self, forKey: .timestamp)?.int64Value
        displayName = try string(.displayName, in: state) ?? string(.vehicleName, in: vehicle)
        carType = try string(.carType, in: config)
        exteriorColor = try string(.exteriorColor, in: config)
        hasSeatCooling = try? config?.decodeIfPresent(TessieValue.self, forKey: .seatCooling)?.boolValue
        canActuateTrunks = try? config?.decodeIfPresent(TessieValue.self, forKey: .actuateTrunks)?.boolValue
        canAcceptNavigationRequests = try? config?.decodeIfPresent(TessieValue.self, forKey: .acceptNavigation)?.boolValue
        if let temperature = try string(.temperature, in: settings) {
            units = temperature.lowercased().hasPrefix("f") ? "imperial" : "metric"
        } else {
            units = try string(.distance, in: settings).map { $0.lowercased().contains("km") ? "metric" : "imperial" }
        }
    }
}

private struct TessiePathSample: Decodable {
    let latitude: TessieValue?
    let longitude: TessieValue?
    let speed: TessieValue?
    let heading: TessieValue?
    let autopilot: TessieValue?
    let timestamp: TessieValue?

    var routePoint: FleetDriveRoutePoint? {
        guard let latitude = latitude?.doubleValue, let longitude = longitude?.doubleValue else { return nil }
        return FleetDriveRoutePoint(
            latitude: latitude,
            longitude: longitude,
            speedMPH: speed?.doubleValue,
            heading: heading?.doubleValue,
            autopilotState: autopilot?.stringValue,
            timestampMS: timestamp?.int64Value.map(TessieObject.milliseconds)
        )
    }
}

private struct TessieReleaseNotes: Decodable {
    let releaseNotes: [FleetReleaseNoteInfo]?

    enum CodingKeys: String, CodingKey {
        case releaseNotes = "release_notes"
    }
}

private struct TessieCommandResponse: Decodable {
    let result: Bool
}

private struct TessieVehicleStatusResponse: Decodable {
    let status: String
}

private enum TessieValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object(TessieObject)
    case array([TessieValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(TessieObject.self) {
            self = .object(value)
        } else if let value = try? container.decode([TessieValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Tessie value")
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value):
            if let integer = Int64(exactly: value) {
                String(integer)
            } else {
                String(value)
            }
        case .bool(let value): value ? "true" : "false"
        default: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }

    var int64Value: Int64? {
        guard let value = doubleValue,
              value.isFinite,
              value < Double(Int64.max),
              value >= Double(Int64.min) else {
            return nil
        }
        return Int64(value)
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1", "yes", "on": true
            case "false", "0", "no", "off": false
            default: nil
            }
        default: nil
        }
    }

    var objectValue: TessieObject? {
        if case .object(let value) = self { return value }
        return nil
    }
}

private extension Dictionary where Key == String, Value == TessieValue {
    func object(_ key: String) -> TessieObject {
        self[key]?.objectValue ?? [:]
    }

    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func double(_ key: String) -> Double? {
        self[key]?.doubleValue
    }

    func int64(_ key: String) -> Int64? {
        self[key]?.int64Value
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    var usesFahrenheit: Bool {
        let settings = object("gui_settings")
        if let temperature = settings.string("gui_temperature_units")?.lowercased() {
            return temperature.hasPrefix("f")
        }
        if let distance = settings.string("gui_distance_units")?.lowercased() {
            return !distance.contains("km")
        }
        return true
    }

    func displayTemperature(_ celsius: Double?) -> Double? {
        guard let celsius else { return nil }
        return usesFahrenheit ? (celsius * 9 / 5) + 32 : celsius
    }

    func snapshot(vin: String, tireState: TessieObject?, topics: [VehicleInfoTopic]? = nil) -> FleetSnapshotInfo {
        let charge = object("charge_state")
        let climate = object("climate_state")
        let drive = object("drive_state")
        let vehicle = object("vehicle_state")
        let tires = tireState?.tirePressures ?? vehicle.stateTirePressures
        let chargeTime = charge.int64("timestamp").map(Self.milliseconds)
        let climateTime = climate.int64("timestamp").map(Self.milliseconds)
        let driveTime = drive.int64("timestamp").map(Self.milliseconds)
        let vehicleTime = vehicle.int64("timestamp").map(Self.milliseconds)
        let updatedAt: Int64?
        if let topics {
            // An unrelated fresh reading must not make an older requested topic look current.
            updatedAt = topics.compactMap { topic in
                switch topic {
                case .battery, .range, .charging: chargeTime
                case .climate: climateTime
                case .location: driveTime
                case .odometer, .security: vehicleTime
                case .tirePressure: tires?.lastMeasuredAt ?? vehicleTime
                }
            }.min()
        } else {
            updatedAt = [chargeTime, climateTime, driveTime, vehicleTime].compactMap { $0 }.max()
        }

        return FleetSnapshotInfo(
            vin: vin,
            batteryLevel: charge.double("battery_level"),
            batteryRangeMiles: charge.double("battery_range"),
            chargeLimitSOC: charge.double("charge_limit_soc"),
            chargingState: charge.string("charging_state"),
            chargerPowerKW: charge.double("charger_power"),
            chargePortDoorOpen: charge.bool("charge_port_door_open"),
            locked: vehicle.bool("locked"),
            sentryModeOn: vehicle.bool("sentry_mode"),
            chargeRateMPH: charge.double("charge_rate"),
            timeToFullCharge: charge.double("time_to_full_charge"),
            insideTemp: displayTemperature(climate.double("inside_temp")),
            outsideTemp: displayTemperature(climate.double("outside_temp")),
            targetTemp: displayTemperature(climate.double("driver_temp_setting")),
            hvacOn: climate.bool("is_climate_on") ?? climate.bool("is_auto_conditioning_on"),
            latitude: drive.double("latitude"),
            longitude: drive.double("longitude"),
            odometer: vehicle.double("odometer"),
            speed: drive.double("speed"),
            updatedAt: updatedAt,
            climateKeeperMode: climate.string("climate_keeper_mode"),
            defrostMode: climate.string("defrost_mode"),
            tires: tires,
            temperatureInFahrenheit: usesFahrenheit,
            shiftState: drive.string("shift_state"),
            openClosures: vehicle.openClosures,
            seatHeaterLevels: climate.seatHeaterLevels,
            steeringWheelHeaterOn: climate.bool("steering_wheel_heater")
        )
    }

    /// Open doors, windows, frunk, and trunk from `vehicle_state` (Tesla reports
    /// non-zero integers for open closures).
    var openClosures: [String]? {
        let closures: [(key: String, name: String)] = [
            ("df", "Driver door"), ("pf", "Passenger door"),
            ("dr", "Rear left door"), ("pr", "Rear right door"),
            ("ft", "Frunk"), ("rt", "Trunk"),
            ("fd_window", "Driver window"), ("fp_window", "Passenger window"),
            ("rd_window", "Rear left window"), ("rp_window", "Rear right window")
        ]
        let reported = closures.compactMap { closure in
            bool(closure.key).map { (name: closure.name, open: $0) }
        }
        let open = reported.filter(\.open).map(\.name)
        return open.isEmpty && reported.count < closures.count ? nil : open
    }

    /// Seat heater levels (0–3) from `climate_state`, keyed by readable seat name.
    var seatHeaterLevels: [String: Int]? {
        let seats: [(key: String, name: String)] = [
            ("seat_heater_left", "Driver"), ("seat_heater_right", "Passenger"),
            ("seat_heater_rear_left", "Rear left"), ("seat_heater_rear_center", "Rear center"),
            ("seat_heater_rear_right", "Rear right")
        ]
        var levels: [String: Int] = [:]
        for seat in seats {
            if let level = int64(seat.key) {
                levels[seat.name] = Int(level)
            }
        }
        return levels.isEmpty ? nil : levels
    }

    var tirePressures: FleetTirePressuresInfo? {
        let frontLeft = double("front_left")
        let frontRight = double("front_right")
        let rearLeft = double("rear_left")
        let rearRight = double("rear_right")
        guard frontLeft != nil || frontRight != nil || rearLeft != nil || rearRight != nil else { return nil }
        return FleetTirePressuresInfo(
            frontLeftPSI: frontLeft,
            frontRightPSI: frontRight,
            rearLeftPSI: rearLeft,
            rearRightPSI: rearRight,
            lastMeasuredAt: int64("timestamp").map(Self.milliseconds)
        )
    }

    var stateTirePressures: FleetTirePressuresInfo? {
        func psi(_ key: String) -> Double? {
            double(key).map {
                Measurement(value: $0, unit: UnitPressure.bars).converted(to: .poundsForcePerSquareInch).value
            }
        }

        let frontLeft = psi("tpms_pressure_fl")
        let frontRight = psi("tpms_pressure_fr")
        let rearLeft = psi("tpms_pressure_rl")
        let rearRight = psi("tpms_pressure_rr")
        guard frontLeft != nil || frontRight != nil || rearLeft != nil || rearRight != nil else { return nil }
        return FleetTirePressuresInfo(
            frontLeftPSI: frontLeft,
            frontRightPSI: frontRight,
            rearLeftPSI: rearLeft,
            rearRightPSI: rearRight
        )
    }

    func drive(vin: String) -> FleetDriveInfo? {
        guard let rawID = string("id"), let started = int64("started_at") else { return nil }
        let ended = int64("ended_at")
        let startedMS = Self.milliseconds(started)
        let endedMS = ended.map(Self.milliseconds)
        return FleetDriveInfo(
            sessionID: "\(vin):\(rawID)",
            vin: vin,
            distanceMiles: double("odometer_distance"),
            durationMS: endedMS.map { Swift.max($0 - startedMS, 0) },
            avgSpeedMPH: double("average_speed"),
            maxSpeedMPH: double("max_speed"),
            energyUsedKWH: double("energy_used"),
            startedAt: startedMS,
            endedAt: endedMS,
            startAddress: string("starting_location"),
            endAddress: string("ending_location"),
            startLatitude: double("starting_latitude"),
            startLongitude: double("starting_longitude"),
            endLatitude: double("ending_latitude"),
            endLongitude: double("ending_longitude"),
            startingBatteryPercent: int64("starting_battery").map(Int.init),
            endingBatteryPercent: int64("ending_battery").map(Int.init),
            ratedRangeUsedMiles: double("rated_range_used"),
            autopilotDistanceMiles: double("autopilot_distance"),
            insideTempF: double("average_inside_temperature"),
            outsideTempF: double("average_outside_temperature"),
            tag: string("tag")
        )
    }

    func charge(vin: String) -> FleetChargeInfo? {
        guard let rawID = string("id"), let started = int64("started_at") else { return nil }
        let ended = int64("ended_at")
        let startedMS = Self.milliseconds(started)
        let endedMS = ended.map(Self.milliseconds)
        return FleetChargeInfo(
            sessionID: "\(vin):\(rawID)",
            vin: vin,
            startedAt: startedMS,
            endedAt: endedMS,
            location: string("location"),
            latitude: double("latitude"),
            longitude: double("longitude"),
            isSupercharger: bool("is_supercharger") ?? false,
            odometerMiles: double("odometer"),
            energyAddedKWH: double("energy_added"),
            energyUsedKWH: double("energy_used"),
            milesAdded: double("miles_added") ?? double("miles_added_ideal"),
            startingBatteryPercent: int64("starting_battery").map(Int.init),
            endingBatteryPercent: int64("ending_battery").map(Int.init),
            cost: double("cost")
        )
    }

    static func mergedBatteryHealth(
        vin: String,
        health: TessieObject?,
        battery: TessieObject?
    ) -> FleetBatteryHealthInfo {
        let minTempF = battery?.double("module_temp_min").map { ($0 * 9.0 / 5.0) + 32.0 }
        let maxTempF = battery?.double("module_temp_max").map { ($0 * 9.0 / 5.0) + 32.0 }
        let rawHealth = health?.double("health_percent")
        let rawDegradation = health?.double("degradation_percent")
        let computedHealth: Double? = rawHealth ?? rawDegradation.map { Swift.max(0, 100.0 - $0) }
        let computedDegradation: Double? = rawDegradation ?? rawHealth.map { Swift.max(0, 100.0 - $0) }

        return FleetBatteryHealthInfo(
            vin: vin,
            healthPercent: computedHealth,
            degradationPercent: computedDegradation,
            usableCapacityKWH: health?.double("capacity"),
            originalCapacityKWH: health?.double("original_capacity"),
            maxRangeMiles: health?.double("max_range"),
            maxIdealRangeMiles: health?.double("max_ideal_range"),
            odometerMiles: health?.double("odometer"),
            energyRemainingKWH: battery?.double("energy_remaining"),
            lifetimeEnergyUsedKWH: battery?.double("lifetime_energy_used"),
            phantomDrainPercent: battery?.double("phantom_drain_percent"),
            packVoltage: battery?.double("pack_voltage"),
            packCurrentAmps: battery?.double("pack_current"),
            moduleTempMinF: minTempF,
            moduleTempMaxF: maxTempF
        )
    }

    var consumptionSinceCharge: FleetConsumptionInfo {
        FleetConsumptionInfo(
            lastChargeAt: int64("last_charge_at").map(Self.milliseconds),
            distanceDrivenMiles: double("distance_driven"),
            batteryPercentUsed: double("battery_percent_used"),
            batteryPercentUsedByDriving: double("battery_percent_used_by_driving"),
            ratedRangeUsedMiles: double("rated_range_used"),
            ratedRangeUsedByDrivingMiles: double("rated_range_used_by_driving"),
            energyUsedKWH: double("energy_used"),
            energyUsedByDrivingKWH: double("energy_used_by_driving")
        )
    }

    var software: FleetSoftwareInfo {
        let vehicle = object("vehicle_state")
        let update = vehicle.object("software_update")
        let availableVersion = update.string("version")?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let status = update.string("status")
        let unavailableStatuses = ["", "idle", "unknown"]
        let normalizedStatus = status?.lowercased() ?? ""
        let available = availableVersion != nil
            || !unavailableStatuses.contains(normalizedStatus)
        // Tesla reports "available" once the update has downloaded and "scheduled"
        // during the install countdown; both can be (re)scheduled. "downloading",
        // "downloading_wifi_wait", and "installing" can't.
        let installable = available && ["available", "scheduled"].contains(normalizedStatus)
        let currentVersion = vehicle.string("car_version")?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        let expectedSeconds = update.double("expected_duration_sec")

        return FleetSoftwareInfo(
            currentVersion: currentVersion,
            availableVersion: availableVersion,
            updateAvailable: available,
            installable: installable,
            status: status,
            downloadPercent: update.double("download_perc"),
            installPercent: update.double("install_perc"),
            expectedDurationMinutes: expectedSeconds.map { $0 / 60 }
        )
    }

    static func milliseconds(_ value: Int64) -> Int64 {
        value.magnitude < 10_000_000_000 ? value * 1_000 : value
    }
}
