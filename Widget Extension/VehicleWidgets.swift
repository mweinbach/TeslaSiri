import AppIntents
import FleetKit
import SwiftUI
import WidgetKit

@main
struct VehicleWidgetBundle: WidgetBundle {
    var body: some Widget {
        VehicleOverviewWidget()
        VehicleChargingWidget()
        VehicleClimateWidget()
        VehicleSecurityWidget()
        LockVehicleControl()
        StartClimateControl()
        StartChargingControl()
    }
}

struct VehicleWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Vehicle"
    static let description = IntentDescription("Choose a car for this widget, or leave empty to follow the car selected in Wattie.")

    @Parameter(title: "Vehicle")
    var vehicle: VehicleEntity?

    init() {}
}

struct VehicleWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: FleetWidgetSnapshot?
    var message: String?
}

struct VehicleWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VehicleWidgetEntry {
        VehicleWidgetEntry(date: .now, snapshot: .sample)
    }

    func snapshot(for configuration: VehicleWidgetConfiguration, in context: Context) async -> VehicleWidgetEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: VehicleWidgetConfiguration, in context: Context) async -> Timeline<VehicleWidgetEntry> {
        let nowEntry = await entry(for: configuration)
        var entries = [nowEntry]

        // Schedule a local auto-clear entry when activation confirmation/error feedback expires
        // so the widget transitions cleanly back to resting status without another network call.
        if let snapshot = nowEntry.snapshot,
           let feedback = snapshot.activeFeedback(at: nowEntry.date),
           feedback.expiresAt > nowEntry.date {
            entries.append(
                VehicleWidgetEntry(
                    date: feedback.expiresAt,
                    snapshot: snapshot.withoutFeedback(),
                    message: nowEntry.message
                )
            )
        }

        let interval: TimeInterval
        if nowEntry.snapshot?.isClimateStarting() == true {
            // Check back soon so a climate start sent to a sleeping car resolves to on.
            interval = FleetWidgetSnapshot.climateStartWindow / 2
        } else {
            interval = nowEntry.snapshot?.isCharging == true ? 900 : 1800
        }
        return Timeline(entries: entries, policy: .after(nowEntry.date.addingTimeInterval(interval)))
    }

    private func entry(for configuration: VehicleWidgetConfiguration) async -> VehicleWidgetEntry {
        do {
            let snapshot = try await FleetWidgetStore.shared.load(
                vin: configuration.vehicle?.id,
                maxCacheAge: 5
            )
            return VehicleWidgetEntry(date: .now, snapshot: snapshot)
        } catch FleetKitError.notSignedIn {
            return VehicleWidgetEntry(date: .now, message: String(localized: "Open Wattie to sign in", comment: "Widget status message when user is signed out"))
        } catch FleetKitError.sessionExpired {
            FleetWidgetStore.shared.clear(reload: false)
            return VehicleWidgetEntry(date: .now, message: String(localized: "Open Wattie to reconnect", comment: "Widget status message when the user's session has expired"))
        } catch {
            return VehicleWidgetEntry(
                date: .now,
                snapshot: FleetWidgetStore.shared.cached(vin: configuration.vehicle?.id),
                message: String(localized: "Saved data · Unable to refresh", comment: "Widget footer message when displaying cached data after a refresh failure")
            )
        }
    }
}

struct VehicleOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.maxweinbach.TeslaSiri.vehicle", intent: VehicleWidgetConfiguration.self, provider: VehicleWidgetProvider()) { entry in
            VehicleWidgetContent(entry: entry, topic: .overview)
        }
        .configurationDisplayName("Vehicle")
        .description("Battery, range, and quick controls for your car.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct VehicleChargingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.maxweinbach.TeslaSiri.charging", intent: VehicleWidgetConfiguration.self, provider: VehicleWidgetProvider()) { entry in
            VehicleWidgetContent(entry: entry, topic: .charging)
        }
        .configurationDisplayName("Charging")
        .description("Battery, charging power, and progress toward your charge limit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct VehicleClimateWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.maxweinbach.TeslaSiri.climate", intent: VehicleWidgetConfiguration.self, provider: VehicleWidgetProvider()) { entry in
            VehicleWidgetContent(entry: entry, topic: .climate)
        }
        .configurationDisplayName("Cabin Climate")
        .description("Check cabin temperature and precondition your car before you leave.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct VehicleSecurityWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.maxweinbach.TeslaSiri.security", intent: VehicleWidgetConfiguration.self, provider: VehicleWidgetProvider()) { entry in
            VehicleWidgetContent(entry: entry, topic: .security)
        }
        .configurationDisplayName("Vehicle Security")
        .description("Check locks, Sentry Mode, and open doors or windows. Lock your car with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct VehicleWidgetContent: View {
    var entry: VehicleWidgetEntry
    var topic: VehicleWidgetTopic

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                VehicleWidgetPanel(snapshot: snapshot, topic: topic, family: family, message: entry.message)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            VehicleWidgetBackdrop(snapshot: entry.snapshot, topic: topic)
        }
        .widgetURL(entry.snapshot?.vehicleURL)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: topic.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetPalette.crimson)
                    .frame(width: 24, height: 24)
                    .background(WidgetPalette.crimson.opacity(0.14), in: Circle())
                    .widgetAccentable()
                Text("Wattie")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            Group {
                if let message = entry.message {
                    Text(message)
                } else {
                    Text("Open Wattie to connect your car")
                }
            }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Overview Small", as: .systemSmall) {
    VehicleOverviewWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, snapshot: .sample)
    VehicleWidgetEntry(date: .now.addingTimeInterval(2), snapshot: {
        var s = FleetWidgetSnapshot.sample
        s.actionFeedback = .confirmed(action: .lock)
        return s
    }())
}

#Preview("Overview Medium", as: .systemMedium) {
    VehicleOverviewWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, snapshot: .sample)
    VehicleWidgetEntry(date: .now.addingTimeInterval(2), snapshot: {
        var s = FleetWidgetSnapshot.sample
        s.climateOn = true
        s.actionFeedback = .confirmed(action: .startClimate)
        return s
    }())
}

#Preview("Overview Large", as: .systemLarge) {
    VehicleOverviewWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, snapshot: {
        var s = FleetWidgetSnapshot.sample
        s.chargingState = "Charging"
        s.chargerPowerKW = 11.5
        s.hoursToCharge = 1.25
        s.openClosures = []
        s.actionFeedback = .confirmed(action: .startCharging)
        return s
    }())
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    VehicleOverviewWidget()
} timeline: {
    VehicleWidgetEntry(date: .now, snapshot: .sample)
    VehicleWidgetEntry(date: .now.addingTimeInterval(2), snapshot: {
        var s = FleetWidgetSnapshot.sample
        s.actionFeedback = .confirmed(action: .lock)
        return s
    }())
}
#endif
