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
        let entry = await entry(for: configuration)
        let interval: TimeInterval
        if entry.snapshot?.isClimateStarting() == true {
            // Check back soon so a climate start sent to a sleeping car resolves to on.
            interval = FleetWidgetSnapshot.climateStartWindow / 2
        } else {
            interval = entry.snapshot?.isCharging == true ? 900 : 1800
        }
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(interval)))
    }

    private func entry(for configuration: VehicleWidgetConfiguration) async -> VehicleWidgetEntry {
        do {
            let snapshot = try await FleetWidgetStore.shared.load(vin: configuration.vehicle?.id)
            return VehicleWidgetEntry(date: .now, snapshot: snapshot)
        } catch FleetKitError.notSignedIn {
            return VehicleWidgetEntry(date: .now, message: "Open Wattie to sign in")
        } catch FleetKitError.sessionExpired {
            FleetWidgetStore.shared.clear(reload: false)
            return VehicleWidgetEntry(date: .now, message: "Open Wattie to reconnect")
        } catch {
            return VehicleWidgetEntry(
                date: .now,
                snapshot: FleetWidgetStore.shared.cached(vin: configuration.vehicle?.id),
                message: "Saved data · Unable to refresh"
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
                VStack(alignment: .leading, spacing: 8) {
                    Label("Wattie", systemImage: topic.systemImage)
                        .font(.headline)
                    Text(entry.message ?? "Open Wattie to set up your car")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.snapshot?.vehicleURL)
    }
}
