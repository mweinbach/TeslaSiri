import FleetKit
import Foundation
import Security

nonisolated struct FleetAccessTokenKeychain: FleetAccessTokenProviding {
    var service: String
    var account: String

    init(service: String = "com.maxweinbach.TeslaSiri.fleet", account: String = "tessieAccessToken") {
        self.service = service
        self.account = account
    }

    func accessToken() async throws -> String {
        try loadAccessToken()
    }

    func loadAccessToken() throws -> String {
        do {
            return try loadAccessToken(includeAccessGroup: true)
        } catch FleetAPIError.missingAccessToken where FleetKeychainAccessGroup.shared != nil {
            let legacy = try loadAccessToken(includeAccessGroup: false)
            try? saveAccessToken(legacy)
            return legacy
        }
    }

    private func loadAccessToken(includeAccessGroup: Bool) throws -> String {
        let queryBase = baseQuery(includeAccessGroup: includeAccessGroup)
        var query = queryBase
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw FleetAPIError.missingAccessToken
        }

        guard status == errSecSuccess else {
            throw FleetAPIError.keychain(status: status)
        }

        guard
            let attributes = item as? [String: Any],
            let data = attributes[kSecValueData as String] as? Data,
            let token = String(data: data, encoding: .utf8),
            !token.isEmpty
        else {
            throw FleetAPIError.missingAccessToken
        }

        // Upgrade legacy WhenUnlocked items so background launches after first unlock can read them.
        let accessible = attributes[kSecAttrAccessible as String] as? String
        if accessible != (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String) {
            _ = SecItemUpdate(
                queryBase as CFDictionary,
                [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary
            )
        }

        return token
    }

    func saveAccessToken(_ token: String) throws {
        let query = baseQuery(includeAccessGroup: true)
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            attributes.forEach { key, value in
                addQuery[key] = value
            }

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                guard retryStatus == errSecSuccess else {
                    throw FleetAPIError.keychain(status: retryStatus)
                }
                return
            }
            guard addStatus == errSecSuccess else {
                throw FleetAPIError.keychain(status: addStatus)
            }
        default:
            throw FleetAPIError.keychain(status: updateStatus)
        }
    }

    func deleteAccessToken() throws {
        let status = SecItemDelete(baseQuery(includeAccessGroup: true) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FleetAPIError.keychain(status: status)
        }
        if FleetKeychainAccessGroup.shared != nil {
            let legacyStatus = SecItemDelete(baseQuery(includeAccessGroup: false) as CFDictionary)
            guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
                throw FleetAPIError.keychain(status: legacyStatus)
            }
        }
    }

    private func baseQuery(includeAccessGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        if includeAccessGroup, let accessGroup = FleetKeychainAccessGroup.shared {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
