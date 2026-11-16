import AppIntents
import SwiftUI

public struct DrivingStatsSnippetView: View {
    public let stats: DrivingStatsEntity

    public init(stats: DrivingStatsEntity) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(stats.vehicleName, systemImage: "road.lanes")
                    .font(.headline)
                Spacer()
                Text(stats.periodTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%.1f mi", stats.totalDistanceMiles))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("across \(stats.driveCount) drive\(stats.driveCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let autopilotMiles = stats.autopilotDistanceMiles, stats.totalDistanceMiles > 0.1, autopilotMiles > 0.05 {
                let share = min(max(autopilotMiles / stats.totalDistanceMiles, 0), 1)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("Autopilot Share", systemImage: "steeringwheel")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text(String(format: "%.0f%% · %.1f mi", share * 100, autopilotMiles))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(proxy.size.width * share, 8))
                        }
                    }
                    .frame(height: 7)
                }
                .padding(9)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            HStack(spacing: 8) {
                statPill(
                    icon: "bolt.fill",
                    label: "Energy",
                    value: stats.totalEnergyUsedKWH.map { String(format: "%.1f kWh", $0) } ?? "—"
                )
                statPill(
                    icon: "leaf.fill",
                    label: "Efficiency",
                    value: stats.averageEfficiencyWhPerMile.map { String(format: "%.0f Wh/mi", $0) } ?? "—"
                )
                statPill(
                    icon: "clock",
                    label: "Drive Time",
                    value: formattedDuration
                )
            }
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: VehicleEntity.self, identifier: stats.vin))
    }

    private func statPill(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var formattedDuration: String {
        let hours = stats.totalDurationMinutes / 60
        let mins = stats.totalDurationMinutes % 60
        if hours > 0 {
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(stats.totalDurationMinutes)m"
    }
}

public struct ChargingStatsSnippetView: View {
    public let stats: ChargingStatsEntity

    public init(stats: ChargingStatsEntity) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(stats.vehicleName, systemImage: "bolt.car.fill")
                    .font(.headline)
                Spacer()
                Text(stats.periodTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "+%.1f kWh", stats.totalEnergyAddedKWH))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                if let cost = stats.formattedCost {
                    Text("· \(cost)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }

            if stats.sessionCount > 0 {
                let scFraction = min(max(Double(stats.superchargerCount) / Double(stats.sessionCount), 0), 1)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(stats.superchargerCount) Supercharger")
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(max(0, stats.sessionCount - stats.superchargerCount)) Home / AC")
                            .foregroundStyle(.green)
                    }
                    .font(.caption2.weight(.semibold))

                    GeometryReader { proxy in
                        HStack(spacing: 3) {
                            if scFraction > 0 {
                                Capsule()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: max(proxy.size.width * scFraction - 1.5, 6))
                            }
                            if scFraction < 1 {
                                Capsule()
                                    .fill(Color.green.opacity(0.85))
                            }
                        }
                    }
                    .frame(height: 7)
                }
                .padding(9)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            HStack(spacing: 8) {
                miniTile(icon: "ev.charger.fill", label: "Sessions", value: "\(stats.sessionCount)")
                miniTile(
                    icon: "road.lanes",
                    label: "Range Added",
                    value: stats.totalMilesAdded > 0 ? String(format: "+%.0f mi", stats.totalMilesAdded) : "—"
                )
                miniTile(
                    icon: "mappin.and.ellipse",
                    label: "Latest",
                    value: stats.lastChargeLocation ?? "—"
                )
            }
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: VehicleEntity.self, identifier: stats.vin))
    }

    private func miniTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

public struct BatteryHealthSnippetView: View {
    public let battery: BatteryHealthEntity

    public init(battery: BatteryHealthEntity) {
        self.battery = battery
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(battery.vehicleName, systemImage: "battery.100percent.bolt")
                .font(.headline)

            if let health = battery.healthPercent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "%.1f%%", health))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                        Text("Pack Health")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let deg = battery.degradationPercent {
                            Text(String(format: "-%.1f%% deg", deg))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    GeometryReader { proxy in
                        let frac = min(max(health / 100.0, 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(proxy.size.width * frac, 8))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(10)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let remaining = battery.energyRemainingKWH {
                Text(String(format: "%.1f kWh Remaining", remaining))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                packTile(
                    icon: "bolt.batteryblock.fill",
                    label: "Capacity",
                    value: capacityLabel
                )
                packTile(
                    icon: "gauge.with.dots.needle.67percent",
                    label: "100% Range",
                    value: battery.maxRangeMiles.map { String(format: "%.0f mi", $0) } ?? "—"
                )
                packTile(
                    icon: "sparkles",
                    label: "Lifetime",
                    value: battery.lifetimeEnergyUsedKWH.map { String(format: "%.0f kWh", $0) } ?? "—"
                )
            }
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: VehicleEntity.self, identifier: battery.vin))
    }

    private var capacityLabel: String {
        if let cap = battery.usableCapacityKWH, let orig = battery.originalCapacityKWH {
            return String(format: "%.1f/%.0f kWh", cap, orig)
        }
        if let cap = battery.usableCapacityKWH {
            return String(format: "%.1f kWh", cap)
        }
        return "—"
    }

    private func packTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

