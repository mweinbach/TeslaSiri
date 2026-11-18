import Foundation

public enum FleetProvider: String, CaseIterable, Sendable {
    case tessie
    case teslascope

    public var displayName: String {
        switch self {
        case .tessie: "Tessie"
        case .teslascope: "Teslascope"
        }
    }

    public var tokenSettingsURL: URL {
        let address = switch self {
        case .tessie: "https://dash.tessie.com/settings/api"
        case .teslascope: "https://teslascope.com/developers/applications"
        }
        guard let url = URL(string: address) else { preconditionFailure("Invalid token settings URL.") }
        return url
    }
}

/// Shared configuration for vehicle data providers and cross-process storage.
///
/// `FleetKit` is intentionally self-contained so the App Intents extension can
/// authenticate and access vehicle providers without importing the app's data
/// layer. The app mirrors the current access token into the shared keychain so
/// this module can read it from either process.
public enum FleetKitConfig {
    public static let baseURL: URL = {
        guard let url = URL(string: "https://api.tessie.com") else {
            preconditionFailure("Invalid Tessie API base URL.")
        }
        return url
    }()

    /// App Group shared between the app and the App Intents extension.
    public static let appGroupIdentifier = "group.com.maxweinbach.TeslaSiri"

    /// Legacy UserDefaults key for access tokens (migrated to shared keychain).
    public static let accessTokenDefaultsKey = "fleet.accessToken"

    public static let sharedAccessTokenKeychainService = "com.maxweinbach.TeslaSiri.fleet.shared"
    public static let sharedAccessTokenKeychainAccount = "extensionAccessToken"

    /// Key under which the app stores the currently selected VIN.
    public static let selectedVINDefaultsKey = "fleet.selectedVIN"

    /// Shared sandbox / demo mode keys read by both the app and App Intents extension.
    public static let sandboxModeDefaultsKey = "fleet.sandbox.mode"
    public static let sandboxPresetDefaultsKey = "fleet.sandbox.preset"
    public static let sandboxDemoStateDefaultsKey = "fleet.sandbox.demoState"
    public static let sandboxCommandLogDefaultsKey = "fleet.sandbox.commandLog"

    public static let requestTimeout: TimeInterval = 30
    /// Synchronous vehicle commands can block up to ~90s while the provider wakes a sleeping car.
    public static let commandTimeout: TimeInterval = 95

    /// Request timeout for synchronous vehicle commands sent from the current task.
    ///
    /// Defaults to `requestTimeout` because ordinary App Intents, widgets, and controls only get
    /// ~30 seconds of background runtime; a longer request would be killed by the system instead
    /// of failing with a readable error. `LongRunningIntent` work run through
    /// `performSandboxAwareBackgroundTask` binds this to `commandTimeout`.
    @TaskLocal public static var vehicleCommandTimeout: TimeInterval = requestTimeout
}
