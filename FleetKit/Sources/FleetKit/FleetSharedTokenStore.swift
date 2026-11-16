import CryptoKit
import Foundation
import Security

/// Reads and writes the small amount of state shared between the app and the
/// App Intents extension.
///
/// Access tokens live in the shared keychain (both targets declare the same
/// `keychain-access-groups` entitlement). The selected VIN is stored in the App
/// Group's `UserDefaults` because it is not secret.
///
/// The app is the source of truth and mirrors each provider's access token here so
/// the extension can authenticate.
public struct FleetSharedTokenStore: Sendable {
    public static let shared = FleetSharedTokenStore()

    let appGroup: String
    private let readAccessToken: (@Sendable (FleetProvider) -> String?)?
    private static let sessionGenerationKey = "FleetKit.sessionGeneration"

    public init(appGroup: String = FleetKitConfig.appGroupIdentifier) {
        self.appGroup = appGroup
        self.readAccessToken = nil
    }

    init(appGroup: String, readAccessToken: @escaping @Sendable (FleetProvider) -> String?) {
        self.appGroup = appGroup
        self.readAccessToken = readAccessToken
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public var provider: FleetProvider {
        defaults?.string(forKey: "fleet.provider").flatMap(FleetProvider.init(rawValue:)) ?? .tessie
    }

    public func selectProvider(_ newProvider: FleetProvider) {
        guard provider != newProvider else { return }
        defaults?.set(newProvider.rawValue, forKey: "fleet.provider")
        invalidateSession()
    }

    public func accessToken() -> String? { accessToken(for: provider) }

    public func accessToken(for provider: FleetProvider) -> String? {
        if let readAccessToken { return readAccessToken(provider) }
        let keychain = SharedAccessTokenKeychain(provider: provider)
        if let token = try? keychain.load() { return token }

        // Only Tessie used the legacy defaults slot.
        guard provider == .tessie,
              let legacy = defaults?.string(forKey: FleetKitConfig.accessTokenDefaultsKey),
              !legacy.isEmpty else { return nil }
        if (try? keychain.save(legacy)) != nil {
            defaults?.removeObject(forKey: FleetKitConfig.accessTokenDefaultsKey)
        }
        return legacy
    }

    static func fingerprint(for token: String) -> String {
        Data(SHA256.hash(data: Data(token.utf8))).base64EncodedString()
    }

    public func sessionScope(for token: String) -> String {
        sessionScope(fingerprint: Self.fingerprint(for: token))
    }

    public var sessionRevision: String {
        let generation = defaults?.string(forKey: Self.sessionGenerationKey) ?? "initial"
        return "\(appGroup).\(provider.rawValue).\(generation)"
    }

    func sessionScope(fingerprint: String) -> String {
        "\(sessionRevision).\(fingerprint)"
    }

    func invalidateSession() {
        defaults?.set(UUID().uuidString, forKey: Self.sessionGenerationKey)
        FleetWidgetStore(appGroup: appGroup).clear()
    }

    public func save(accessToken: String, for provider: FleetProvider) throws {
        let changed = self.accessToken(for: provider) != accessToken
        try SharedAccessTokenKeychain(provider: provider).save(accessToken)
        if provider == .tessie { defaults?.removeObject(forKey: FleetKitConfig.accessTokenDefaultsKey) }
        if changed, self.provider == provider { invalidateSession() }
    }

    public func clearAccessToken(for provider: FleetProvider) throws {
        try SharedAccessTokenKeychain(provider: provider).delete()
        if provider == .tessie { defaults?.removeObject(forKey: FleetKitConfig.accessTokenDefaultsKey) }
        if self.provider == provider { invalidateSession() }
    }

    private func selectedVINKey(for provider: FleetProvider) -> String {
        provider == .tessie ? FleetKitConfig.selectedVINDefaultsKey : "fleet.teslascope.selectedVIN"
    }

    public func selectedVIN() -> String? {
        let vin = defaults?.string(forKey: selectedVINKey(for: provider))
        return (vin?.isEmpty == false) ? vin : nil
    }

    public func save(selectedVIN: String) {
        defaults?.set(selectedVIN, forKey: selectedVINKey(for: provider))
        FleetWidgetStore.reload()
    }

    public func clearSelectedVIN() {
        defaults?.removeObject(forKey: selectedVINKey(for: provider))
        FleetWidgetStore.reload()
    }
}

private struct SharedAccessTokenKeychain {
    let provider: FleetProvider

    private var account: String {
        provider == .tessie ? FleetKitConfig.sharedAccessTokenKeychainAccount : "teslascopeExtensionAccessToken"
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard
            let data = item as? Data,
            let token = String(data: data, encoding: .utf8),
            !token.isEmpty
        else {
            return nil
        }
        return token
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            attributes.forEach { key, value in
                addQuery[key] = value
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
                guard retryStatus == errSecSuccess else {
                    throw KeychainError(status: retryStatus)
                }
                return
            }
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FleetKitConfig.sharedAccessTokenKeychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

private struct KeychainError: Error {
    let status: OSStatus
}
