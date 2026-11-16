import FleetKit
import Foundation

nonisolated struct FleetProviderTokenStore: FleetAccessTokenProviding, Sendable {
    let provider: FleetProvider
    private let keychain: FleetAccessTokenKeychain

    init(provider: FleetProvider) {
        self.provider = provider
        self.keychain = FleetAccessTokenKeychain(account: provider.rawValue + "AccessToken")
    }

    @concurrent
    func accessToken() async throws -> String {
        guard FleetSharedTokenStore.shared.provider == provider else { throw CancellationError() }
        return try keychain.loadAccessToken()
    }

    func loadAccessToken() throws -> String? {
        do {
            return try keychain.loadAccessToken()
        } catch FleetAPIError.missingAccessToken {
            return nil
        }
    }

    func saveAccessToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FleetAPIError.missingAccessToken
        }
        let previous = try loadAccessToken()
        try keychain.saveAccessToken(trimmed)
        do {
            try FleetSharedTokenStore.shared.save(accessToken: trimmed, for: provider)
        } catch {
            if let previous { try keychain.saveAccessToken(previous) } else { try keychain.deleteAccessToken() }
            throw error
        }
    }

    func deleteAccessToken() throws {
        try FleetSharedTokenStore.shared.clearAccessToken(for: provider)
        try keychain.deleteAccessToken()
    }
}
