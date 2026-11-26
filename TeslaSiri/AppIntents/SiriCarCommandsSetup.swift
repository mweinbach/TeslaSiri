import FleetKit
import Intents
import OSLog

/// App side of SiriKit Car Commands (handled by the `TeslaSiriCarIntents` extension): the car
/// names Siri should recognize ("Lock Midnight") and the user's Siri permission.
nonisolated enum SiriCarCommandsSetup {
    private static let logger = Logger(subsystem: FleetKitLog.subsystem, category: "SiriCarCommands")

    /// Registers the visible cars' names so Siri can match them without the app name.
    static func updateCarNames(for vehicles: [FleetVehicle]) {
        var seen = Set<String>()
        let names = vehicles
            .filter { !$0.hidden && $0.name != $0.vin }
            .map(\.name)
            .filter { seen.insert($0.lowercased()).inserted }
        INVocabulary.shared().setVocabularyStrings(NSOrderedSet(array: names), of: .carName)
        logger.info("Registered \(names.count, privacy: .public) car names with Siri")
    }

    static func clearCarNames() {
        INVocabulary.shared().removeAllVocabularyStrings()
    }

    static var authorizationStatus: INSiriAuthorizationStatus {
        INPreferences.siriAuthorizationStatus()
    }

    static func requestAuthorization() async -> INSiriAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            // Siri calls back on a background queue.
            INPreferences.requestSiriAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
        logger.notice("Siri authorization status: \(status.rawValue, privacy: .public)")
        return status
    }
}
