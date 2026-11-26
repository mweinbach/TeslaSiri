import Foundation

struct TeslascopeEnvelope<Payload: Decodable>: Decodable {
    let response: Payload
}

/// A Teslascope session is bound to one credential. Its roster maps Wattie's VINs
/// to the separate public identifiers used in Teslascope's vehicle URLs.
public struct TeslascopeClient: Sendable {
    private let session: URLSession
    private let token: String
    private let onUnauthorized: @Sendable () -> Void
    private let validateRequest: @Sendable () throws -> Void
    private let roster = TeslascopeRoster()

    public init(
        session: URLSession = .shared,
        token: String,
        onUnauthorized: @escaping @Sendable () -> Void = {},
        validateRequest: @escaping @Sendable () throws -> Void = {}
    ) {
        self.session = session
        self.token = token
        self.onUnauthorized = onUnauthorized
        self.validateRequest = validateRequest
    }

    public func vehicles() async throws -> [FleetVehicleInfo] {
        try validateRequest()
        let entries = try await roster.load(requiring: nil, fetch: fetchRoster)
        try validateRequest()
        return entries.map(\.vehicle)
    }

    public func publicID(vin: String) async throws -> String {
        try await entry(vin: vin).publicID
    }

    func entry(vin: String) async throws -> TeslascopeVehicleEntry {
        try validateRequest()
        let entries = try await roster.load(requiring: vin, fetch: fetchRoster)
        try validateRequest()
        guard let entry = entries.first(where: { $0.vehicle.vin == vin }) else {
            throw FleetKitError.api(String(localized: "This vehicle is unavailable on the selected Teslascope account.", bundle: .module, comment: "Error when a requested VIN is missing from the Teslascope account"))
        }
        return entry
    }

    private func fetchRoster() async throws -> [TeslascopeVehicleEntry] {
        struct Account: Decodable {
            let id: Int
            let enabled: Bool?
            let vehicleCommands: Bool?
            let chargingCommands: Bool?

            enum CodingKeys: String, CodingKey {
                case id, enabled
                case vehicleCommands = "scope_vehicle_cmds"
                case chargingCommands = "scope_vehicle_charging_cmds"
            }
        }

        let accounts = try await get([Account].self, ["account", "tesla-accounts"])
        var entries: [TeslascopeVehicleEntry] = []
        for account in accounts where account.enabled != false {
            let vehicles = try await get(
                [TeslascopeVehicleRecord].self, ["account", "tesla-account", String(account.id), "vehicles"]
            )
            for vehicle in vehicles {
                guard Self.validComponent(vehicle.publicID) else { throw FleetKitError.badResponse }
                var record = vehicle
                if record.vin == nil {
                    let detail = try await vehicleDetail(publicID: vehicle.publicID)
                    record = try JSONDecoder().decode(
                        TeslascopeVehicleRecord.self, from: JSONSerialization.data(withJSONObject: detail)
                    )
                }
                guard record.publicID == vehicle.publicID, var entry = record.entry else {
                    throw FleetKitError.api(String(localized: "Teslascope did not return a matching vehicle VIN and public ID.", bundle: .module, comment: "Error when Teslascope returns inconsistent vehicle identity fields"))
                }
                entry.vehicle.allowsVehicleCommands = account.vehicleCommands
                entry.vehicle.allowsChargingCommands = account.chargingCommands
                if let index = entries.firstIndex(where: { $0.publicID == entry.publicID || $0.vehicle.vin == entry.vehicle.vin }) {
                    guard entries[index].publicID == entry.publicID, entries[index].vehicle.vin == entry.vehicle.vin else {
                        throw FleetKitError.api(String(localized: "Teslascope returned conflicting identifiers for a vehicle.", bundle: .module, comment: "Error when Teslascope returns conflicting vehicle VIN and public ID"))
                    }
                    // Vehicle URLs can't select which linked account executes a command.
                    if account.vehicleCommands == false { entries[index].vehicle.allowsVehicleCommands = false }
                    if account.chargingCommands == false { entries[index].vehicle.allowsChargingCommands = false }
                } else {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    private func get<Value: Decodable>(_ type: Value.Type, _ components: [String]) async throws -> Value {
        let data = try await request(components)
        return try JSONDecoder().decode(TeslascopeEnvelope<Value>.self, from: data).response
    }

    func vehicleDetail(publicID: String) async throws -> [String: Any] {
        let data = try await request(["vehicle", publicID, "detailed"], allowsUnwrappedSuccess: true)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FleetKitError.badResponse
        }
        // Vehicle details can arrive as a top-level object instead of a status envelope.
        if object["code"] == nil { return object }
        guard let code = object["code"] as? Int, (200..<300).contains(code),
              let detail = object["response"] as? [String: Any] else {
            throw FleetKitError.badResponse
        }
        return detail
    }

    /// Retains the original envelope and HTTP status for the user-requested diagnostics export.
    public func rawRead(_ components: [String]) async throws -> (Data, HTTPURLResponse) {
        try await send(components, method: "GET", query: [], body: nil, timeout: FleetKitConfig.requestTimeout)
    }

    func request(
        _ components: [String],
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        allowsUnwrappedSuccess: Bool = false,
        timeout: TimeInterval = FleetKitConfig.requestTimeout
    ) async throws -> Data {
        let (data, http) = try await send(components, method: method, query: query, body: body, timeout: timeout)
        let header = try? JSONDecoder().decode(TeslascopeResponseStatus.self, from: data)
        let status: Int
        if (200..<300).contains(http.statusCode) {
            if let header {
                status = header.code
            } else {
                guard allowsUnwrappedSuccess else { throw FleetKitError.badResponse }
                return data
            }
        } else {
            status = http.statusCode
        }
        if status == 401 {
            onUnauthorized()
            throw FleetKitError.sessionExpired
        }
        guard (200..<300).contains(status) else {
            throw FleetKitError.api(header?.message ?? String(localized: "Teslascope returned HTTP \(status).", bundle: .module, comment: "Fallback HTTP error message from Teslascope"))
        }
        return data
    }

    static func validComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && component.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95, 126].contains($0)
        }
    }

