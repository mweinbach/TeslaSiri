import AppIntents
import FleetKit
import SwiftUI
import WidgetKit

struct VehicleWidgetPanel: View {
    var snapshot: FleetWidgetSnapshot
    var topic: VehicleWidgetTopic
    var family: WidgetFamily = .systemSmall
    var message: String?

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryCircular
    }

    var body: some View {
        Group {
            if isAccessory {
                accessoryContent
            } else {
                panelContent
            }
        }
        .privacySensitive()
        .tint(topic == .charging ? .green : .blue)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            HStack(spacing: 6) {
                Label(snapshot.name, systemImage: topic.systemImage)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(intent: actionIntent(.refresh)) {
                    Label("Refresh vehicle", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if family == .systemMedium {
                HStack(alignment: .center, spacing: 20) {
                    headline.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        detail
                        actions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            } else {
                headline
                if family == .systemLarge {
                    Divider()
                    largeDetails
                } else if topic != .overview {
                    detail
                }
                Spacer(minLength: 0)
                actions
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headlineValue)
                .font(.system(family == .systemLarge ? .largeTitle : .title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .widgetAccentable()
            Text(headlineCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        switch topic {
        case .overview:
            Label(snapshot.lockDescription, systemImage: snapshot.locked == false ? "lock.open.fill" : "lock.fill")
                .font(.caption)
        case .charging:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: snapshot.batteryLevel ?? 0, total: 100) {
                    Text(snapshot.chargeLimit.map { "Limit \(Int($0))%" } ?? "Charge limit unavailable")
                }
                .font(.caption2)
                .accessibilityLabel("Battery charge")
                .accessibilityValue(snapshot.batteryLevel.map { "\(Int($0)) percent" } ?? "Unavailable")
                if let power = snapshot.chargerPowerKW, snapshot.isCharging {
                    Text("\(power.formatted(.number.precision(.fractionLength(0...1)))) kW")
                        .font(.caption)
                }
            }
        case .climate:
            Text("Target \(snapshot.temperatureDescription(snapshot.targetTemperature))")
                .font(.caption)
        case .security:
            Text(snapshot.openClosures.map { $0.isEmpty ? "Doors and windows closed" : $0.joined(separator: ", ") } ?? "Closure status unavailable")
                .font(.caption)
                .lineLimit(2)
        }
    }

    private var largeDetails: some View {
        VStack(spacing: 14) {
            infoRow("Range", value: snapshot.rangeDescription, symbol: "car.fill")
            infoRow("Charging", value: snapshot.chargingDescription, symbol: "bolt.fill")
            infoRow("Cabin", value: snapshot.temperatureDescription(snapshot.insideTemperature), symbol: "thermometer.medium")
            infoRow("Doors", value: snapshot.lockDescription, symbol: "lock.fill")
        }
        .font(.subheadline)
    }

    private func infoRow(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        switch topic {
        case .overview:
            HStack(spacing: 8) {
                actionButton("Lock", symbol: "lock.fill", action: .lock, iconOnly: family != .systemLarge)
                actionButton("Climate", symbol: "fan.fill", action: .startClimate, iconOnly: family != .systemLarge)
            }
        case .charging:
            if snapshot.canStartCharging {
                actionButton("Start charging", symbol: "bolt.fill", action: .startCharging)
            } else if snapshot.isCharging, let hours = snapshot.hoursToCharge, hours > 0 {
                Text("\(Int((hours * 60).rounded())) min to limit")
                    .font(.caption.weight(.medium)).lineLimit(1)
            }
        case .climate:
            actionButton("Start climate", symbol: "fan.fill", action: .startClimate)
        case .security:
            actionButton("Lock car", symbol: "lock.fill", action: .lock)
        }
    }

    private func actionButton(_ title: String, symbol: String, action: FleetWidgetAction, iconOnly: Bool = false) -> some View {
        Button(intent: actionIntent(action)) {
            Label(title, systemImage: symbol)
                .labelStyle(WidgetActionLabelStyle(iconOnly: iconOnly))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(action.title)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if snapshot.mode != .live {
                Text(snapshot.mode.shortTitle).fontWeight(.semibold)
            }
            if let message {
                Text(message)
            } else if let updatedAt = snapshot.updatedAt {
                Text(updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .accessibilityLabel("Vehicle data from \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Timestamp unavailable")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var accessoryContent: some View {
        VStack(alignment: family == .accessoryCircular ? .center : .leading, spacing: 2) {
            if family == .accessoryCircular {
                Gauge(value: snapshot.batteryLevel ?? 0, in: 0...100) {
                    Image(systemName: "bolt.fill")
                } currentValueLabel: {
                    Text(snapshot.batteryLevel.map { "\(Int($0))" } ?? "—")
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel("Car battery")
                .accessibilityValue(snapshot.batteryLevel.map { "\(Int($0)) percent" } ?? "Unavailable")
            } else {
                Label(snapshot.name, systemImage: topic.systemImage).font(.caption.weight(.semibold))
                Text(headlineValue + " · " + headlineCaption).font(.headline)
                footer
            }
        }
        .lineLimit(1)
    }

    private var headlineValue: String {
        switch topic {
        case .overview, .charging: snapshot.batteryLevel.map { "\(Int($0.rounded()))%" } ?? "—"
        case .climate: snapshot.temperatureDescription(snapshot.insideTemperature)
        case .security: snapshot.lockDescription
        }
    }

    private var headlineCaption: String {
        switch topic {
        case .overview: snapshot.rangeDescription
        case .charging: snapshot.chargingDescription
        case .climate: snapshot.climateOn.map { $0 ? "Climate on" : "Climate off" } ?? "Climate status unavailable"
        case .security: snapshot.sentryOn.map { $0 ? "Sentry on" : "Sentry off" } ?? "Sentry status unavailable"
        }
    }

    private func actionIntent(_ action: FleetWidgetAction) -> FleetWidgetActionIntent {
        FleetWidgetActionIntent(action: action, vehicle: VehicleEntity(id: snapshot.vin, name: snapshot.name))
    }
}

enum VehicleWidgetTopic: String, CaseIterable, Identifiable {
    case overview, charging, climate, security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Vehicle"
        case .charging: "Charging"
        case .climate: "Cabin Climate"
        case .security: "Vehicle Security"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "car.fill"
        case .charging: "bolt.fill"
        case .climate: "thermometer.medium"
        case .security: "lock.fill"
        }
    }
}

private struct WidgetActionLabelStyle: LabelStyle {
    var iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 5) {
                configuration.icon
                configuration.title.lineLimit(1).minimumScaleFactor(0.75)
            }
        }
    }
}
