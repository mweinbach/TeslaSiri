import FleetKit
import Foundation
import Observation
import UserNotifications

nonisolated struct FleetWebhookNotificationContent: Codable, Equatable, Sendable {
    var body: String?
    var category: String?
    var sound: String?
    var title: String?
}

nonisolated struct FleetWebhookNotificationPayload: Codable, Equatable, Sendable {
    var id: String?
    var createdAt: Int64?
    var data: [String: JSONValue]
    var deviceID: String?
    var event: String
    var notification: FleetWebhookNotificationContent?
    var platform: String?
    var timestamp: Int64?
    var vin: String?
    var vehicleName: String?

    var notificationTitle: String {
        if let title = notification?.title, !title.isEmpty {
            return title
        }
        return event
            .split(separator: ".")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var notificationBody: String {
        if let body = notification?.body, !body.isEmpty {
            return body
        }

        if let vehicleName, !vehicleName.isEmpty {
            return "\(vehicleName) reported \(event)."
        }

        if let vin, !vin.isEmpty {
            return "Vehicle \(String(vin.suffix(6))) reported \(event)."
        }

        return "A fleet event was received."
    }

    var notificationIdentifier: String {
        if let id, !id.isEmpty {
            return id
        }

        let parts = [event, vin, timestamp.map(String.init), createdAt.map(String.init)].compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: ":")
        }

        return UUID().uuidString
    }

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
        case data
        case deviceID = "device_id"
        case event
        case notification
        case platform
        case timestamp
        case title
        case vin
        case vehicleName = "vehicle_name"
    }

    init(
        id: String? = nil,
        event: String,
        vin: String? = nil,
        vehicleName: String? = nil,
        title: String? = nil,
        body: String? = nil,
        timestamp: Int64? = nil,
        createdAt: Int64? = nil,
        deviceID: String? = nil,
        platform: String? = nil,
        data: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.data = data
        self.deviceID = deviceID
        self.event = event
        self.notification = FleetWebhookNotificationContent(body: body, category: event, sound: "default", title: title)
        self.platform = platform
        self.timestamp = timestamp
        self.vin = vin
        self.vehicleName = vehicleName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        data = try container.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        event = try container.decode(String.self, forKey: .event)
        notification = try container.decodeIfPresent(FleetWebhookNotificationContent.self, forKey: .notification)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp) ?? createdAt
        vin = try container.decodeIfPresent(String.self, forKey: .vin)
        vehicleName = try container.decodeIfPresent(String.self, forKey: .vehicleName)

        if notification == nil {
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            let body = try container.decodeIfPresent(String.self, forKey: .body)
            if title != nil || body != nil {
                notification = FleetWebhookNotificationContent(body: body, category: event, sound: "default", title: title)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(deviceID, forKey: .deviceID)
        try container.encode(event, forKey: .event)
        try container.encodeIfPresent(notification, forKey: .notification)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(vin, forKey: .vin)
        try container.encodeIfPresent(vehicleName, forKey: .vehicleName)
        try container.encodeIfPresent(notification?.title, forKey: .title)
        try container.encodeIfPresent(notification?.body, forKey: .body)
    }

    init(userInfo: [AnyHashable: Any]) throws {
        let normalized = Self.normalizedJSONObject(from: userInfo) as? [String: Any] ?? [:]
        let payload = normalized["fleet"] as? [String: Any] ?? normalized
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        self = try JSONDecoder().decode(FleetWebhookNotificationPayload.self, from: payloadData)
    }

    var userInfo: [AnyHashable: Any] {
        var payload: [String: Any] = [
            "event": event,
            "data": data.mapValues(\.foundationValue)
        ]

        payload["id"] = id
        payload["created_at"] = createdAt
        payload["device_id"] = deviceID
        if let notification {
            var value: [String: Any] = [:]
            value["body"] = notification.body
            value["category"] = notification.category
            value["sound"] = notification.sound
            value["title"] = notification.title
            payload["notification"] = value
        }
        payload["platform"] = platform
        payload["timestamp"] = timestamp
        payload["vin"] = vin
        payload["vehicle_name"] = vehicleName

        return ["fleet": payload]
    }

    private static func normalizedJSONObject(from value: Any) -> Any {
        switch value {
        case let dictionary as [AnyHashable: Any]:
            var normalized: [String: Any] = [:]
            for (key, value) in dictionary {
                normalized[String(describing: key)] = normalizedJSONObject(from: value)
            }
            return normalized
        case let dictionary as [String: Any]:
            return dictionary.mapValues { normalizedJSONObject(from: $0) }
        case let array as [Any]:
            return array.map { normalizedJSONObject(from: $0) }
        case let value as String:
            return value
        case let value as NSNumber:
            return value
        case _ as NSNull:
            return NSNull()
        default:
            return String(describing: value)
        }
    }
}