    private func send(
        _ components: [String], method: String, query: [URLQueryItem], body: Data?, timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        guard !components.isEmpty, components.allSatisfy(Self.validComponent) else { throw FleetKitError.badResponse }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "teslascope.com"
        url.path = "/api/" + components.joined(separator: "/")
        url.queryItems = query.isEmpty ? nil : query
        guard let address = url.url else { throw FleetKitError.badResponse }
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        try Task.checkCancellation()
        try validateRequest()
        let (data, response) = try await session.data(for: request, delegate: TeslascopeRedirectPolicy.shared)
        try validateRequest()
        guard let http = response as? HTTPURLResponse else { throw FleetKitError.badResponse }
        return (data, http)
    }
}

private struct TeslascopeResponseStatus: Decodable {
    let code: Int
    let message: String?

    enum CodingKeys: String, CodingKey { case code, response, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = (try? container.decode(String.self, forKey: .response)) ?? (try? container.decode(String.self, forKey: .message))
    }
}

private final class TeslascopeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static let shared = TeslascopeRedirectPolicy()

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // An API redirect must never repeat a vehicle command or forward this session's token.
        completionHandler(nil)
    }
}

private actor TeslascopeRoster {
    private var entries: [TeslascopeVehicleEntry] = []
    private var expires = ContinuousClock.now
    private var flight: Task<[TeslascopeVehicleEntry], Error>?

    func load(
        requiring vin: String?,
        fetch: @escaping @Sendable () async throws -> [TeslascopeVehicleEntry]
    ) async throws -> [TeslascopeVehicleEntry] {
        if let flight { return try await flight.value }
        if let vin, expires > .now, entries.contains(where: { $0.vehicle.vin == vin }) { return entries }
        let task = Task { try await fetch() }
        flight = task
        defer { flight = nil }
        do {
            entries = try await task.value
            expires = .now + .seconds(30)
            return entries
        } catch {
            entries = []
            throw error
        }
    }
}
