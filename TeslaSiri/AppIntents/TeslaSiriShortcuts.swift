import AppIntents
import FleetKit

/// Zero-configuration App Shortcuts so the most common intents are available in
/// Siri, Spotlight, and on the Action button the moment the app is installed.
/// The intents live in the shared `FleetKit` package so the App Intents
/// extension can perform them in the background.
///
/// Apple limits each app to 10 App Shortcuts; less common intents remain
/// available via the Shortcuts app and Spotlight entity/indexing discovery.
nonisolated struct TeslaSiriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetVehicleStatusIntent(),
            phrases: [
                "Check my car in \(.applicationName)",
                "How's my car in \(.applicationName)",
                "Check my car battery in \(.applicationName)",
                "Check \(\.$vehicle) in \(.applicationName)",
                "Show \(.applicationName) status for \(\.$vehicle)"
            ],
            shortTitle: "Vehicle Status",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: LockVehicleIntent(),
            phrases: [
                "Lock \(\.$vehicle) with \(.applicationName)",
                "Lock my car with \(.applicationName)"
            ],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockVehicleIntent(),
            phrases: [
                "Unlock \(\.$vehicle) with \(.applicationName)",
                "Unlock my car with \(.applicationName)"
            ],
            shortTitle: "Unlock",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: [
                "Warm up my car with \(.applicationName)",
                "Warm up \(\.$vehicle) with \(.applicationName)",
                "Heat up my car with \(.applicationName)",
                "Cool down my car with \(.applicationName)",
                "Cool down \(\.$vehicle) with \(.applicationName)",
                "Precondition my car with \(.applicationName)",
                "Precondition \(\.$vehicle) with \(.applicationName)",
                "Start climate in my car with \(.applicationName)",
                "Start climate in \(\.$vehicle) with \(.applicationName)",
                "Turn on climate in my car with \(.applicationName)"
            ],
            shortTitle: "Start Climate",
            systemImageName: "fan.fill"
        )
        AppShortcut(
            intent: StopClimateIntent(),
            phrases: [
                "Stop climate in \(\.$vehicle) with \(.applicationName)",
                "Stop climate in my car with \(.applicationName)",
                "Turn off climate in \(\.$vehicle) with \(.applicationName)",
                "Turn off climate in my car with \(.applicationName)",
                "Turn off my car AC with \(.applicationName)"
            ],
            shortTitle: "Stop Climate",
            systemImageName: "fan.slash.fill"
        )
        AppShortcut(
            intent: VentWindowsIntent(),
            phrases: [
                "Vent \(\.$vehicle) windows with \(.applicationName)",
                "Vent my car windows with \(.applicationName)"
            ],
            shortTitle: "Vent Windows",
            systemImageName: "wind"
        )
        AppShortcut(
            intent: OpenTrunkIntent(),
            phrases: [
                "Open \(\.$vehicle) trunk with \(.applicationName)",
                "Open my car trunk with \(.applicationName)",
                "Open \(\.$vehicle) \(\.$trunk) with \(.applicationName)",
                "Open my car \(\.$trunk) with \(.applicationName)"
            ],
            shortTitle: "Open Trunk",
            systemImageName: "car.rear"
        )
        AppShortcut(
            intent: GetLastDriveIntent(),
            phrases: [
                "Show \(\.$vehicle) last drive in \(.applicationName)",
                "Where did I drive in \(.applicationName)"
            ],
            shortTitle: "Last Drive",
            systemImageName: "map.fill"
        )
        AppShortcut(
            intent: GetSoftwareStatusIntent(),
            phrases: [
                "Does \(\.$vehicle) have an update in \(.applicationName)",
                "Check my car software in \(.applicationName)"
            ],
            shortTitle: "Software Status",
            systemImageName: "arrow.down.circle.fill"
        )
        AppShortcut(
            intent: InstallSoftwareUpdateIntent(),
            phrases: [
                "Update \(\.$vehicle) with \(.applicationName)",
                "Update my car with \(.applicationName)"
            ],
            shortTitle: "Install Update",
            systemImageName: "square.and.arrow.down.fill"
        )
    }
}
