import AppIntents
import SwiftUI

public struct DrivingStatsSnippetView: View {
    public let stats: DrivingStatsEntity
    public let includeEntityIdentifier: Bool

    public init(stats: DrivingStatsEntity, includeEntityIdentifier: Bool = true) {
        self.stats = stats
        self.includeEntityIdentifier = includeEntityIdentifier
    }

    public var body: some View {
        content
            .modifier(OptionalEntityIdentifierModifier(
                identifier: includeEntityIdentifier ? EntityIdentifier(for: VehicleEntity.self, identifier: stats.vin) : nil
            ))
    }

    private var content: some View {
        let usesMetric = FleetKitFormatting.prefersMetric()
        let efficiencyValue: String = stats.averageEfficiencyWhPerMile.map { whPerMi in
            if usesMetric {
                let whPerKm = Int((whPerMi / 1.609344).rounded())
                return String(localized: "\(whPerKm) Wh/km", bundle: .module, comment: "Driving efficiency in watt-hours per kilometer")
            }
            return String(localized: "\(Int(whPerMi.rounded())) Wh/mi", bundle: .module, comment: "Driving efficiency in watt-hours per mile")
        } ?? "—"

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(stats.vehicleName, systemImage: "road.lanes")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(stats.periodTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(FleetKitFormatting.distance(miles: stats.totalDistanceMiles, usesMetric: usesMetric, fractionLength: 1))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("across ^[\(stats.driveCount) drive](inflect: true)", bundle: .module, comment: "Drive count subtitle next to total distance driven")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }

            if let autopilotMiles = stats.autopilotDistanceMiles, stats.totalDistanceMiles > 0.1, autopilotMiles > 0.05 {
                let share = min(max(autopilotMiles / stats.totalDistanceMiles, 0), 1)
                let sharePct = FleetKitFormatting.percent(share * 100)
                let apDist = FleetKitFormatting.distance(miles: autopilotMiles, usesMetric: usesMetric, fractionLength: 1)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label {
                            Text("Autopilot Share", bundle: .module, comment: "Autopilot percentage share bar title")
                        } icon: {
                            Image(systemName: "steeringwheel")
                        }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text(verbatim: "\(sharePct) · \(apDist)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        FractionalCapsuleBar(fraction: share, minimumWidth: 8)
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                    }
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(height: 7)
                }
                .padding(9)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            HStack(spacing: 8) {
                statPill(
                    icon: "bolt.fill",
                    label: LocalizedStringResource("Energy", bundle: FleetKitLocalization.bundleDescription, comment: "Driving stats energy pill label"),
                    value: stats.totalEnergyUsedKWH.map { FleetKitFormatting.energyKWH($0) } ?? "—"
                )
                statPill(
                    icon: "leaf.fill",
                    label: LocalizedStringResource("Efficiency", bundle: FleetKitLocalization.bundleDescription, comment: "Driving stats efficiency pill label"),
                    value: efficiencyValue
                )
                statPill(
                    icon: "clock",
                    label: LocalizedStringResource("Drive Time", bundle: FleetKitLocalization.bundleDescription, comment: "Driving stats total duration pill label"),
                    value: FleetKitFormatting.durationMinutes(stats.totalDurationMinutes)
                )
            }
        }
        .padding(14)
    }

    private func statPill(icon: String, label: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

public struct ChargingStatsSnippetView: View {
    public let stats: ChargingStatsEntity
    public let includeEntityIdentifier: Bool

    public init(stats: ChargingStatsEntity, includeEntityIdentifier: Bool = true) {
        self.stats = stats
        self.includeEntityIdentifier = includeEntityIdentifier
    }

    public var body: some View {
        content
            .modifier(OptionalEntityIdentifierModifier(
                identifier: includeEntityIdentifier ? EntityIdentifier(for: VehicleEntity.self, identifier: stats.vin) : nil
            ))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(stats.vehicleName, systemImage: "bolt.car.fill")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(stats.periodTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "+\(FleetKitFormatting.energyKWH(stats.totalEnergyAddedKWH))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let cost = stats.formattedCost {
                    Text(verbatim: "· \(cost)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
            }

            if stats.sessionCount > 0 {
                let scFraction = min(max(Double(stats.superchargerCount) / Double(stats.sessionCount), 0), 1)
                let acCount = max(0, stats.sessionCount - stats.superchargerCount)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(stats.superchargerCount) Supercharger", bundle: .module, comment: "Count of Supercharger sessions on charging split bar")
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(acCount) Home / AC", bundle: .module, comment: "Count of home or AC charging sessions on charging split bar")
                            .foregroundStyle(.green)
                    }
                    .font(.caption2.weight(.semibold))

                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        if scFraction > 0 {
                            FractionalCapsuleBar(
                                startFraction: 0,
                                endFraction: scFraction,
                                minimumWidth: 6,
                                trailingGap: scFraction < 1 ? 1.5 : 0
                            )
                            .fill(Color.red.opacity(0.85))
                        }
                        if scFraction < 1 {
                            FractionalCapsuleBar(
                                startFraction: scFraction,
                                endFraction: 1,
                                minimumWidth: 6,
                                leadingGap: scFraction > 0 ? 1.5 : 0
                            )
                            .fill(Color.green.opacity(0.85))
                        }
                    }
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(height: 7)
                }
                .padding(9)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            HStack(spacing: 8) {
                miniTile(
                    icon: "ev.charger.fill",
                    label: LocalizedStringResource("Sessions", bundle: FleetKitLocalization.bundleDescription, comment: "Charging session count tile label"),
                    value: stats.sessionCount.formatted()
                )
                miniTile(
                    icon: "road.lanes",
                    label: LocalizedStringResource("Range Added", bundle: FleetKitLocalization.bundleDescription, comment: "Total range added tile label"),
                    value: stats.totalMilesAdded > 0 ? "+\(FleetKitFormatting.distance(miles: stats.totalMilesAdded))" : "—"
                )
                miniTile(
                    icon: "mappin.and.ellipse",
                    label: LocalizedStringResource("Latest", bundle: FleetKitLocalization.bundleDescription, comment: "Most recent charging location tile label"),
                    value: stats.lastChargeLocation ?? "—"
                )
            }
        }
        .padding(14)
    }

    private func miniTile(icon: String, label: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

public struct BatteryHealthSnippetView: View {
    public let battery: BatteryHealthEntity
    public let includeEntityIdentifier: Bool

    public init(battery: BatteryHealthEntity, includeEntityIdentifier: Bool = true) {
        self.battery = battery
        self.includeEntityIdentifier = includeEntityIdentifier
    }

    public var body: some View {
        content
            .modifier(OptionalEntityIdentifierModifier(
                identifier: includeEntityIdentifier ? EntityIdentifier(for: VehicleEntity.self, identifier: battery.vin) : nil
            ))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(battery.vehicleName, systemImage: "battery.100percent.bolt")
                .font(.headline)
                .lineLimit(1)

            if let health = battery.healthPercent {
                let frac = min(max(health / 100.0, 0), 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(FleetKitFormatting.percent(health, fractionLength: 1))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("Pack Health", bundle: .module, comment: "Battery pack health title next to health percentage")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer()
                        if let deg = battery.degradationPercent {
                            let degPct = FleetKitFormatting.percent(deg, fractionLength: 1)
                            Text("-\(degPct) deg", bundle: .module, comment: "Abbreviated battery degradation percentage badge")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }

                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        FractionalCapsuleBar(fraction: frac, minimumWidth: 8)
                            .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                    }
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(height: 8)
                }
                .padding(10)
                .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let remaining = battery.energyRemainingKWH {
                let remKWH = FleetKitFormatting.energyKWH(remaining)
                Text("\(remKWH) Remaining", bundle: .module, comment: "Fallback headline when pack health percent is unavailable")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                packTile(
                    icon: "bolt.batteryblock.fill",
                    label: LocalizedStringResource("Capacity", bundle: FleetKitLocalization.bundleDescription, comment: "Battery usable capacity tile label"),
                    value: capacityLabel
                )
                packTile(
                    icon: "gauge.with.dots.needle.67percent",
                    label: LocalizedStringResource("100% Range", bundle: FleetKitLocalization.bundleDescription, comment: "Estimated full-charge range tile label"),
                    value: battery.maxRangeMiles.map { FleetKitFormatting.distance(miles: $0) } ?? "—"
                )
                packTile(
                    icon: "sparkles",
                    label: LocalizedStringResource("Lifetime", bundle: FleetKitLocalization.bundleDescription, comment: "Lifetime battery energy used tile label"),
                    value: battery.lifetimeEnergyUsedKWH.map { FleetKitFormatting.energyKWH($0, fractionLength: 0) } ?? "—"
                )
            }
        }
        .padding(14)
    }

    private var capacityLabel: String {
        if let cap = battery.usableCapacityKWH, let orig = battery.originalCapacityKWH {
            let capText = cap.formatted(.number.precision(.fractionLength(1)))
            let origText = FleetKitFormatting.energyKWH(orig, fractionLength: 0)
            return "\(capText)/\(origText)"
        }
        if let cap = battery.usableCapacityKWH {
            return FleetKitFormatting.energyKWH(cap)
        }
        return "—"
    }

    private func packTile(icon: String, label: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

