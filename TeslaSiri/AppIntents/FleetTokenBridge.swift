import AppIntents
import FleetKit
import Foundation
import OSLog

/// Mirrors the active provider's access token (and selected VIN) into shared
/// storage so the App Intents extension can authenticate from its own process.
@MainActor
enum FleetTokenBridge {
    private static let logger = Logger(subsystem: FleetKitLog.subsystem, category: "TokenBridge")

    @discardableResult
    static func sync(store: FleetDataStore) async -> Bool {
        let shared = FleetSharedTokenStore.shared
        guard shared.provider == store.provider, !Task.isCancelled else { return false }
        let revision = shared.sessionRevision
        let tokenStore = FleetBackend.makeAccessTokenStore(provider: store.provider)
        let hasLiveToken: Bool

        do {
            let token = try await tokenStore.accessToken()
            guard revision == shared.sessionRevision, !Task.isCancelled else { return false }
            try shared.save(accessToken: token, for: store.provider)
            hasLiveToken = true
            logger.notice("Mirrored access token to shared keychain")
        } catch FleetAPIError.missingAccessToken {
            guard revision == shared.sessionRevision, !Task.isCancelled else { return false }
            try? shared.clearAccessToken(for: store.provider)
            hasLiveToken = false
            logger.warning("No access token stored — cleared shared access token")
        } catch {
            // Do not clear the shared token on transient or locked-keychain errors
            // (e.g. errSecInteractionNotAllowed when woken in the background while locked).
            logger.warning("Skipped access token sync — leaving shared token intact (\(error.localizedDescription, privacy: .public))")
            return false
        }

        if !hasLiveToken || store.loadState == .loaded || store.selectedVehicle != nil {
            syncSelectedVehicle(store: store, forceShortcutRefresh: true)
            await FleetIntentDonations.syncCarSuggestions(for: store.selectedVehicle)
            if hasLiveToken {
                SiriCarCommandsSetup.updateCarNames(for: store.vehicles)
            } else {
                SiriCarCommandsSetup.clearCarNames()
            }
        }
        return hasLiveToken
    }

    static func syncSelectedVehicle(store: FleetDataStore, forceShortcutRefresh: Bool = false) {
        guard FleetSharedTokenStore.shared.provider == store.provider, !Task.isCancelled else { return }
        let vin = store.selectedVehicle?.vin
        guard forceShortcutRefresh || FleetSharedTokenStore.shared.selectedVIN() != vin else { return }

        if let vin {
            FleetSharedTokenStore.shared.save(selectedVIN: vin)
            logger.info("Shared selected VIN set to \(FleetKitLog.vin(vin), privacy: .public)")
        } else {
            FleetSharedTokenStore.shared.clearSelectedVIN()
            logger.info("Cleared shared selected VIN (no vehicle selected)")
        }

        TeslaSiriShortcuts.updateAppShortcutParameters()
    }

    static func clearVehicleSystemData(for vehicles: [FleetVehicle]) async {
        BatteryReminderManager.shared.clearNotification()
        SiriCarCommandsSetup.clearCarNames()
        try? await FleetSpotlightIndexer.deleteAllIndexedEntities()
        await FleetIntentDonations.clearVehicleSuggestions(for: vehicles)
    }

    static func clear(provider: FleetProvider) {
        let shared = FleetSharedTokenStore.shared
        guard shared.provider == provider else { return }
        shared.clearSelectedVIN()
        TeslaSiriShortcuts.updateAppShortcutParameters()
    }
}
