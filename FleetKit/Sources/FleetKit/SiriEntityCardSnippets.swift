import AppIntents
import Foundation
import SwiftUI

// MARK: - Entity Card Snippet Conformances

/// Provides rich static SwiftUI cards that Siri renders in responses and
/// conversation transcripts for FleetKit entities, supporting both `.standard`
/// (iPhone/iPad/Mac) and `.compact` (Apple Watch / tight spaces) families.

extension VehicleEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { vehicle, context in
            VehicleEntityCardView(vehicle: vehicle, compact: context.family == .compact)
        }
    }
}

extension VehicleStatusEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { status, context in
            VehicleStatusCardView(status: status, compact: context.family == .compact)
        }
    }
}

extension DriveEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { drive, context in
            DriveEntityCardView(drive: drive, compact: context.family == .compact)
        }
    }
}

extension ChargeSessionEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { session, context in
            ChargeSessionCardView(session: session, compact: context.family == .compact)
        }
    }
}

extension SoftwareUpdateEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { software, context in
            if context.family == .compact {
                SoftwareUpdateCompactCardView(software: software)
            } else {
                SoftwareUpdateStaticCardView(software: software)
            }
        }
    }
}

extension ReleaseNoteEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { note, context in
            ReleaseNoteCardView(note: note, compact: context.family == .compact)
        }
    }
}

extension DrivingStatsEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { stats, context in
            if context.family == .compact {
                DrivingStatsCompactCardView(stats: stats)
            } else {
                DrivingStatsSnippetView(stats: stats, includeEntityIdentifier: false)
            }
        }
    }
}

extension ChargingStatsEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { stats, context in
            if context.family == .compact {
                ChargingStatsCompactCardView(stats: stats)
            } else {
                ChargingStatsSnippetView(stats: stats, includeEntityIdentifier: false)
            }
        }
    }
}

extension BatteryHealthEntity: SnippetRepresentableEntity {
    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard, .compact]) { battery, context in
            if context.family == .compact {
                BatteryHealthCompactCardView(battery: battery)
            } else {
                BatteryHealthSnippetView(battery: battery, includeEntityIdentifier: false)
            }
        }
    }
}

// MARK: - Vehicle Card

private struct VehicleEntityCardView: View {
    let vehicle: VehicleEntity
    let compact: Bool

    private var subtitleText: String {
        let parts = [vehicle.model, vehicle.color].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Tesla" : parts.joined(separator: " · ")
    }

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "car.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if vehicle.isDefaultCar == true {
                    Text("Default")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.14), in: Capsule())
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Vehicle Status Card

