import FleetKit
import Foundation

@MainActor
final class TeslascopeFleetDataClient: FleetDataLoading {
    private let accessTokenProvider: any FleetAccessTokenProviding
    private let session: URLSession
    private typealias Connection = (token: String, scope: String?, client: TeslascopeClient)
    private var connection: Connection?

    init(accessTokenProvider: any FleetAccessTokenProviding, session: URLSession = .shared) {
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    private func transport(writing: Bool = false) async throws -> Connection {
        let shared = FleetSharedTokenStore.shared
        let sandbox = FleetSandboxStore.shared
        let storedCredential = accessTokenProvider is FleetProviderTokenStore
        let revision = shared.sessionRevision
        let mode = sandbox.sessionScope
        if storedCredential, writing, sandbox.mode() != .live { throw CancellationError() }
        let token = try await accessTokenProvider.accessToken()
        let scope = storedCredential ? "\(revision).\(mode)" : nil
        let validate: @Sendable () throws -> Void = {
            try Task.checkCancellation()
            guard storedCredential else { return }
            guard shared.provider == .teslascope, shared.sessionRevision == revision,
                  sandbox.sessionScope == mode, shared.accessToken(for: .teslascope) == token else {
                throw CancellationError()
            }
        }
        try validate()
        if let connection, connection.token == token, connection.scope == scope {
            return connection
        }
        let client = TeslascopeClient(session: session, token: token, validateRequest: validate)
        let next = (token, scope, client)
        connection = next
        return next
    }

    private var supportedCapabilities: FleetCapabilities {
        let actions = TeslascopeClient.controlActions
        return FleetCapabilities(chargeActions: actions.chargeActions, controlActions: actions.actions,
                                 scopes: ["tesla-accounts", "vehicles", "controls"],
                                 software: ["provider": "teslascope", "cancel": false])
    }

    func capabilities() async throws -> FleetAPIPage<FleetCapabilities> {
        page(supportedCapabilities)
    }

    private func roster() async throws -> [FleetVehicle] {
        try await transport().client.vehicles().map { info in
            var permissions = ["read"]
            if info.allowsVehicleCommands != false { permissions.append("vehicle_commands") }
            if info.allowsChargingCommands != false { permissions.append("charging_commands") }
            return FleetVehicle(displayName: info.displayName, permissions: permissions,
                                vehicleTag: info.vehicleTag, vin: info.vin)
        }
    }

    func bootstrap() async throws -> FleetAPIPage<FleetBootstrap> {
        let vehicles = try await roster()
        let user = FleetUser(authType: "personal_access_token", name: "Teslascope", units: TeslascopeClient.displayUnits)
        return page(FleetBootstrap(capabilities: supportedCapabilities, user: user, vehicles: vehicles),
                    cursor: Self.nowMS)
    }

    func changes(since cursor: Int64) async throws -> FleetAPIPage<FleetSyncChanges> {
        let vehicles = try await roster()
        return page(FleetSyncChanges(vehicles: vehicles), cursor: max(Self.nowMS, cursor + 1))
    }

    private func state(vin: String, connection: Connection, refresh: Bool = false) async throws -> TessieJSONObject {
        func read() async throws -> FleetAPIClient.Response<TessieJSONObject> {
            let data = try await connection.client.stateData(vin: vin)
            let state = try await Self.decodeState(data)
            FleetAPIClient.recordDashboardState(data, vin: vin)
            return .init(data: state, requestID: nil)
        }
        if refresh { return try await read().data }
        return try await FleetAPIClient.sharedVehicleState(
            vin: vin, token: connection.token, source: connection.scope ?? "teslascope", load: read
        ).data
    }

    @concurrent
    private static func decodeState(_ data: Data) async throws -> TessieJSONObject {
        try JSONDecoder().decode(TessieVehicleState.self, from: data).fields
    }

    func latestSnapshot(vin: String, includingTires: Bool) async throws -> FleetAPIPage<FleetLatestSnapshot> {
        let state = try await state(vin: vin, connection: transport())
        return page(TessieModelAdapter.snapshot(vin: vin, state: state))
    }

    func activeDrive(vin: String, includeRoute: Bool, routeMaxPoints: Int?) async throws -> FleetAPIPage<FleetActiveDriveSession> {
        let state = try await state(vin: vin, connection: transport())
        // Detailed state includes current speed and position. Recorded route samples belong to completed sessions.
        guard Self.isCurrentObservation(state.object("drive_state")) else {
            return page(FleetActiveDriveSession(active: false, vin: vin))
        }
        return page(TessieModelAdapter.activeDrive(vin: vin, state: state))
    }

    func drives(vin: String, limit: Int?, includeRoute: Bool) async throws -> FleetAPIPage<[FleetDriveSession]> {
        let client = try await transport().client
        let rows = try await client.drives(vin: vin, limit: limit ?? 50)
        var sessions = rows.map { row in
            FleetDriveSession(avgSpeedMPH: row.avgSpeedMPH, distanceMiles: row.distanceMiles, durationMS: row.durationMS,
                             endedAt: row.endedAt, energyUsedKWH: row.energyUsedKWH, maxSpeedMPH: row.maxSpeedMPH,
                             sessionID: row.sessionID, startAddress: row.startAddress, endAddress: row.endAddress,
                             startLatitude: row.startLatitude, startLongitude: row.startLongitude,
                             endLatitude: row.endLatitude, endLongitude: row.endLongitude, startedAt: row.startedAt, vin: vin)
        }
        if includeRoute {
            for index in sessions.indices {
                let drive = sessions[index]
                sessions[index].route = try await route(client: client, vin: vin, sessionID: drive.sessionID,
                                                        start: drive.startedAt, end: drive.endedAt, cap: 500)
            }
        }
        return page(sessions)
    }

    func driveRoute(sessionID: String, startTime: Int64?, endTime: Int64?, limit: Int?, maxPoints: Int?) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        guard let separator = sessionID.firstIndex(of: ":") else { throw FleetKitError.badResponse }
        let vin = String(sessionID[..<separator])
        let start = startTime.map(TessieModelAdapter.milliseconds)
        let end = endTime.map(TessieModelAdapter.milliseconds)
        if let start, let end, end < start { throw FleetAPIError.invalidHistoryRange }
        let client = try await transport().client
        let points = try await route(client: client, vin: vin, sessionID: sessionID, start: start, end: end, cap: maxPoints ?? limit)
        return page(points)
    }

