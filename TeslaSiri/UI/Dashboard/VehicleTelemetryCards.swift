import AppIntents
import CoreLocation
import FleetKit
import MapKit
import SwiftUI

/// At-a-glance cards under the Vehicle tab hero: live drive, charging & battery,
/// interactive climate + security, location, tires, and vehicle details.
struct VehicleTelemetryCards: View {
    let vehicle: FleetVehicle
    let units: String?
    let activeDrive: FleetActiveDriveSession?
    let chargingSessions: [FleetChargeSession]
    var includeLocation: Bool = true
    var isRunningControl: Bool = false
    var activeControlAction: String? = nil
    var pendingControls: Set<VehicleControlCommand> = []
    var onCommand: ((VehicleControlCommand) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let activeDrive {
            VehicleLiveDriveCard(drive: activeDrive, units: units)
        }

        if let snapshot = vehicle.latest {
            VehicleBatteryCard(
                snapshot: snapshot,
                units: units,
                sessions: chargingSessions,
                controlsEnabled: vehicle.allowsChargingControls && onCommand != nil,
                isRunningControl: isRunningControl,
                activeControlAction: activeControlAction,
                pendingControls: pendingControls,
                onCommand: onCommand
            )

            let pairLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            pairLayout {
                VehicleClimateCard(
                    snapshot: snapshot,
                    units: units,
                    controlsEnabled: vehicle.allowsVehicleControls && onCommand != nil,
                    isRunningControl: isRunningControl,
                    activeControlAction: activeControlAction,
                    pendingControls: pendingControls,
                    onCommand: onCommand
                )
                VehicleSecurityCard(
                    snapshot: snapshot,
                    controlsEnabled: vehicle.allowsVehicleControls && onCommand != nil,
                    isRunningControl: isRunningControl,
                    activeControlAction: activeControlAction,
                    pendingControls: pendingControls,
                    onCommand: onCommand
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if includeLocation, let latitude = snapshot.latitude, let longitude = snapshot.longitude {
                VehicleLocationCard(vehicleName: vehicle.name, latitude: latitude, longitude: longitude)
            }

            if let tires = snapshot.tires, tires.hasAnyReading {
                VehicleTiresCard(tires: tires, units: units)
            }

            VehicleDetailsCard(vehicle: vehicle, snapshot: snapshot, units: units)
        }
    }
}

// MARK: - Live drive

struct VehicleLiveDriveCard: View {
    let drive: FleetActiveDriveSession
    var units: String? = nil

    private var speedNumber: String {
        guard let mph = drive.latestRoutePoint?.speed ?? drive.latest?.speed else { return "--" }
        let value = prefersMetricUnits(units) ? mph * 1.609_344 : mph
        return formattedNumber(value, fractionLength: 0)
    }

    private var speedUnit: String {
        prefersMetricUnits(units) ? UnitSpeed.kilometersPerHour.symbol : UnitSpeed.milesPerHour.symbol
    }

    var body: some View {
        DashboardCard("Driving", systemImage: "location.north.fill", tint: AppTheme.chargeGreen) {
            if let status = drive.status {
                Text(humanizedStatus(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } content: {
            HStack(alignment: .lastTextBaseline) {
                MetricValueText(
                    value: speedNumber,
                    unit: speedUnit
                )
                Spacer(minLength: 12)
                HStack(spacing: 18) {
                    if let distance = drive.distanceMiles {
                        miniStat(formattedDistance(miles: distance, units: units, fractionLength: 1), caption: "Distance")
                    }
                    if let durationMS = drive.durationMS, durationMS > 0 {
                        miniStat(formattedDuration(milliseconds: durationMS), caption: "Duration")
                    }
                }
            }
        }
        .appEntityIdentifier(driveEntityIdentifier)
    }

    private func miniStat(_ value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var driveEntityIdentifier: EntityIdentifier? {
        guard !drive.sessionID.isEmpty else { return nil }
        return EntityIdentifier(for: DriveEntity.self, identifier: drive.sessionID)
    }
}

// MARK: - Battery & Charging

struct VehicleBatteryCard: View {
    let snapshot: FleetLatestSnapshot
    let units: String?
    let sessions: [FleetChargeSession]
    var controlsEnabled: Bool = false
    var isRunningControl: Bool = false
    var activeControlAction: String? = nil
    var pendingControls: Set<VehicleControlCommand> = []
    var onCommand: ((VehicleControlCommand) -> Void)? = nil

    private static let chargeLimitPresets = [50, 60, 70, 80, 90, 100]

    private var isCharging: Bool { snapshot.isActivelyCharging }
    private var isPortOpen: Bool { snapshot.chargePortDoorOpen == true }

    private var isPluggedIn: Bool {
        if isCharging { return true }
        guard let raw = snapshot.chargingState?.lowercased() else { return false }
        if raw.contains("disconnected") { return false }
        return raw.contains("stopped") || raw.contains("complete") || raw.contains("connected") || raw.contains("starting")
    }

    var body: some View {
        DashboardCard("Charging", systemImage: batterySymbol, tint: isCharging ? AppTheme.chargeGreen : .secondary) {
            StatusBadge(
                plugStatusText,
                systemImage: isCharging ? "bolt.fill" : "powerplug",
                tint: isCharging ? AppTheme.chargeGreen : (isPortOpen ? AppTheme.climateBlue : .secondary)
            )
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formattedPercent(snapshot.batteryLevel))
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isCharging ? AppTheme.chargeGreen : .primary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(formattedRange)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Battery \(formattedPercent(snapshot.batteryLevel)), \(formattedRange) range")

                    Spacer(minLength: 8)

                    chargeLimitControl
                }

                if let level = snapshot.batteryLevel {
                    BatteryLevelBar(
                        level: level / 100,
                        limit: snapshot.chargeLimitSOC.map { $0 / 100 },
                        isCharging: isCharging
                    )
                }

                if isCharging {
                    chargingDetails
                }

                if controlsEnabled {
                    chargingActionStrip
                }

                if !sessions.isEmpty {
                    Divider()
                    NavigationLink {
                        ChargingHistoryView(sessions: sessions)
                    } label: {
                        DashboardCardLinkLabel(
                            title: "Charging History",
                            systemImage: "clock.arrow.circlepath",
                            detail: sessions.count.formatted()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var chargeLimitControl: some View {
        let currentLimit = snapshot.chargeLimitSOC.map { Int($0.rounded()) }
        if controlsEnabled, let onCommand {
            Menu {
                ForEach(Self.chargeLimitPresets, id: \.self) { percent in
                    Button {
                        onCommand(.setChargeLimit(percent: percent))
                    } label: {
                        let percentText = FleetKitFormatting.percent(percent)
                        if currentLimit == percent {
                            Label(percentText, systemImage: "checkmark")
                        } else {
                            Text(percentText)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let currentLimit {
                        Text("Limit \(FleetKitFormatting.percent(currentLimit))")
                            .monospacedDigit()
                    } else {
                        Text("Set Limit")
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.insetSurface, in: Capsule())
            }
            .tint(.primary)
            .disabled(isRunningControl || isBusy(.setChargeLimit(percent: currentLimit ?? 80)))
            .accessibilityLabel("Charge limit")
            .accessibilityValue(
                currentLimit.map { FleetKitFormatting.percent($0) }
                    ?? String(localized: "Unset", comment: "Accessibility value when charge limit is not set")
            )
        } else if let currentLimit {
            Text("Limit \(FleetKitFormatting.percent(currentLimit))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var chargingActionStrip: some View {
        HStack(spacing: 8) {
            if isPluggedIn {
                let chargeCommand = VehicleControlCommand.charge(shouldStart: !isCharging)
                Button {
                    onCommand?(chargeCommand)
                } label: {
                    HStack(spacing: 6) {
                        if isBusy(chargeCommand) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: isCharging ? "stop.fill" : "bolt.fill")
                                .font(.caption.weight(.semibold))
                        }
                        Group {
                            if isCharging {
                                Text("Stop Charging")
                            } else {
                                Text("Start Charging")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isCharging ? AppTheme.alertAmber : AppTheme.chargeGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                    .background(
                        (isCharging ? AppTheme.alertAmber : AppTheme.chargeGreen).opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunningControl || isBusy(chargeCommand))
            }

            if !isCharging {
                let portCommand = VehicleControlCommand.chargePort(open: !isPortOpen)
                Button {
                    onCommand?(portCommand)
                } label: {
                    HStack(spacing: 6) {
                        if isBusy(portCommand) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.circle")
                                .font(.caption.weight(.semibold))
                        }
                        Group {
                            if isPortOpen {
                                Text("Close Port")
                            } else {
                                Text("Open Charge Port")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isPortOpen ? AnyShapeStyle(AppTheme.climateBlue) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                    .background(
                        isPortOpen ? AppTheme.climateBlue.opacity(0.13) : AppTheme.insetSurface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRunningControl || isBusy(portCommand))
            }
        }
    }

    private func isBusy(_ command: VehicleControlCommand) -> Bool {
        (isRunningControl && activeControlAction == command.action)
            || pendingControls.contains { $0.conflicts(with: command) }
    }

    @ViewBuilder
    private var chargingDetails: some View {
        HStack(spacing: 8) {
            if let power = snapshot.chargerPowerKW, power > 0 {
                detail(formattedPowerKW(power), caption: "Power")
            }
            if let rate = snapshot.chargeRateMPH, rate > 0 {
                detail(formattedSpeed(mph: rate, units: units), caption: "Rate")
            }
            if let remaining = snapshot.timeToFullCharge, remaining > 0 {
                let duration = Duration.seconds(Int((remaining * 3_600).rounded())).formatted(
                    .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
                )
                detail(duration, caption: "To limit")
            }
        }
    }

    private func detail(_ value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var plugStatusText: String {
        if let state = snapshot.chargingState, !state.isEmpty {
            return humanizedStatus(state)
        }
        return isPortOpen
            ? String(localized: "Port Open", comment: "Charging status badge when the charge port door is open")
            : String(localized: "Unplugged", comment: "Charging status badge when the vehicle is not plugged in")
    }

    private var batterySymbol: String {
        if isCharging { return "battery.100.bolt" }
        let level = snapshot.batteryLevel ?? 0
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var formattedRange: String {
        formattedDistance(miles: snapshot.batteryRange, units: units)
    }
}

/// Sleek Tesla-style graduated battery bar with charge-limit pin.
private struct BatteryLevelBar: View {
    let level: Double
    let limit: Double?
    let isCharging: Bool

    private var clampedLevel: Double { max(0, min(level, 1)) }

    private var fillStyle: Color {
        if isCharging { return AppTheme.chargeGreen }
        if clampedLevel <= 0.15 { return AppTheme.accent }
        return clampedLevel <= 0.25 ? AppTheme.alertAmber : AppTheme.chargeGreen
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = proxy.size.height
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.insetSurface)

                Capsule()
                    .fill(fillStyle.gradient)
                    .frame(width: max(height, width * clampedLevel))
                    .animation(.smooth(duration: 0.35), value: clampedLevel)

                // Subtle quarter-scale ticks positioned via leading spacers so RTL mirrors cleanly.
                ForEach([0.25, 0.5, 0.75], id: \.self) { tick in
                    HStack(spacing: 0) {
                        Color.clear.frame(width: width * tick)
                        Rectangle()
                            .fill(.background.opacity(0.28))
                            .frame(width: 1, height: height - 4)
                        Spacer(minLength: 0)
                    }
                }

                if let limit {
                    let clampedLimit = max(0, min(limit, 1))
                    let leading = min(max(width * clampedLimit - 1.25, 0), width - 2.5)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: leading)
                        Capsule()
                            .fill(.primary.opacity(0.8))
                            .frame(width: 2.5, height: height + 6)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: 14)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let levelText = FleetKitFormatting.percent(clampedLevel * 100)
        if let limit {
            let limitText = FleetKitFormatting.percent(limit * 100)
            return String(localized: "\(levelText), charge limit \(limitText)", comment: "VoiceOver value for battery gauge with charge limit")
        }
        return levelText
    }
}

private struct ChargingHistoryView: View {
    let sessions: [FleetChargeSession]

    var body: some View {
        List(sessions) { session in
            ChargeHistoryRow(session: session)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppScreenBackground())
        .navigationTitle("Charging History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChargeHistoryRow: View {
    let session: FleetChargeSession

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAtDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                if hasSubtitle {
                    HStack(spacing: 4) {
                        if let start = session.batteryLevelStart, let end = session.batteryLevelEnd {
                            Text(formattedPercent(start))
                            Image(systemName: "arrow.forward")
                                .font(.caption2)
                            Text(formattedPercent(end))
                        }
                        if !extraSubtitleParts.isEmpty {
                            if session.batteryLevelStart != nil, session.batteryLevelEnd != nil {
                                Text("·")
                            }
                            Text(extraSubtitleParts.joined(separator: " · "))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }

            Spacer()

            if let energy = session.energyAddedKWH {
                Text("+\(formattedEnergyKWH(energy))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.chargeGreen)
                    .monospacedDigit()
            } else {
                Text(session.status.map(humanizedStatus) ?? String(localized: "Charge", comment: "Fallback label for a charging session row"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        // Same "<VIN>:<id>" identifier as FleetKit's ChargeSessionEntity, so Siri can
        // resolve "tell me about this charge" from the visible row.
        .appEntityIdentifier(EntityIdentifier(for: ChargeSessionEntity.self, identifier: session.sessionID))
    }

    private var hasSubtitle: Bool {
        (session.batteryLevelStart != nil && session.batteryLevelEnd != nil) || !extraSubtitleParts.isEmpty
    }

    private var extraSubtitleParts: [String] {
        var parts: [String] = []
        if let power = session.avgPowerKW, power > 0 {
            let powerText = formattedPowerKW(power)
            parts.append(String(localized: "\(powerText) avg", comment: "Average charging power in charging history row"))
        }
        if let cost = session.cost, cost > 0 {
            parts.append(
                session.currency.map { cost.formatted(.currency(code: $0)) }
                    ?? String(localized: "Cost \(cost.formatted())", comment: "Charging session cost when currency code is missing")
            )
        }
        return parts
    }
}

// MARK: - Climate & security

struct VehicleClimateCard: View {
    let snapshot: FleetLatestSnapshot
    let units: String?
    var controlsEnabled: Bool = false
    var isRunningControl: Bool = false
    var activeControlAction: String? = nil
    var pendingControls: Set<VehicleControlCommand> = []
    var onCommand: ((VehicleControlCommand) -> Void)? = nil

    private var isOn: Bool { snapshot.climateOn == true }
    private var isMetric: Bool { prefersMetricUnits(units) }

    var body: some View {
        DashboardCard("Climate", systemImage: isOn ? "fan.fill" : "fan", tint: isOn ? AppTheme.climateBlue : .secondary) {
            VStack(alignment: .leading, spacing: 4) {
                MetricValueText(value: formattedNumber(snapshot.insideTemp, fractionLength: 0, suffix: "°"))
                if let outside = snapshot.outsideTemp {
                    Text("\(formattedNumber(outside, fractionLength: 0, suffix: "°")) outside")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Inside cabin")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                if controlsEnabled {
                    climateInteractiveControl
                } else {
                    Label(statusText, systemImage: isOn ? "fan.fill" : "power")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(isOn ? AnyShapeStyle(AppTheme.climateBlue) : AnyShapeStyle(.secondary))
                        .labelStyle(CompactLabelStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var climateInteractiveControl: some View {
        if isOn {
            let targetDisplay = snapshot.targetTemperature ?? (isMetric ? 21 : 70)
            HStack(spacing: 0) {
                Button {
                    stepTemperature(delta: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isRunningControl)
                .accessibilityLabel("Decrease target temperature")

                Spacer(minLength: 0)

                Text(formattedNumber(targetDisplay, fractionLength: 0, suffix: "°"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.climateBlue)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Target temperature \(formattedTemperature(targetDisplay, inFahrenheit: !isMetric))")

                Spacer(minLength: 0)

                Button {
                    stepTemperature(delta: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isRunningControl)
                .accessibilityLabel("Increase target temperature")
            }
            .foregroundStyle(AppTheme.climateBlue)
            .padding(.horizontal, 4)
            .background(AppTheme.climateBlue.opacity(0.13), in: Capsule())
        } else {
            let startCommand = VehicleControlCommand.climate(shouldTurnOn: true)
            Button {
                onCommand?(startCommand)
            } label: {
                HStack(spacing: 5) {
                    if isBusy(startCommand) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "fan.fill")
                            .font(.caption2.weight(.semibold))
                    }
                    Text("Start Climate")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(AppTheme.climateBlue)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 30)
                .padding(.horizontal, 8)
                .background(AppTheme.climateBlue.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRunningControl || isBusy(startCommand))
            .accessibilityLabel("Start climate")
        }
    }

    private func stepTemperature(delta: Double) {
        let current = snapshot.targetTemperature ?? (isMetric ? 21 : 70)
        let celsius: Double
        if isMetric {
            celsius = min(max((current + delta).rounded(), 15), 28)
        } else {
            let nextF = min(max((current + delta).rounded(), 59), 82)
            celsius = ((nextF - 32) * 5 / 9 * 100).rounded() / 100
        }
        onCommand?(.setCabinTemperature(celsius: celsius))
    }

    private func isBusy(_ command: VehicleControlCommand) -> Bool {
        (isRunningControl && activeControlAction == command.action)
            || pendingControls.contains { $0.conflicts(with: command) }
    }

    private var statusText: String {
        guard let on = snapshot.climateOn else {
            return String(localized: "Unavailable", comment: "Climate status when telemetry is unavailable")
        }
        guard on else {
            return String(localized: "Off", comment: "Climate status when climate control is off")
        }
        if let target = snapshot.targetTemperature {
            let temp = formattedNumber(target, fractionLength: 0, suffix: "°")
            return String(localized: "Set to \(temp)", comment: "Climate status when active with a target temperature")
        }
        return String(localized: "On", comment: "Climate status when climate control is on")
    }
}

struct VehicleSecurityCard: View {
    let snapshot: FleetLatestSnapshot
    var controlsEnabled: Bool = false
    var isRunningControl: Bool = false
    var activeControlAction: String? = nil
    var pendingControls: Set<VehicleControlCommand> = []
    var onCommand: ((VehicleControlCommand) -> Void)? = nil

    private var isLocked: Bool { snapshot.locked == true }
    private var isSentryOn: Bool { snapshot.sentryMode == true }

    var body: some View {
        DashboardCard("Security", systemImage: "lock.shield", tint: isLocked ? .secondary : AppTheme.alertAmber) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let locked = snapshot.locked {
                        if locked {
                            Text("Locked")
                        } else {
                            Text("Unlocked")
                        }
                    } else {
                        Text("--")
                    }
                }
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(isLocked ? AnyShapeStyle(.primary) : AnyShapeStyle(AppTheme.alertAmber))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                let summary = closureSummary
                Label(summary.text, systemImage: summary.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(summary.hasOpenItem ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.secondary))
                    .labelStyle(CompactLabelStyle())

                Spacer(minLength: 10)

                if controlsEnabled, snapshot.sentryMode != nil {
                    sentryToggleButton
                } else if let sentry = snapshot.sentryMode {
                    Label(
                        sentry ? LocalizedStringKey("Sentry on") : LocalizedStringKey("Sentry off"),
                        systemImage: sentry ? "eye.fill" : "eye.slash"
                    )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(sentry ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(.secondary))
                        .labelStyle(CompactLabelStyle())
                }
            }
        }
    }

    private var sentryToggleButton: some View {
        let command = VehicleControlCommand.sentryMode(shouldTurnOn: !isSentryOn)
        return Button {
            onCommand?(command)
        } label: {
            HStack(spacing: 5) {
                if isBusy(command) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isSentryOn ? "eye.fill" : "eye.slash")
                        .font(.caption2.weight(.semibold))
                }
                Group {
                    if isSentryOn {
                        Text("Sentry On")
                    } else {
                        Text("Sentry Off")
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSentryOn ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
            .padding(.horizontal, 8)
            .background(
                isSentryOn ? AppTheme.accent.opacity(0.14) : AppTheme.insetSurface,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(isRunningControl || isBusy(command))
        .accessibilityLabel(isSentryOn ? Text("Turn off Sentry Mode") : Text("Turn on Sentry Mode"))
        .accessibilityValue(isSentryOn ? Text("On") : Text("Off"))
    }

    private func isBusy(_ command: VehicleControlCommand) -> Bool {
        (isRunningControl && activeControlAction == command.action)
            || pendingControls.contains { $0.conflicts(with: command) }
    }

    private var closureSummary: (text: String, symbol: String, hasOpenItem: Bool) {
        let c = snapshot.closures
        let groups: [(String, [Bool?])] = [
            (String(localized: "Door", comment: "Closure item name for vehicle doors"), [c?.frontDriverDoorOpen, c?.frontPassengerDoorOpen, c?.rearDriverDoorOpen, c?.rearPassengerDoorOpen]),
            (String(localized: "Frunk", comment: "Closure item name for front trunk"), [c?.frontTrunkOpen]),
            (String(localized: "Trunk", comment: "Closure item name for rear trunk"), [c?.rearTrunkOpen]),
            (String(localized: "Window", comment: "Closure item name for vehicle windows"), [c?.frontDriverWindowOpen, c?.frontPassengerWindowOpen, c?.rearDriverWindowOpen, c?.rearPassengerWindowOpen]),
            (String(localized: "Port", comment: "Closure item name for charge port"), [snapshot.chargePortDoorOpen])
        ]
        let openItems = groups.filter { $0.1.contains(true) }.map(\.0)
        if !openItems.isEmpty {
            let list = openItems.formatted(.list(type: .and))
            return (
                String(localized: "\(list) open", comment: "Security card summary listing open doors, trunks, windows, or charge port"),
                "exclamationmark.triangle.fill",
                true
            )
        }
        if groups.contains(where: { $0.1.contains(nil) }) {
            return (
                String(localized: "Closure status incomplete", comment: "Security card summary when some door/window sensors are unknown"),
                "questionmark.circle",
                false
            )
        }
        return (
            String(localized: "All closed", comment: "Security card summary when all doors, trunks, windows, and charge port are closed"),
            "checkmark.circle",
            false
        )
    }
}

/// Tight icon + title label for the small status lines inside cards.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
                .imageScale(.small)
            configuration.title
                .lineLimit(2)
        }
    }
}

// MARK: - Location

struct VehicleLocationCard: View {
    let vehicleName: String
    let latitude: Double
    let longitude: Double
    var mapHeight: CGFloat = 196

    @State private var resolvedAddress: String?

    var body: some View {
        DashboardCard("Location", systemImage: "location.fill") {
            if let mapsURL {
                Link(destination: mapsURL) {
                    Label("Directions", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.footnote.weight(.semibold))
                }
            }
        } content: {
            Map(
                position: .constant(.camera(MapCamera(centerCoordinate: coordinate, distance: 820))),
                interactionModes: []
            ) {
                Marker(vehicleName, systemImage: "car.fill", coordinate: coordinate)
                    .tint(AppTheme.accent)
            }
            .mapControlVisibility(.hidden)
            .frame(height: mapHeight)
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)

                    Text(resolvedAddress ?? coordinateTaskID)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppTheme.hairline)
                        .frame(height: 0.5)
                }
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.hairline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Location of \(vehicleName): \(resolvedAddress ?? coordinateTaskID)")
            .task(id: coordinateTaskID) {
                let address = await driveEndpointAddressGeocoder.address(latitude: latitude, longitude: longitude)
                guard !Task.isCancelled else { return }
                if let address {
                    resolvedAddress = address
                }
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var coordinateTaskID: String {
        formattedCoordinate(latitude: latitude, longitude: longitude)
    }

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: vehicleName)
        ]
        return components?.url
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}

// MARK: - Tires

struct VehicleTiresCard: View {
    let tires: FleetTirePressures
    var units: String? = nil

    private static let lowThresholdPSI = 38.0
    private var isMetric: Bool { prefersMetricUnits(units) }

    private var hasLowTire: Bool {
        [tires.frontLeftPSI, tires.frontRightPSI, tires.rearLeftPSI, tires.rearRightPSI]
            .compactMap { $0 }
            .contains { $0 < Self.lowThresholdPSI }
    }

    var body: some View {
        DashboardCard(
            "Tire Pressure",
            systemImage: hasLowTire ? "exclamationmark.tirepressure" : "tirepressure",
            tint: hasLowTire ? AppTheme.alertAmber : .secondary
        ) {
            if hasLowTire {
                StatusBadge("Low Tire", systemImage: "exclamationmark.triangle.fill", tint: AppTheme.alertAmber)
            } else if let measured = tires.measuredAtDate {
                RelativeTimeText(date: measured)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } content: {
            // Pin physical left/right vehicle diagram to LTR so left tires stay on the car's left side in RTL.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 34) {
                    tireReading(
                        tires.frontLeftPSI,
                        position: String(localized: "Front left", comment: "Front left tire position label"),
                        alignment: .leading
                    )
                    tireReading(
                        tires.rearLeftPSI,
                        position: String(localized: "Rear left", comment: "Rear left tire position label"),
                        alignment: .leading
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VehicleTopDownOutline(
                    lowFrontLeft: isLow(tires.frontLeftPSI),
                    lowFrontRight: isLow(tires.frontRightPSI),
                    lowRearLeft: isLow(tires.rearLeftPSI),
                    lowRearRight: isLow(tires.rearRightPSI)
                )
                .frame(width: 72, height: 128)
                .accessibilityHidden(true)

                VStack(alignment: .trailing, spacing: 34) {
                    tireReading(
                        tires.frontRightPSI,
                        position: String(localized: "Front right", comment: "Front right tire position label"),
                        alignment: .trailing
                    )
                    tireReading(
                        tires.rearRightPSI,
                        position: String(localized: "Rear right", comment: "Rear right tire position label"),
                        alignment: .trailing
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.vertical, 4)
        }
    }

    private func isLow(_ psi: Double?) -> Bool {
        guard let psi else { return false }
        return psi < Self.lowThresholdPSI
    }

    private func formattedPressureValue(_ psi: Double?) -> String {
        guard let psi else { return "--" }
        if isMetric {
            let bar = Measurement(value: psi, unit: UnitPressure.poundsForcePerSquareInch).converted(to: .bars).value
            return formattedNumber(bar, fractionLength: 2)
        }
        return formattedNumber(psi, fractionLength: 1)
    }

    private var pressureUnitSymbol: String {
        isMetric ? UnitPressure.bars.symbol : UnitPressure.poundsForcePerSquareInch.symbol
    }

    private func tireReading(_ psi: Double?, position: String, alignment: HorizontalAlignment) -> some View {
        let low = isLow(psi)
        let pressureText = formattedTirePressure(psi: psi, units: units)
        return VStack(alignment: alignment, spacing: 2) {
            MetricValueText(
                value: formattedPressureValue(psi),
                unit: pressureUnitSymbol,
                font: .system(.title2, design: .rounded, weight: .semibold),
                unitFont: .caption.weight(.semibold)
            )
            .foregroundStyle(low ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.primary))
            Text(low ? String(localized: "\(position) · Low", comment: "Tire position label with low pressure indicator") : position)
                .font(.caption)
                .foregroundStyle(low ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(position) tire"))
        .accessibilityValue(
            low
                ? String(localized: "\(pressureText), low", comment: "VoiceOver value for a tire with low pressure")
                : pressureText
        )
    }
}

/// Top-down car silhouette with panoramic glass roof and four wheel indicators.
private struct VehicleTopDownOutline: View {
    var lowFrontLeft: Bool = false
    var lowFrontRight: Bool = false
    var lowRearLeft: Bool = false
    var lowRearRight: Bool = false

    var body: some View {
        ZStack {
            wheel(offset: CGSize(width: -30, height: -35), isLow: lowFrontLeft)
            wheel(offset: CGSize(width: 30, height: -35), isLow: lowFrontRight)
            wheel(offset: CGSize(width: -30, height: 36), isLow: lowRearLeft)
            wheel(offset: CGSize(width: 30, height: 36), isLow: lowRearRight)

            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(AppTheme.insetSurface)
                .strokeBorder(AppTheme.hairline, lineWidth: 1.25)
                .frame(width: 56, height: 124)

            // Panoramic glass canopy (windshield + roof + rear glass)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.primary.opacity(0.08))
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.75)
                .frame(width: 40, height: 74)
                .offset(y: 4)

            // Crossbar hint separating windshield and roof glass
            Rectangle()
                .fill(AppTheme.insetSurface)
                .frame(width: 38, height: 2)
                .offset(y: -12)
        }
    }

    private func wheel(offset: CGSize, isLow: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(isLow ? AnyShapeStyle(AppTheme.alertAmber) : AnyShapeStyle(.secondary.opacity(0.8)))
            .frame(width: 7, height: 22)
            .offset(offset)
    }
}

// MARK: - Details

struct VehicleDetailsCard: View {
    let vehicle: FleetVehicle
    let snapshot: FleetLatestSnapshot
    let units: String?

    var body: some View {
        DashboardCard("Vehicle", systemImage: "car.fill") {
            VStack(alignment: .leading, spacing: 12) {
                let specs = specBadges
                if !specs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(specs, id: \.self) { spec in
                                Text(spec)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.insetSurface, in: Capsule())
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    let rows = detailRows
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .monospacedDigit()
                                .textSelection(.enabled)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 9)

                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var specBadges: [String] {
        let config = snapshot.vehicleConfiguration
        return [
            config?.humanizedModelName,
            config?.humanizedTrimName,
            config?.humanizedPaintName,
            config?.humanizedWheelName
        ].compactMap { $0 }
    }

    private var detailRows: [(label: LocalizedStringKey, value: String)] {
        var rows: [(label: LocalizedStringKey, value: String)] = []
        if let odometer = snapshot.odometer {
            rows.append(("Odometer", formattedDistance(miles: odometer, units: units)))
        }
        if !vehicle.vin.isEmpty {
            rows.append(("VIN", vehicle.vin))
        }
        return rows
    }
}
