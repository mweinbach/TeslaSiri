import AppIntents
import FleetKit

/// Zero-configuration App Shortcuts so climate preconditioning, status, history,
/// and software updates are available in Siri, Spotlight, and on the Action button
/// the moment the app is installed.
///
/// Other control intents (`LockVehicleIntent`, `UnlockVehicleIntent`, etc.) stay
/// available in the Shortcuts app while natural-language vehicle control routes to
/// Siri AI's `@AppIntent(.tool)` surface (`ControlCarIntent`) or SiriKit Car Commands.
nonisolated struct TeslaSiriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartClimateIntent(),
            phrases: [
                "Warm up my car with \(.applicationName)",
                "Warm up \(\.$vehicle) with \(.applicationName)",
                "Cool down my car with \(.applicationName)",
                "Cool down \(\.$vehicle) with \(.applicationName)",
                "Precondition my car with \(.applicationName)"
            ],
            shortTitle: "Warm Up Car",
            systemImageName: "fanblades.fill"
        )
        AppShortcut(
            intent: GetVehicleStatusIntent(),
            phrases: [
                "Check my car in \(.applicationName)",
                "How's my car in \(.applicationName)",
                "Check \(\.$vehicle) in \(.applicationName)"
            ],
            shortTitle: "Vehicle Status",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: GetDriveDetailsIntent(),
            phrases: [
                "Show my last drive in \(.applicationName)",
                "Show \(\.$vehicle) last drive in \(.applicationName)"
            ],
            shortTitle: "Last Drive",
            systemImageName: "map.fill"
        )
        AppShortcut(
            intent: GetChargeDetailsIntent(),
            phrases: [
                "Show my last charge in \(.applicationName)",
                "Show \(\.$vehicle) last charge in \(.applicationName)"
            ],
            shortTitle: "Last Charge",
            systemImageName: "bolt.car.fill"
        )
        AppShortcut(
            intent: GetBatteryHealthIntent(),
            phrases: [
                "Check my battery health in \(.applicationName)",
                "Check \(\.$vehicle) battery health in \(.applicationName)"
            ],
            shortTitle: "Battery Health",
            systemImageName: "battery.100percent.bolt"
        )
        AppShortcut(
            intent: GetSoftwareStatusIntent(),
            phrases: [
                "Check my car software in \(.applicationName)",
                "Does \(\.$vehicle) have an update in \(.applicationName)"
            ],
            shortTitle: "Software Update",
            systemImageName: "arrow.down.circle.fill"
        )
        AppShortcut(
            intent: GetReleaseNotesIntent(),
            phrases: [
                "Read my car release notes in \(.applicationName)",
                "Read \(\.$vehicle) release notes in \(.applicationName)"
            ],
            shortTitle: "Release Notes",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: InstallSoftwareUpdateIntent(),
            phrases: [
                "Update my car with \(.applicationName)",
                "Update \(\.$vehicle) with \(.applicationName)"
            ],
            shortTitle: "Install Update",
            systemImageName: "square.and.arrow.down.fill"
        )
    }
}