    private func route(client: TeslascopeClient, vin: String, sessionID: String,
                       start: Int64?, end: Int64?, cap: Int?) async throws -> [FleetRoutePoint] {
        let samples = try await client.driveTelemetry(vin: vin, sessionID: sessionID)
        let points = samples.compactMap { sample -> FleetRoutePoint? in
            if let start, sample.timestampMS.map({ $0 >= start }) != true { return nil }
            if let end, sample.timestampMS.map({ $0 <= end }) != true { return nil }
            guard let lat = sample.latitude, let lon = sample.longitude,
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return FleetRoutePoint(latitude: lat, longitude: lon, odometer: sample.odometerMiles,
                                   speed: sample.speedMPH, timestamp: sample.timestampMS, heading: sample.heading)
        }
        guard let cap, points.count > cap else { return points }
        guard cap > 1 else { return Array(points.prefix(max(0, cap))) }
        return (0..<cap).map { points[$0 * (points.count - 1) / (cap - 1)] }
    }

    func chargingSessions(vin: String, limit: Int?) async throws -> FleetAPIPage<[FleetChargeSession]> {
        let connection = try await transport()
        let rows = try await connection.client.charges(vin: vin, limit: limit ?? 50)
        var sessions = rows.map { info in
            FleetChargeSession(batteryLevelEnd: info.endingBatteryPercent.map(Double.init),
                               batteryLevelStart: info.startingBatteryPercent.map(Double.init),
                               cost: info.cost, currency: info.currency, durationMS: info.endedAt.map { $0 - info.startedAt },
                               endedAt: info.endedAt, energyAddedKWH: info.energyAddedKWH, sessionID: info.sessionID,
                               startedAt: info.startedAt, status: info.endedAt == nil ? nil : "Completed", vin: vin)
        }
        do {
            let state = try await state(vin: vin, connection: connection)
            if Self.isCurrentObservation(state.object("charge_state")),
               let active = TessieModelAdapter.activeCharge(vin: vin, state: state) {
                sessions.insert(active, at: 0)
            }
        } catch FleetKitError.sessionExpired { throw FleetKitError.sessionExpired }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation() }
        try Task.checkCancellation()
        return page(Array(sessions.prefix(max(0, limit ?? sessions.count))))
    }

    func softwareUpdate(vin: String, includeReleaseNotes: Bool, refresh: Bool) async throws -> FleetAPIPage<FleetSoftwareUpdate> {
        let connection = try await transport()
        let state = try await state(vin: vin, connection: connection, refresh: refresh)
        var update = TessieModelAdapter.software(from: state)
        if includeReleaseNotes, let version = update.availableVersion ?? update.currentVersion {
            do {
                let notes = try await connection.client.releaseNotes(vin: vin, version: version, staged: update.availableVersion == version)
                update.releaseNotes = notes.map { FleetSoftwareReleaseNote(description: $0.details, subtitle: $0.subtitle, title: $0.title) }
                update.releaseNotesCount = notes.count
            } catch FleetKitError.sessionExpired { throw FleetKitError.sessionExpired }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        return page(update)
    }

    func installSoftwareUpdate(vin: String, offsetSec: Int) async throws -> FleetAPIPage<[String: JSONValue]> {
        try await transport(writing: true).client.installSoftwareUpdate(vin: vin, offsetSec: offsetSec)
        return page(["requested": true])
    }

    func cancelSoftwareUpdate(vin: String) async throws -> FleetAPIPage<[String: JSONValue]> {
        throw FleetKitError.api("Teslascope does not support canceling a software update.")
    }

    func runControl(action: String, vin: String, params: [String: JSONValue]) async throws -> FleetAPIPage<[String: JSONValue]> {
        let client = try await transport(writing: true).client
        try await client.runControl(action: action, vin: vin, params: FleetSandboxDataClient.convertParameters(params))
        return page(["result": true])
    }

    func locations(vin: String, startTime: Int64?, endTime: Int64?, limit: Int?) async throws -> FleetAPIPage<[FleetRoutePoint]> {
        throw FleetKitError.api("Teslascope provides recorded locations for individual drives.")
    }

    func telemetrySeries(vin: String, topic: String?, startTime: Int64?, endTime: Int64?, limit: Int?, maxPoints: Int?, fields: [String]) async throws -> FleetAPIPage<[FleetTelemetrySeriesPoint]> {
        throw FleetKitError.api("Teslascope provides telemetry samples for individual drives.")
    }

    func rawVehicleDataExport(vin: String) async throws -> FleetRawDataExport {
        let client = try await transport().client
        let publicID = try await client.publicID(vin: vin)
        let base = "https://teslascope.com/api"
        var responses: [FleetRawAPIResponse] = []
        for suffix in [[], ["detailed"], ["drives"], ["charges"]] {
            let components = ["vehicle", publicID] + suffix
            let path = "/" + components.joined(separator: "/")
            let start = Self.nowMS
            var response = FleetRawAPIResponse(durationMS: 0, method: "GET", path: path, query: [:], timestamp: start, url: base + path)
            do {
                let (data, http) = try await client.rawRead(components)
                response.statusCode = http.statusCode
                response.cacheControl = http.value(forHTTPHeaderField: "Cache-Control")
                response.requestID = http.value(forHTTPHeaderField: "X-Request-ID")
                (response.body, response.bodyText) = await FleetAPIClient.rawPayload(data, contentType: http.mimeType)
            } catch is CancellationError { throw CancellationError() }
            catch { response.errorMessage = error.localizedDescription }
            try Task.checkCancellation()
            response.durationMS = max(Self.nowMS - start, 0)
            responses.append(response)
        }
        return FleetRawDataExport(apiBaseURL: base, appSchemaVersion: 2, generatedAt: Self.nowMS, responses: responses, vin: vin)
    }

    private func page<Value: Decodable>(_ value: Value, cursor: Int64? = nil) -> FleetAPIPage<Value> {
        FleetAPIPage(data: value, cursor: cursor, cached: false, stale: false, requestID: nil)
    }

    // A freshly downloaded document may contain months-old observations on a sleeping vehicle.
    // Only synthesize an active session from a timestamp within the current polling interval.
    private static func isCurrentObservation(_ section: TessieJSONObject) -> Bool {
        guard let timestamp = section.int64("timestamp") else { return false }
        return (0...60_000).contains(nowMS - TessieModelAdapter.milliseconds(timestamp))
    }

    private static var nowMS: Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}
