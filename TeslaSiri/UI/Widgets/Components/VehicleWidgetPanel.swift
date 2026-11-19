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

    private var accentColor: Color {
        switch topic {
        case .overview:
            snapshot.isCharging ? .green : .blue
        case .charging:
            snapshot.isCharging ? .green : ((snapshot.batteryLevel ?? 50) <= 20 ? .orange : .green)
        case .climate:
            snapshot.climateOn == true || snapshot.isClimateStarting() ? .blue : .cyan
        case .security:
            snapshot.locked == false ? .orange : .blue
        }
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
        .tint(accentColor)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            header

            if family == .systemMedium {
                HStack(alignment: .center, spacing: 16) {
                    headline
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                } else if topic == .charging {
                    chargingBar
                } else if topic == .security {
                    detail
                }
                Spacer(minLength: 0)
                actions
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: topic.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .widgetAccentable()
            Text(snapshot.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button(intent: actionIntent(.refresh)) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh vehicle")
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headlineValue)
                .font(.system(family == .systemLarge ? .largeTitle : .title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(headlineColor)
                .widgetAccentable()
            Text(headlineCaption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineColor: Color {
        if topic == .security, snapshot.locked == false { return .orange }
        if topic == .charging, snapshot.isCharging { return .green }
        return .primary
    }

    private var chargingBar: some View {
        let level = max(0, min((snapshot.batteryLevel ?? 0) / 100.0, 1))
        let limit = snapshot.chargeLimit.map { max(0, min($0 / 100.0, 1)) }
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = proxy.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(accentColor.gradient)
                        .frame(width: max(height, width * level))
                    if let limit {
                        Capsule()
                            .fill(.primary.opacity(0.65))
                            .frame(width: 2, height: height + 4)
                            .offset(x: min(max(width * limit - 1, 0), width - 2))
                    }
                }
            }
            .frame(height: 8)

            HStack {
                if let limitVal = snapshot.chargeLimit {
                    Text("Limit \(Int(limitVal.rounded()))%")
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                if let power = snapshot.chargerPowerKW, snapshot.isCharging, power > 0 {
                    Text("\(power.formatted(.number.precision(.fractionLength(0...1)))) kW")
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery charge")
        .accessibilityValue(snapshot.batteryLevel.map { "\(Int($0)) percent" } ?? "Unavailable")
    }

    @ViewBuilder
    private var detail: some View {
        switch topic {
        case .overview:
            Label(snapshot.lockDescription, systemImage: snapshot.locked == false ? "lock.open.fill" : "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(snapshot.locked == false ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        case .charging:
            chargingBar
        case .climate:
            Label("Target \(snapshot.temperatureDescription(snapshot.targetTemperature))", systemImage: "thermometer.medium")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .security:
            Text(snapshot.openClosures.map { $0.isEmpty ? "All closed" : $0.joined(separator: ", ") } ?? "Status unavailable")
                .font(.caption.weight(.medium))
                .foregroundStyle(snapshot.openClosures?.isEmpty == false ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }

    private var largeDetails: some View {
        VStack(spacing: 12) {
            infoRow("Range", value: snapshot.rangeDescription, symbol: "road.lanes")
            infoRow("Charging", value: snapshot.chargingDescription, symbol: "bolt.fill")
            infoRow("Cabin", value: snapshot.temperatureDescription(snapshot.insideTemperature), symbol: "thermometer.medium")
            infoRow("Doors", value: snapshot.lockDescription, symbol: snapshot.locked == false ? "lock.open.fill" : "lock.fill")
        }
        .font(.subheadline)
    }

    private func infoRow(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        switch topic {
        case .overview:
            if snapshot.allowsVehicleCommands != false {
                HStack(spacing: 8) {
                    actionButton("Lock", symbol: "lock.fill", action: .lock, iconOnly: family != .systemLarge)
                    actionButton("Climate", symbol: "fan.fill", action: .startClimate, iconOnly: family != .systemLarge)
                }
            }
        case .charging:
            if snapshot.canStartCharging {
                actionButton("Start Charging", symbol: "bolt.fill", action: .startCharging)
            } else if snapshot.isCharging, let hours = snapshot.hoursToCharge, hours > 0 {
                Label("\(Int((hours * 60).rounded())) min to limit", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        case .climate:
            if snapshot.allowsVehicleCommands != false {
                actionButton(
                    snapshot.isClimateStarting() ? "Starting…" : "Start Climate",
                    symbol: "fan.fill",
                    action: .startClimate
                )
            }
        case .security:
            if snapshot.allowsVehicleCommands != false {
                actionButton("Lock Car", symbol: "lock.fill", action: .lock)
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, action: FleetWidgetAction, iconOnly: Bool = false) -> some View {
        Button(intent: actionIntent(action)) {
            Label(title, systemImage: symbol)
                .labelStyle(WidgetActionLabelStyle(iconOnly: iconOnly))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(action.title)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if snapshot.mode != .live {
                Text(snapshot.mode.shortTitle)
                    .fontWeight(.semibold)
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
        .foregroundStyle(.tertiary)
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
        case .climate: snapshot.climateDescription
        case .security: snapshot.sentryOn.map { $0 ? "Sentry on" : "Sentry off" } ?? "Sentry unavailable"
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