enum FleetNotificationError: Error, LocalizedError {
    case notificationsNotAuthorized

    var errorDescription: String? {
        switch self {
        case .notificationsNotAuthorized:
            return "Notifications are not authorized for this app."
        }
    }
}

@MainActor
final class FleetNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func scheduleNotification(for payload: FleetWebhookNotificationPayload) async throws {
        let settings = await center.notificationSettings()
        guard Self.canPresentNotifications(settings.authorizationStatus) else {
            throw FleetNotificationError.notificationsNotAuthorized
        }

        let content = UNMutableNotificationContent()
        content.title = payload.notificationTitle
        content.body = payload.notificationBody
        content.sound = settings.soundSetting == .enabled ? .default : nil
        content.categoryIdentifier = "fleet.webhook"
        content.userInfo = payload.userInfo

        let request = UNNotificationRequest(
            identifier: payload.notificationIdentifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private static func canPresentNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

@MainActor
@Observable
final class FleetNotificationWebhookStore {
    @ObservationIgnored private let apiClient: FleetAPIClient
    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private let deviceIdentity: FleetDeviceIdentity

    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var configuredCallbackURL: URL?
    private(set) var deviceID = "--"
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var lastActionMessage = "Not run"
    private(set) var lastErrorMessage: String?
    private(set) var lastRequestID: String?
    private(set) var webhooks: [FleetDeviceNotificationWebhook] = []

    var draftCallbackURLString = ""

    var activeWebhooks: [FleetDeviceNotificationWebhook] {
        webhooks.filter(\.enabled)
    }

    var authorizationStatusDescription: String {
        switch authorizationStatus {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .ephemeral:
            return "Ephemeral"
        case .notDetermined:
            return "Not determined"
        case .provisional:
            return "Provisional"
        case nil:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }

    convenience init() {
        self.init(
            apiClient: FleetAPIClient(accessTokenProvider: FleetBackend.makeAccessTokenStore(provider: .tessie)),
            deviceIdentity: FleetBackend.makeDeviceIdentity(),
            center: .current()
        )
    }

    init(apiClient: FleetAPIClient, deviceIdentity: FleetDeviceIdentity, center: UNUserNotificationCenter) {
        self.apiClient = apiClient
        self.deviceIdentity = deviceIdentity
        self.center = center
    }

    func refresh(includeDisabled: Bool = true) async {
        guard !isLoading else {
            return
        }

        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            deviceID = try deviceIdentity.deviceID()
            configuredCallbackURL = Self.configuredCallbackURL(forDeviceID: deviceID)
            if draftCallbackURLString.isEmpty, let configuredCallbackURL {
                draftCallbackURLString = configuredCallbackURL.absoluteString
            }
            await refreshAuthorizationStatus()

            let page = try await apiClient.notificationWebhooks(forDeviceID: deviceID, includeDisabled: includeDisabled)
            webhooks = Self.normalizedWebhooks(page.data)
            lastRequestID = page.requestID
            lastActionMessage = "Loaded \(webhooks.count) notification hooks."
        } catch {
            lastErrorMessage = error.localizedDescription
            lastActionMessage = error.localizedDescription
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            lastErrorMessage = nil
            lastActionMessage = granted ? "Notifications authorized." : "Notifications were not authorized."
            return granted
        } catch {
            lastErrorMessage = error.localizedDescription
            lastActionMessage = error.localizedDescription
            return false
        }
    }

    func ensureWebhook(capabilities: FleetCapabilities?, vins: [String]) async {
        guard !isMutating else {
            return
        }

        await refreshAuthorizationStatus()
        guard Self.canPresentNotifications(authorizationStatus) else {
            lastErrorMessage = FleetNotificationError.notificationsNotAuthorized.localizedDescription
            lastActionMessage = FleetNotificationError.notificationsNotAuthorized.localizedDescription
            return
        }

        do {
            let deviceID = try resolvedDeviceID()
            let callbackURL = try resolvedCallbackURL(forDeviceID: deviceID)
            let events = Self.defaultEvents(from: capabilities)
            let normalizedVINs = Self.normalizedStrings(vins)
            let existingWebhook = webhooks.first { $0.url == callbackURL }

            isMutating = true
            defer { isMutating = false }

            let page: FleetAPIPage<FleetDeviceNotificationWebhook>
            if let existingWebhook {
                page = try await apiClient.updateNotificationWebhook(
                    forDeviceID: deviceID,
                    id: existingWebhook.id,
                    request: FleetDeviceNotificationWebhookUpdateRequest(
                        url: callbackURL,
                        events: events,
                        vins: normalizedVINs,
                        description: "TeslaSiri iOS notifications",
                        deviceName: "TeslaSiri iOS",
                        enabled: true,
                        platform: "ios"
                    )
                )
            } else {
                page = try await apiClient.createNotificationWebhook(
                    forDeviceID: deviceID,
                    request: FleetDeviceNotificationWebhookCreateForDeviceRequest(
                        url: callbackURL,
                        events: events,
                        vins: normalizedVINs,
                        description: "TeslaSiri iOS notifications",
                        deviceName: "TeslaSiri iOS",
                        enabled: true,
                        platform: "ios"
                    )
                )
            }

            upsertWebhook(page.data)
            lastErrorMessage = nil
            lastRequestID = page.requestID
            lastActionMessage = existingWebhook == nil ? "Created notification hook." : "Updated notification hook."
        } catch {
            lastErrorMessage = error.localizedDescription
            lastActionMessage = error.localizedDescription
        }
    }

    func setWebhook(_ webhook: FleetDeviceNotificationWebhook, enabled: Bool) async {
        await updateWebhook(
            webhook,
            request: FleetDeviceNotificationWebhookUpdateRequest(enabled: enabled),
            successMessage: enabled ? "Enabled notification hook." : "Disabled notification hook."
        )
    }

    func refreshEvents(for webhook: FleetDeviceNotificationWebhook, capabilities: FleetCapabilities?) async {
        await updateWebhook(
            webhook,
            request: FleetDeviceNotificationWebhookUpdateRequest(events: Self.defaultEvents(from: capabilities)),
            successMessage: "Updated notification hook events."
        )
    }

    func testWebhook(_ webhook: FleetDeviceNotificationWebhook, event: String = FleetNotificationEvent.driveStarted, vin: String? = nil) async {
        guard !isMutating else {
            return
        }

        do {
            let deviceID = try resolvedDeviceID()
            isMutating = true
            defer { isMutating = false }

            let page = try await apiClient.testNotificationWebhook(
                forDeviceID: deviceID,
                id: webhook.id,
                request: FleetDeviceNotificationWebhookTestRequest(event: event, vin: vin)
            )
            lastErrorMessage = page.data.ok ? nil : page.data.error
            lastRequestID = page.requestID
            lastActionMessage = page.data.ok ? "Test notification hook delivered." : "Test failed: \(page.data.error ?? "unknown error")"
            await refresh(includeDisabled: true)
        } catch {
            lastErrorMessage = error.localizedDescription
            lastActionMessage = error.localizedDescription
        }
    }

    func deleteWebhook(_ webhook: FleetDeviceNotificationWebhook) async {
        guard !isMutating else {
            return
        }

        do {
            let deviceID = try resolvedDeviceID()
            isMutating = true
            defer { isMutating = false }

            let page = try await apiClient.deleteNotificationWebhook(forDeviceID: deviceID, id: webhook.id)
            webhooks.removeAll { $0.id == webhook.id }
            lastErrorMessage = nil
            lastRequestID = page.requestID
            lastActionMessage = "Deleted notification hook."
        } catch {
            lastErrorMessage = error.localizedDescription
            lastActionMessage = error.localizedDescription
        }
    }

    func recordLocalNotificationResult(_ message: String, error: String? = nil) {
        lastActionMessage = message
        lastErrorMessage = error
    }

    func reset() {
        authorizationStatus = nil
        configuredCallbackURL = nil
        deviceID = "--"
        isLoading = false
        isMutating = false
        lastActionMessage = "Not run"
        lastErrorMessage = nil
        lastRequestID = nil
        webhooks = []
    }

    private func updateWebhook(_ webhook: FleetDeviceNotificationWebhook, request: FleetDeviceNotificationWebhookUpdateRequest, successMessage: String) async {
        guard !isMutating else {
            return
        }

        do {
            let deviceID = try resolvedDeviceID()
            isMutating = true
            defer { isMutating = false }

            let page = try await apiClient.updateNotificationWebhook(forDeviceID: deviceID, id: webhook.id, request: request)
            upsertWebhook(page.data)
            lastErrorMessage = nil
            lastRequestID = page.requestID
            lastActionMessage = successMessage
        } catch {
            lastErrorMessage = error.localizedDescription
            lastActionMessage = error.localizedDescription
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    private func resolvedDeviceID() throws -> String {
        let resolvedDeviceID = try deviceIdentity.deviceID()
        deviceID = resolvedDeviceID
        return resolvedDeviceID
    }

    private func resolvedCallbackURL(forDeviceID deviceID: String) throws -> URL {
        if let url = URL(string: draftCallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" {
            return url
        }
        if let configuredCallbackURL = Self.configuredCallbackURL(forDeviceID: deviceID) {
            return configuredCallbackURL
        }
        throw FleetNotificationWebhookError.missingCallbackURL
    }

    private func upsertWebhook(_ webhook: FleetDeviceNotificationWebhook) {
        var updatedWebhooks = webhooks.filter { $0.id != webhook.id }
        updatedWebhooks.append(webhook)
        webhooks = Self.normalizedWebhooks(updatedWebhooks)
    }

    private static func configuredCallbackURL(forDeviceID deviceID: String) -> URL? {
        let bundle = Bundle.main
        let encodedDeviceID = deviceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceID

        if let template = bundle.object(forInfoDictionaryKey: "FleetNotificationWebhookURLTemplate") as? String,
           !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let value = template
                .replacingOccurrences(of: "{deviceID}", with: deviceID)
                .replacingOccurrences(of: "{deviceIDURL}", with: encodedDeviceID)
            return URL(string: value)
        }

        if let baseURLString = bundle.object(forInfoDictionaryKey: "FleetNotificationWebhookBaseURL") as? String,
           let baseURL = URL(string: baseURLString),
           !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseURL.appendingPathComponent(encodedDeviceID)
        }

        return nil
    }

    private static func canPresentNotifications(_ status: UNAuthorizationStatus?) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined, nil:
            return false
        @unknown default:
            return false
        }
    }