/// Purely static status card snippet (no interactive buttons, links, or GeometryReader).
/// Deliberately omits GPS/address fields, which are gated by property-level
/// `.requiresAuthentication` on `VehicleStatusEntity`.
private struct VehicleStatusCardView: View {
    let status: VehicleStatusEntity
    let compact: Bool

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label(status.vehicleName, systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let isLocked = status.isLocked {
                        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(status.batteryDisplay)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(batteryColor)
                        .monospacedDigit()
                    if let range = status.batteryRangeMiles {
                        Text("\(Int(range.rounded())) mi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if let inside = status.insideTemp {
                        Text("\(Int(inside.rounded()))\(status.temperatureUnit ?? "°F")")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            .padding(10)
        } else {
            let unit = status.temperatureUnit ?? "°F"
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(status.vehicleName, systemImage: "car.fill")
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let isLocked = status.isLocked {
                        Label(
                            isLocked ? "Locked" : "Unlocked",
                            systemImage: isLocked ? "lock.fill" : "lock.open.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isLocked ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }

                    if status.sentryModeOn == true {
                        Image(systemName: "record.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(status.batteryDisplay)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(batteryColor)
                            .monospacedDigit()

                        if let range = status.batteryRangeMiles {
                            Text("· \(Int(range.rounded())) mi")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Spacer(minLength: 4)

                        if let state = status.chargingState, !state.isEmpty {
                            let isCharging = state.localizedStandardContains("charging") && !state.localizedStandardContains("dis")
                            Label(state.capitalized, systemImage: isCharging ? "bolt.fill" : "powerplug")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isCharging ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }

                    if let pct = status.batteryPercent {
                        let clampedPct = min(max(Double(pct) / 100.0, 0), 1)
                        let limitFraction = min(max(Double(status.chargeLimitPercent ?? 80) / 100.0, 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            FractionalCapsuleBar(fraction: clampedPct, minimumWidth: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [batteryColor.opacity(0.85), batteryColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            if status.chargeLimitPercent != nil {
                                FractionalTickMark(fraction: limitFraction, tickWidth: 2.5, tickHeight: 14)
                                    .fill(.primary.opacity(0.75))
                            }
                        }
                        .frame(height: 9)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 8) {
                    if let inside = status.insideTemp {
                        cardMetricTile(
                            icon: status.isClimateOn == true ? "fan.fill" : "thermometer.medium",
                            tint: status.isClimateOn == true ? .orange : .secondary,
                            label: "Cabin",
                            value: "\(Int(inside.rounded()))\(unit)"
                        )
                    }
                    if let odometer = status.odometerDisplay {
                        cardMetricTile(
                            icon: "gauge.with.needle",
                            tint: .secondary,
                            label: "Odometer",
                            value: odometer
                        )
                    }
                    if let tires = status.tireSummary {
                        cardMetricTile(
                            icon: "car.side.rear.and.tire.marks",
                            tint: .secondary,
                            label: "Tires",
                            value: tires
                        )
                    }
                }
            }
            .padding(14)
        }
    }

    private var batteryColor: Color {
        switch status.batteryPercent ?? 50 {
        case ..<20: .red
        case ..<35: .orange
        default: .green
        }
    }
}

// MARK: - Drive Card

private struct DriveEntityCardView: View {
    let drive: DriveEntity
    let compact: Bool

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(drive.distanceText)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    if let duration = drive.durationText {
                        Text("· \(duration)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let battery = drive.batterySummaryText {
                        Text(battery)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                Text(drive.routeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
        } else {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(drive.distanceText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if let duration = drive.durationText {
                        Text("· \(duration)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    if let tag = drive.tag, !tag.isEmpty {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.14), in: Capsule())
                    }
                }

                Text(drive.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(drive.startAddress ?? "Start location")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(drive.endAddress ?? "Destination")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                HStack(spacing: 8) {
                    if let battery = drive.batterySummaryText {
                        cardMetricTile(icon: "battery.75percent", tint: .green, label: "Battery", value: battery)
                    }
                    if let efficiency = drive.efficiencyText {
                        cardMetricTile(icon: "leaf.fill", tint: .green, label: "Efficiency", value: efficiency)
                    }
                    if let energy = drive.energyUsedKWH {
                        cardMetricTile(
                            icon: "bolt.fill",
                            tint: .orange,
                            label: "Energy",
                            value: String(format: "%.1f kWh", energy)
                        )
                    }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Charge Session Card

private struct ChargeSessionCardView: View {
    let session: ChargeSessionEntity
    let compact: Bool

    private var accentColor: Color {
        session.isSupercharger ? .red : .green
    }

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: session.isSupercharger ? "bolt.circle.fill" : "powerplug.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Text(session.energyText)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if let cost = session.formattedCost {
                        Text(cost)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                Text(session.location ?? session.chargerKindText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
        } else {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Label(
                        session.location ?? session.chargerKindText,
                        systemImage: session.isSupercharger ? "bolt.circle.fill" : "powerplug.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(session.isSupercharger ? "Supercharger" : "AC")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.14), in: Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.energyText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()

                    if let cost = session.formattedCost {
                        Text("· \(cost)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }

                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let battery = session.batterySummaryText {
                        cardMetricTile(icon: "battery.100percent.bolt", tint: .green, label: "Battery", value: battery)
                    }
                    if let miles = session.milesAdded, miles > 0 {
                        cardMetricTile(
                            icon: "road.lanes",
                            tint: .blue,
                            label: "Range",
                            value: String(format: "+%.0f mi", miles)
                        )
                    }
                    if let minutes = session.durationMinutes, minutes > 0 {
                        cardMetricTile(icon: "clock", tint: .secondary, label: "Duration", value: "\(minutes) min")
                    }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Software & Release Note Cards

private struct SoftwareUpdateStaticCardView: View {
    let software: SoftwareUpdateEntity

    private var activeProgressPercent: Double? {
        if let install = software.installPercent, install > 0 { return Double(install) }
        if let download = software.downloadPercent, download > 0, software.updateAvailable { return Double(download) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(software.vehicleName, systemImage: "car.fill")
                    .font(.headline)
                Spacer()
                if let current = software.currentVersion {
                    Text("Installed \(current)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Image(systemName: software.updateAvailable ? "arrow.down.circle.dotted" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(software.updateAvailable ? AnyShapeStyle(.tint) : AnyShapeStyle(.green))

                VStack(alignment: .leading, spacing: 2) {
                    Text(software.headline)
                        .font(.subheadline.weight(.bold))
                    Text(software.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let progress = activeProgressPercent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(software.installPercent ?? 0 > 0 ? "Installing Update" : "Downloaded")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress.rounded()))%")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                    }
                    ProgressView(value: min(max(progress, 0), 100), total: 100)
                }
            }
        }
        .padding(14)
    }
}

private struct SoftwareUpdateCompactCardView: View {
    let software: SoftwareUpdateEntity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: software.updateAvailable ? "arrow.down.circle.dotted" : "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(software.updateAvailable ? AnyShapeStyle(.tint) : AnyShapeStyle(.green))

            VStack(alignment: .leading, spacing: 2) {
                Text(software.headline)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(software.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }
}

private struct ReleaseNoteCardView: View {
    let note: ReleaseNoteEntity
    let compact: Bool

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(note.title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let version = note.version, !version.isEmpty {
                        Text("v\(version)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if let details = note.details, !details.isEmpty {
                    Text(details)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Label(note.title, systemImage: "sparkles")
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    if let version = note.version, !version.isEmpty {
                        Text("v\(version)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.16), in: Capsule())
                    }
                }

                if let subtitle = note.subtitle,
                   !subtitle.isEmpty,
                   subtitle.caseInsensitiveCompare(note.title) != .orderedSame {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let details = note.details,
                   !details.isEmpty,
                   details.caseInsensitiveCompare(note.subtitle ?? "") != .orderedSame {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Compact Stats Cards

private struct DrivingStatsCompactCardView: View {
    let stats: DrivingStatsEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(stats.vehicleName, systemImage: "road.lanes")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(stats.periodTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f mi", stats.totalDistanceMiles))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("· \(stats.driveCount) drive\(stats.driveCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }
}

private struct ChargingStatsCompactCardView: View {
    let stats: ChargingStatsEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(stats.vehicleName, systemImage: "bolt.car.fill")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(stats.periodTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "+%.1f kWh", stats.totalEnergyAddedKWH))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                if let cost = stats.formattedCost {
                    Text("· \(cost)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(10)
    }
}

private struct BatteryHealthCompactCardView: View {
    let battery: BatteryHealthEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(battery.vehicleName, systemImage: "battery.100percent.bolt")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let health = battery.healthPercent {
                    Text(String(format: "%.1f%%", health))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                    Text("Pack Health")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let remaining = battery.energyRemainingKWH {
                    Text(String(format: "%.1f kWh", remaining))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
            }
        }
        .padding(10)
    }
}

// MARK: - Shared Helper

private func cardMetricTile(icon: String, tint: Color, label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Label(label, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(tint)
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
