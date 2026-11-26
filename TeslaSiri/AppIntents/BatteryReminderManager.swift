import AppIntents
import BackgroundTasks
import FleetKit
import OSLog
import UserNotifications

/// On-device fallback for the "you should charge your car" reminder.
///
/// Registers a `BGAppRefreshTask` that periodically reads the selected
/// vehicle's battery via the shared `FleetIntentService` and posts a local
/// notification when it's low and not charging. The primary path (server
/// webhook → push) is handled elsewhere; this covers the case where the app
/// hasn't received a push recently.
@MainActor
final class BatteryReminderManager {
    static let shared = BatteryReminderManager()

    static let taskIdentifier = "com.maxweinbach.TeslaSiri.batterycheck"
    private let notificationIdentifier = "battery-reminder"
    private let lowBatteryThreshold = 20
    private let checkInterval: TimeInterval = 3 * 60 * 60
    private let logger = Logger(subsystem: FleetKitLog.subsystem, category: "BatteryReminder")

    private init() {}

    /// Must be called during app launch (before launch finishes).
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self.handle(refreshTask)
            }
        }
    }

    /// Requests notification permission (foreground) and schedules the first check.
    func prepare() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        await schedule()
    }

    func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: checkInterval)
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            logger.info("Scheduled next battery check")
        } catch {
            logger.warning("Failed to schedule battery check — \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        logger.notice("Background battery check started")

        let work = Task {
            await schedule()
            await checkBatteryAndNotify()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    func clearNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    func checkBatteryAndNotify() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let service = FleetIntentService.make()
        guard
            let vehicle = try? await service.resolvedVehicle(nil),
            let snapshot = try? await service.batterySnapshotForReminder(for: vehicle, maxAge: checkInterval),
            service.sessionScopeID != nil,
            let battery = snapshot.batteryLevel
        else {
            logger.warning("Battery check skipped — vehicle or snapshot unavailable")
            return
        }

        let isCharging = snapshot.chargingState?.lowercased() == "charging"
        let level = Int(battery.rounded())
        guard !isCharging, level <= lowBatteryThreshold else {
            logger.info("Battery check OK — \(vehicle.name, privacy: .public) at \(level, privacy: .public)%\(isCharging ? " (charging)" : "", privacy: .public)")
            return
        }

        logger.notice("Low battery — \(vehicle.name, privacy: .public) at \(level, privacy: .public)%; posting reminder")
        await postLowBatteryNotification(vin: vehicle.vin, vehicleName: vehicle.name, battery: level)
    }

    private func postLowBatteryNotification(vin: String, vehicleName: String, battery: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Low Battery", comment: "Local notification title when the vehicle battery is low")
        let levelText = FleetKitFormatting.percent(Double(battery))
        content.body = String(
            localized: "\(vehicleName) is at \(levelText). You should charge your car.",
            comment: "Local notification body reminding the user to charge their vehicle"
        )
        content.sound = .default
        content.appEntityIdentifiers = [
            EntityIdentifier(for: VehicleEntity.self, identifier: vin),
            EntityIdentifier(for: VehicleStatusEntity.self, identifier: VehicleStatusEntity.entityID(forVIN: vin))
        ]

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