    private static func defaultEvents(from capabilities: FleetCapabilities?) -> [String] {
        let advertisedEvents = capabilities?.notificationEvents ?? []
        let events = advertisedEvents.isEmpty ? FleetNotificationEvent.supportedEvents : advertisedEvents
        return normalizedStrings(events.filter { $0 != FleetNotificationEvent.all })
    }

    private static func normalizedWebhooks(_ webhooks: [FleetDeviceNotificationWebhook]) -> [FleetDeviceNotificationWebhook] {
        webhooks.map { webhook in
            var webhook = webhook
            webhook.description = normalizedString(webhook.description)
            webhook.deviceID = normalizedString(webhook.deviceID) ?? ""
            webhook.deviceName = normalizedString(webhook.deviceName)
            webhook.events = normalizedStrings(webhook.events)
            webhook.platform = normalizedString(webhook.platform)
            webhook.secret = normalizedString(webhook.secret)
            webhook.vins = normalizedStrings(webhook.vins)
            return webhook
        }
        .sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled {
                return lhs.enabled && !rhs.enabled
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func normalizedStrings(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedString))).sorted()
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum FleetNotificationWebhookError: Error, LocalizedError {
    case missingCallbackURL

    var errorDescription: String? {
        switch self {
        case .missingCallbackURL:
            return "Enter an HTTPS notification webhook callback URL before creating a hook."
        }
    }
}

private extension JSONValue {
    nonisolated var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.foundationValue)
        case .array(let value):
            return value.map(\.foundationValue)
        case .null:
            return NSNull()
        }
    }
}
