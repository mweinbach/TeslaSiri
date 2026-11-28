import AppIntents
import FleetKit
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Calibrated Widget Palette (matches Wattie Showroom AppTheme)

enum WidgetPalette {
    static let crimson = dynamic(
        light: UIColor(red: 0.824, green: 0.110, blue: 0.196, alpha: 1),
        dark: UIColor(red: 0.949, green: 0.212, blue: 0.298, alpha: 1)
    )

    static let chargeGreen = dynamic(
        light: UIColor(red: 0.118, green: 0.659, blue: 0.341, alpha: 1),
        dark: UIColor(red: 0.188, green: 0.820, blue: 0.447, alpha: 1)
    )

    static let climateBlue = dynamic(
        light: UIColor(red: 0.039, green: 0.478, blue: 0.859, alpha: 1),
        dark: UIColor(red: 0.247, green: 0.667, blue: 1.000, alpha: 1)
    )

    static let alertAmber = dynamic(
        light: UIColor(red: 0.878, green: 0.467, blue: 0.020, alpha: 1),
        dark: UIColor(red: 1.000, green: 0.624, blue: 0.125, alpha: 1)
    )

    static let tileFill = dynamic(
        light: UIColor(white: 0, alpha: 0.045),
        dark: UIColor(white: 1, alpha: 0.075)
    )

    static let tileStroke = dynamic(
        light: UIColor(white: 0, alpha: 0.07),
        dark: UIColor(white: 1, alpha: 0.12)
    )

    static let surfaceBase = dynamic(
        light: UIColor.systemBackground,
        dark: UIColor(red: 0.086, green: 0.084, blue: 0.092, alpha: 1)
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

// MARK: - Subtle Semantic Widget Backdrop

struct VehicleWidgetBackdrop: View {
    var snapshot: FleetWidgetSnapshot?
    var topic: VehicleWidgetTopic

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var ambientTint: Color {
        guard let snapshot else { return WidgetPalette.crimson }
        if let feedback = snapshot.activeFeedback(), topic.handles(feedback.action) {
            switch feedback.outcome {
            case .confirmed: return WidgetPalette.chargeGreen
            case .waking: return WidgetPalette.alertAmber
            case .failed: return WidgetPalette.crimson
            }
        }
        switch topic {
        case .overview:
            if snapshot.locked == false { return WidgetPalette.alertAmber }
            if snapshot.isCharging { return WidgetPalette.chargeGreen }
            if snapshot.climateOn == true || snapshot.isClimateStarting() { return WidgetPalette.climateBlue }
            return WidgetPalette.crimson
        case .charging:
            if snapshot.isCharging { return WidgetPalette.chargeGreen }
            return (snapshot.batteryLevel ?? 50) <= 20 ? WidgetPalette.alertAmber : WidgetPalette.chargeGreen
        case .climate:
            return snapshot.isClimateStarting() ? WidgetPalette.alertAmber : WidgetPalette.climateBlue
        case .security:
            return (snapshot.locked == false || snapshot.openClosures?.isEmpty == false)
                ? WidgetPalette.alertAmber
                : WidgetPalette.climateBlue
        }
    }

    var body: some View {
        if renderingMode == .fullColor && !isLuminanceReduced {
            ZStack {
                WidgetPalette.surfaceBase
                LinearGradient(
                    colors: [
                        ambientTint.opacity(colorScheme == .dark ? 0.16 : 0.09),
                        ambientTint.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - Main Widget Panel

struct VehicleWidgetPanel: View {
    var snapshot: FleetWidgetSnapshot
    var topic: VehicleWidgetTopic
    var family: WidgetFamily = .systemSmall
    var message: String?

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryCircular
    }

    private var activeFeedback: FleetWidgetActionFeedback? {
        guard let feedback = snapshot.activeFeedback(), topic.handles(feedback.action) else {
            return nil
        }
        return feedback
    }

    private var isClimateActive: Bool {
        snapshot.climateOn == true
    }

    private var isClimateWaking: Bool {
        snapshot.isClimateStarting() || (activeFeedback?.action == .startClimate && activeFeedback?.outcome == .waking)
    }

    private var hasOpenClosures: Bool {
        snapshot.openClosures?.isEmpty == false
    }

    private var accentColor: Color {
        switch topic {
        case .overview:
            if snapshot.isCharging { return WidgetPalette.chargeGreen }
            if snapshot.locked == false { return WidgetPalette.alertAmber }
            if isClimateActive { return WidgetPalette.climateBlue }
            return WidgetPalette.crimson
        case .charging:
            if snapshot.isCharging { return WidgetPalette.chargeGreen }
            return (snapshot.batteryLevel ?? 50) <= 20 ? WidgetPalette.alertAmber : WidgetPalette.chargeGreen
        case .climate:
            if isClimateWaking { return WidgetPalette.alertAmber }
            return WidgetPalette.climateBlue
        case .security:
            return (snapshot.locked == false || hasOpenClosures) ? WidgetPalette.alertAmber : WidgetPalette.climateBlue
        }
    }

    private var batteryTint: Color {
        if snapshot.isCharging { return WidgetPalette.chargeGreen }
        let level = snapshot.batteryLevel ?? 50
        if level <= 15 { return WidgetPalette.crimson }
        if level <= 25 { return WidgetPalette.alertAmber }
        return WidgetPalette.chargeGreen
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

    // MARK: - Home Screen Layouts

    @ViewBuilder
    private var panelContent: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        case .systemLarge:
            largeLayout
        default:
            smallLayout
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            headline

            smallSupplemental

            Spacer(minLength: 0)

            smallActions

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    headline
                    mediumLeftAnchor
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    mediumRightContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headlineValue)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(headlineColor)
                        .widgetAccentable()
                        .invalidatableContent()

                    Text(headlineCaption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .invalidatableContent()

                    Spacer(minLength: 4)

                    statusChip(
                        title: largeStatusTitle,
                        symbol: largeStatusSymbol,
                        tint: largeStatusTint
                    )
                }

                batteryProgressBar(barHeight: 8, showsCaption: true, preferTimeRemaining: true)
            }

            largeTelemetryGrid

            Spacer(minLength: 0)

            largeActions

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        let isSmall = family == .systemSmall
        return HStack(spacing: isSmall ? 5 : 6) {
            ZStack {
                if renderingMode == .fullColor {
                    Circle()
                        .fill(accentColor.opacity(0.16))
                }
                Image(systemName: topic.systemImage)
                    .font(.system(size: isSmall ? 10 : 11, weight: .bold))
                    .foregroundStyle(accentColor)
                    .widgetAccentable()
            }
            .frame(width: isSmall ? 20 : 22, height: isSmall ? 20 : 22)

            Text(snapshot.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 2)

            refreshButton
        }
    }

    private var refreshButton: some View {
        let refreshConfirmed = activeFeedback?.action == .refresh && activeFeedback?.outcome == .confirmed
        let refreshFailed = activeFeedback?.action == .refresh && activeFeedback?.outcome == .failed
        let symbol = refreshConfirmed ? "checkmark" : (refreshFailed ? "exclamationmark" : "arrow.clockwise")
        let tint: Color = refreshConfirmed
            ? WidgetPalette.chargeGreen
            : (refreshFailed ? WidgetPalette.crimson : .secondary)
        let size: CGFloat = family == .systemSmall ? 22 : 24

        return Button(intent: actionIntent(.refresh)) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(refreshConfirmed || refreshFailed ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .background(
                    (refreshConfirmed || refreshFailed)
                        ? tint.opacity(0.18)
                        : WidgetPalette.tileFill,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel(
            refreshConfirmed
                ? String(localized: "Vehicle updated", comment: "VoiceOver label after a widget status refresh succeeds.")
                : String(localized: "Refresh vehicle", comment: "VoiceOver label for the widget refresh button.")
        )
    }

    // MARK: - Hero Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headlineValue)
                .font(.system(family == .systemSmall ? .title2 : .title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.68)
                .lineLimit(1)
                .foregroundStyle(headlineColor)
                .widgetAccentable()
                .invalidatableContent()

            Text(headlineCaption)
                .font(.caption.weight(.medium))
                .foregroundStyle(headlineCaptionColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .invalidatableContent()
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineColor: Color {
        switch topic {
        case .security:
            return snapshot.locked == false ? WidgetPalette.alertAmber : .primary
        case .charging:
            return snapshot.isCharging ? WidgetPalette.chargeGreen : .primary
        case .climate:
            if isClimateWaking { return WidgetPalette.alertAmber }
            return isClimateActive ? WidgetPalette.climateBlue : .primary
        case .overview:
            return .primary
        }
    }

    private var headlineCaptionColor: Color {
        switch topic {
        case .charging where snapshot.isCharging:
            return WidgetPalette.chargeGreen
        case .climate where isClimateActive:
            return WidgetPalette.climateBlue
        case .climate where isClimateWaking:
            return WidgetPalette.alertAmber
        case .security where snapshot.sentryOn == true:
            return WidgetPalette.crimson
        default:
            return .secondary
        }
    }

    // MARK: - Supplemental & Anchors

    @ViewBuilder
    private var smallSupplemental: some View {
        switch topic {
        case .overview:
            batteryProgressBar(barHeight: 5, showsCaption: false)
        case .charging:
            batteryProgressBar(barHeight: 6, showsCaption: true)
        case .climate:
            compactMetricLine(
                symbol: "thermometer.medium",
                text: String(localized: "Target \(snapshot.temperatureDescription(snapshot.targetTemperature))", comment: "Widget line showing the climate target temperature."),
                tint: isClimateActive ? WidgetPalette.climateBlue : .secondary
            )
        case .security:
            compactMetricLine(
                symbol: hasOpenClosures ? "exclamationmark.circle.fill" : "checkmark.shield.fill",
                text: closureSummary,
                tint: hasOpenClosures ? WidgetPalette.alertAmber : .secondary
            )
        }
    }

    @ViewBuilder
    private var mediumLeftAnchor: some View {
        switch topic {
        case .overview:
            batteryProgressBar(barHeight: 6, showsCaption: true)
        case .charging:
            batteryProgressBar(barHeight: 7, showsCaption: true)
        case .climate:
            compactMetricLine(
                symbol: "target",
                text: String(localized: "Target \(snapshot.temperatureDescription(snapshot.targetTemperature))", comment: "Widget line showing the climate target temperature."),
                tint: isClimateActive ? WidgetPalette.climateBlue : .secondary
            )
        case .security:
            compactMetricLine(
                symbol: hasOpenClosures ? "car.side.door.open" : "checkmark.shield.fill",
                text: closureSummary,
                tint: hasOpenClosures ? WidgetPalette.alertAmber : .secondary
            )
        }
    }

    @ViewBuilder
    private var mediumRightContent: some View {
        switch topic {
        case .overview:
            HStack(spacing: 6) {
                miniInfoPill(
                    symbol: snapshot.locked == false ? "lock.open.fill" : "lock.fill",
                    text: snapshot.locked == false
                        ? String(localized: "Unlocked", comment: "Widget pill while the car is unlocked.")
                        : (snapshot.locked == true ? String(localized: "Locked", comment: "Widget pill while the car is locked.") : "—"),
                    tint: snapshot.locked == false ? WidgetPalette.alertAmber : .secondary
                )
                miniInfoPill(
                    symbol: isClimateActive ? "fan.fill" : "thermometer.medium",
                    text: snapshot.temperatureDescription(snapshot.insideTemperature),
                    tint: isClimateActive ? WidgetPalette.climateBlue : .secondary
                )
            }
            if snapshot.allowsVehicleCommands != false {
                HStack(spacing: 6) {
                    widgetActionButton(for: .lock, compact: false)
                    widgetActionButton(for: .startClimate, compact: false)
                }
            }

        case .charging:
            miniInfoPill(
                symbol: "road.lanes",
                text: snapshot.rangeDescription,
                tint: .secondary
            )
            if snapshot.canStartCharging {
                widgetActionButton(for: .startCharging, compact: false)
            } else if snapshot.isCharging, let timeText = timeToLimitDescription {
                statusChip(title: timeText, symbol: "clock.fill", tint: WidgetPalette.chargeGreen)
            } else if let limit = snapshot.chargeLimit {
                statusChip(
                    title: String(localized: "Limit \(FleetKitFormatting.percent(limit))", comment: "Widget chip showing the charge limit percentage."),
                    symbol: "battery.100percent",
                    tint: .secondary
                )
            }

        case .climate:
            miniInfoPill(
                symbol: snapshot.isCharging ? "bolt.fill" : "battery.75percent",
                text: batteryAndRangeSummary,
                tint: batteryTint
            )
            if snapshot.allowsVehicleCommands != false {
                widgetActionButton(for: .startClimate, compact: false)
            }

        case .security:
            miniInfoPill(
                symbol: isClimateActive ? "fan.fill" : "car.fill",
                text: batteryAndCabinSummary,
                tint: isClimateActive ? WidgetPalette.climateBlue : .secondary
            )
            if snapshot.allowsVehicleCommands != false {
                widgetActionButton(for: .lock, compact: false)
            }
        }
    }

    private var batteryAndRangeSummary: String {
        let battery = snapshot.batteryLevel.map { FleetKitFormatting.percent($0) } ?? "—"
        return "\(battery) · \(snapshot.rangeDescription)"
    }

    private var batteryAndCabinSummary: String {
        let battery = snapshot.batteryLevel.map { FleetKitFormatting.percent($0) } ?? "—"
        let cabin = snapshot.temperatureDescription(snapshot.insideTemperature)
        return "\(battery) · \(cabin)"
    }

    // MARK: - Large Telemetry Grid & Actions

    private var largeTelemetryGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            telemetryTile(
                title: "Charging",
                value: largeChargingTileValue,
                symbol: "bolt.fill",
                tint: snapshot.isCharging ? WidgetPalette.chargeGreen : .secondary
            )
            telemetryTile(
                title: "Cabin",
                value: largeCabinTileValue,
                symbol: isClimateActive ? "fan.fill" : "thermometer.medium",
                tint: isClimateWaking ? WidgetPalette.alertAmber : (isClimateActive ? WidgetPalette.climateBlue : .secondary)
            )
            telemetryTile(
                title: "Security",
                value: largeSecurityTileValue,
                symbol: snapshot.locked == false ? "lock.open.fill" : "lock.fill",
                tint: snapshot.locked == false ? WidgetPalette.alertAmber : (snapshot.sentryOn == true ? WidgetPalette.crimson : .secondary)
            )
            telemetryTile(
                title: "Closures",
                value: closureSummary,
                symbol: hasOpenClosures ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                tint: hasOpenClosures ? WidgetPalette.alertAmber : WidgetPalette.chargeGreen
            )
        }
    }

    private func telemetryTile(title: LocalizedStringKey, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .invalidatableContent()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetPalette.tileFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WidgetPalette.tileStroke, lineWidth: 0.5)
                }
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var smallActions: some View {
        switch topic {
        case .overview:
            if snapshot.allowsVehicleCommands != false {
                HStack(spacing: 6) {
                    widgetActionButton(for: .lock, compact: true)
                    widgetActionButton(for: .startClimate, compact: true)
                }
            }
        case .charging:
            if snapshot.canStartCharging {
                widgetActionButton(for: .startCharging, compact: false)
            } else if snapshot.isCharging, let timeText = timeToLimitDescription {
                compactMetricLine(symbol: "clock.fill", text: timeText, tint: WidgetPalette.chargeGreen)
            }
        case .climate:
            if snapshot.allowsVehicleCommands != false {
                widgetActionButton(for: .startClimate, compact: false)
            }
        case .security:
            if snapshot.allowsVehicleCommands != false {
                widgetActionButton(for: .lock, compact: false)
            }
        }
    }

    @ViewBuilder
    private var largeActions: some View {
        if snapshot.allowsVehicleCommands != false || snapshot.canStartCharging {
            HStack(spacing: 8) {
                if snapshot.allowsVehicleCommands != false {
                    widgetActionButton(for: .lock, compact: false)
                    widgetActionButton(for: .startClimate, compact: false)
                }
                if snapshot.canStartCharging {
                    widgetActionButton(for: .startCharging, compact: false)
                }
            }
        }
    }

    // MARK: - Interactive Action Buttons with Confirmation States

    private enum ButtonVisualState {
        case resting
        case active(Color)
        case confirmed
        case waking
        case failed

        var isEmphasized: Bool {
            switch self {
            case .resting: false
            case .active, .confirmed, .waking, .failed: true
            }
        }
    }

    private func visualState(for action: FleetWidgetAction) -> ButtonVisualState {
        if let feedback = activeFeedback, feedback.action == action {
            switch feedback.outcome {
            case .confirmed: return .confirmed
            case .waking: return .waking
            case .failed: return .failed
            }
        }
        switch action {
        case .lock:
            if snapshot.locked == false { return .active(WidgetPalette.alertAmber) }
            return .resting
        case .startClimate:
            if isClimateWaking { return .waking }
            if isClimateActive { return .active(WidgetPalette.climateBlue) }
            return .resting
        case .startCharging:
            return .active(WidgetPalette.chargeGreen)
        case .refresh:
            return .resting
        }
    }

    private func buttonSymbol(for action: FleetWidgetAction, state: ButtonVisualState) -> String {
        switch state {
        case .confirmed:
            return "checkmark"
        case .waking:
            return "moon.zzz.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .resting, .active:
            switch action {
            case .lock:
                return snapshot.locked == false ? "lock.open.fill" : "lock.fill"
            case .startClimate:
                return isClimateActive ? "fan.fill" : "fan"
            case .startCharging:
                return "bolt.fill"
            case .refresh:
                return "arrow.clockwise"
            }
        }
    }

    private func buttonLabel(for action: FleetWidgetAction, state: ButtonVisualState) -> String {
        switch state {
        case .confirmed:
            switch action {
            case .lock:
                return String(localized: "Locked", comment: "Widget quick action label after the car locks.")
            case .startClimate:
                return String(localized: "On", comment: "Widget quick action label after cabin climate starts.")
            case .startCharging:
                return String(localized: "Started", comment: "Widget quick action label after a charge starts.")
            case .refresh:
                return String(localized: "Updated", comment: "Widget quick action label after a status refresh.")
            }
        case .waking:
            return String(localized: "Starting…", comment: "Widget quick action label while a sleeping car wakes.")
        case .failed:
            return String(localized: "Retry", comment: "Widget quick action label after a failed action.")
        case .resting, .active:
            switch action {
            case .lock:
                return family == .systemMedium && topic == .overview
                    ? String(localized: "Lock", comment: "Short widget quick action label for locking.")
                    : String(localized: "Lock Car", comment: "Widget quick action label for locking.")
            case .startClimate:
                if family == .systemMedium && topic == .overview {
                    return isClimateActive
                        ? String(localized: "On", comment: "Short widget quick action label while climate is running.")
                        : String(localized: "Climate", comment: "Short widget quick action label for climate.")
                }
                return isClimateActive
                    ? String(localized: "Climate On", comment: "Widget quick action label while climate is running.")
                    : String(localized: "Start Climate", comment: "Widget quick action label for starting climate.")
            case .startCharging:
                return String(localized: "Start Charge", comment: "Widget quick action label for starting a charge.")
            case .refresh:
                return String(localized: "Refresh", comment: "Widget quick action label for refreshing.")
            }
        }
    }

    private func widgetActionButton(for action: FleetWidgetAction, compact: Bool) -> some View {
        let state = visualState(for: action)
        let symbol = buttonSymbol(for: action, state: state)
        let title = buttonLabel(for: action, state: state)
        let minHeight: CGFloat = family == .systemLarge ? 34 : 28

        let foreground: Color
        let background: Color
        let stroke: Color

        switch state {
        case .confirmed:
            foreground = .white
            background = WidgetPalette.chargeGreen
            stroke = WidgetPalette.chargeGreen
        case .waking:
            foreground = .white
            background = WidgetPalette.alertAmber
            stroke = WidgetPalette.alertAmber
        case .failed:
            foreground = .white
            background = WidgetPalette.crimson
            stroke = WidgetPalette.crimson
        case .active(let tint):
            foreground = tint
            background = tint.opacity(0.16)
            stroke = tint.opacity(0.32)
        case .resting:
            foreground = .primary
            background = WidgetPalette.tileFill
            stroke = WidgetPalette.tileStroke
        }

        return Button(intent: actionIntent(action)) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 12 : 11, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                if !compact {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(foreground) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, compact ? 4 : 8)
            .background {
                Capsule(style: .continuous)
                    .fill(renderingMode == .fullColor ? background : WidgetPalette.tileFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(renderingMode == .fullColor ? stroke : WidgetPalette.tileStroke, lineWidth: 0.75)
                    }
            }
            .widgetAccentable(state.isEmphasized)
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel(accessibilityLabel(for: action, state: state))
    }

    private func accessibilityLabel(for action: FleetWidgetAction, state: ButtonVisualState) -> String {
        switch state {
        case .confirmed: return action.confirmedMessage
        case .waking: return "\(action.wakingMessage)"
        case .failed: return String(localized: "\(action.title), failed, double tap to retry", comment: "VoiceOver label for a widget quick action that failed.")
        case .resting, .active: return action.title
        }
    }

    // MARK: - Battery Progress Bar

    private func batteryProgressBar(
        barHeight: CGFloat,
        showsCaption: Bool,
        preferTimeRemaining: Bool = false
    ) -> some View {
        let level = max(0, min((snapshot.batteryLevel ?? 0) / 100.0, 1))
        let limit = snapshot.chargeLimit.map { max(0, min($0 / 100.0, 1)) }
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = proxy.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WidgetPalette.tileFill)
                    Capsule()
                        .fill(batteryTint.gradient)
                        .frame(width: max(height, width * level))
                        .widgetAccentable()
                    if let limit {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: min(max(width * limit - 1, 0), width - 2), height: 1)
                            Capsule()
                                .fill(.primary.opacity(0.72))
                                .frame(width: 2, height: height + 3)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(height: barHeight)
            .invalidatableContent()

            if showsCaption {
                HStack(spacing: 6) {
                    if let limitVal = snapshot.chargeLimit {
                        Text("Limit \(FleetKitFormatting.percent(limitVal))")
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    if preferTimeRemaining, let timeText = timeToLimitDescription, snapshot.isCharging {
                        Text(timeText)
                            .foregroundStyle(WidgetPalette.chargeGreen)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } else if let power = snapshot.chargerPowerKW, snapshot.isCharging, power > 0 {
                        Text(
                            Measurement(value: power, unit: UnitPower.kilowatts).formatted(
                                .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                            )
                        )
                            .foregroundStyle(WidgetPalette.chargeGreen)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } else if let timeText = timeToLimitDescription, snapshot.isCharging {
                        Text(timeText)
                            .foregroundStyle(WidgetPalette.chargeGreen)
                            .monospacedDigit()
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery charge")
        .accessibilityValue(
            snapshot.batteryLevel.map { FleetKitFormatting.percent($0) }
                ?? String(localized: "Unavailable", comment: "VoiceOver fallback when battery charge is unavailable")
        )
    }

    // MARK: - Small Reusable Chips

    private func compactMetricLine(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .invalidatableContent()
    }

    private func miniInfoPill(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WidgetPalette.tileFill, in: Capsule(style: .continuous))
        .invalidatableContent()
    }

    private func statusChip(title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule(style: .continuous))
        .widgetAccentable()
        .invalidatableContent()
    }

    // MARK: - Footer with Animated Activation Confirmation Banner

    @ViewBuilder
    private var footer: some View {
        if let feedback = activeFeedback {
            feedbackBanner(feedback)
                .id(feedback)
                .transition(isLuminanceReduced ? .identity : .push(from: .bottom).combined(with: .opacity))
        } else {
            restingFooter
                .id("resting-footer")
                .transition(isLuminanceReduced ? .identity : .opacity)
        }
    }

    private func feedbackBanner(_ feedback: FleetWidgetActionFeedback) -> some View {
        let tint: Color = switch feedback.outcome {
        case .confirmed: WidgetPalette.chargeGreen
        case .waking: WidgetPalette.alertAmber
        case .failed: WidgetPalette.crimson
        }

        return HStack(spacing: 5) {
            Image(systemName: feedback.symbolName)
                .font(.system(size: 10.5, weight: .bold))
            Text(feedback.message)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(renderingMode == .fullColor ? tint : .primary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(renderingMode == .fullColor ? tint.opacity(0.16) : WidgetPalette.tileFill)
        )
        .widgetAccentable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedback.message)
    }

    private var restingFooter: some View {
        HStack(spacing: 5) {
            if snapshot.mode != .live {
                Text(snapshot.mode.shortTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(WidgetPalette.tileFill, in: Capsule())
            }
            if let message {
                Text(message)
                    .foregroundStyle(WidgetPalette.alertAmber)
            } else if let updatedAt = snapshot.updatedAt {
                Group {
                    if family == .systemSmall {
                        if Calendar.current.isDateInToday(updatedAt) {
                            Text(updatedAt, format: .dateTime.hour().minute())
                        } else {
                            Text(updatedAt, format: .dateTime.month(.abbreviated).day())
                        }
                    } else {
                        Text(updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                }
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

    // MARK: - Lock Screen Accessories

    private var accessoryContent: some View {
        Group {
            if family == .accessoryCircular {
                let confirmed = activeFeedback?.outcome == .confirmed
                Gauge(value: snapshot.batteryLevel ?? 0, in: 0...100) {
                    Image(systemName: confirmed ? "checkmark" : (snapshot.isCharging ? "bolt.fill" : "car.fill"))
                } currentValueLabel: {
                    Text(snapshot.batteryLevel.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
                .invalidatableContent()
                .accessibilityLabel("Car battery")
                .accessibilityValue(
                    snapshot.batteryLevel.map { FleetKitFormatting.percent($0) }
                        ?? String(localized: "Unavailable", comment: "VoiceOver fallback when battery charge is unavailable")
                )
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: topic.systemImage)
                            .font(.caption2.weight(.bold))
                        Text(snapshot.name)
                            .font(.caption.weight(.semibold))
                    }
                    .widgetAccentable()

                    Text("\(headlineValue) · \(headlineCaption)")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .invalidatableContent()

                    if let feedback = activeFeedback {
                        Label(feedback.message, systemImage: feedback.symbolName)
                            .font(.caption2.weight(.semibold))
                    } else {
                        Text(accessorySecondaryLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accessorySecondaryLine: String {
        switch topic {
        case .overview:
            return "\(snapshot.lockDescription) · \(snapshot.temperatureDescription(snapshot.insideTemperature))"
        case .charging:
            if let power = snapshot.chargerPowerKW, snapshot.isCharging, power > 0 {
                return "\(Measurement(value: power, unit: UnitPower.kilowatts).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))) · \(timeToLimitDescription ?? snapshot.rangeDescription)"
            }
            return snapshot.rangeDescription
        case .climate:
            return String(localized: "Target \(snapshot.temperatureDescription(snapshot.targetTemperature))", comment: "Lock Screen accessory line showing the climate target temperature.")
        case .security:
            return closureSummary
        }
    }

    // MARK: - Derived Strings

    private var headlineValue: String {
        switch topic {
        case .overview, .charging:
            snapshot.batteryLevel.map { FleetKitFormatting.percent($0) } ?? "—"
        case .climate:
            snapshot.temperatureDescription(snapshot.insideTemperature)
        case .security:
            snapshot.lockDescription
        }
    }

    private var headlineCaption: String {
        switch topic {
        case .overview: snapshot.rangeDescription
        case .charging: snapshot.chargingDescription
        case .climate: snapshot.climateDescription
        case .security:
            snapshot.sentryOn.map {
                $0
                    ? String(localized: "Sentry on", comment: "Widget caption when Sentry Mode is enabled")
                    : String(localized: "Sentry off", comment: "Widget caption when Sentry Mode is disabled")
            } ?? String(localized: "Sentry unavailable", comment: "Widget caption when Sentry Mode status is unavailable")
        }
    }

    private var closureSummary: String {
        snapshot.openClosures.map { $0.isEmpty ? String(localized: "All closed", comment: "Widget security detail when all doors, windows, and trunks are closed") : $0.formatted(.list(type: .and)) } ?? String(localized: "Unavailable", comment: "Widget security detail when closure status is unavailable")
    }

    private var timeToLimitDescription: String? {
        guard let hours = snapshot.hoursToCharge, hours > 0 else { return nil }
        let duration = Duration.seconds(hours * 3600).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
        return String(localized: "\(duration) to limit", comment: "Widget or Control Center label shown on Home Screen, Lock Screen, or Control Center.")
    }

    private var largeStatusTitle: String {
        if snapshot.isCharging {
            return String(localized: "Charging", comment: "Widget status chip while the car is charging.")
        }
        if snapshot.locked == false {
            return String(localized: "Unlocked", comment: "Widget status chip while the car is unlocked.")
        }
        if isClimateActive {
            return String(localized: "Climate On", comment: "Widget status chip while cabin climate is running.")
        }
        return String(localized: "Ready", comment: "Widget status chip when nothing needs attention.")
    }

    private var largeStatusSymbol: String {
        if snapshot.isCharging { return "bolt.fill" }
        if snapshot.locked == false { return "lock.open.fill" }
        if isClimateActive { return "fan.fill" }
        return "checkmark.circle.fill"
    }

    private var largeStatusTint: Color {
        if snapshot.isCharging { return WidgetPalette.chargeGreen }
        if snapshot.locked == false { return WidgetPalette.alertAmber }
        if isClimateActive { return WidgetPalette.climateBlue }
        return .secondary
    }

    private var largeChargingTileValue: String {
        if snapshot.isCharging, let power = snapshot.chargerPowerKW, power > 0 {
            return "\(Measurement(value: power, unit: UnitPower.kilowatts).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))))"
        }
        return snapshot.chargingDescription
    }

    private var largeCabinTileValue: String {
        let inside = snapshot.temperatureDescription(snapshot.insideTemperature)
        if isClimateActive, let target = snapshot.targetTemperature {
            return "\(inside) → \(snapshot.temperatureDescription(target))"
        }
        return inside
    }

    private var largeSecurityTileValue: String {
        guard let sentry = snapshot.sentryOn else { return snapshot.lockDescription }
        let sentryText = sentry
            ? String(localized: "Sentry on", comment: "Widget caption when Sentry Mode is enabled")
            : String(localized: "Sentry off", comment: "Widget caption when Sentry Mode is disabled")
        return "\(snapshot.lockDescription) · \(sentryText)"
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
        case .overview: String(localized: "Vehicle", comment: "Widget topic title for vehicle overview")
        case .charging: String(localized: "Charging", comment: "Widget topic title for charging status")
        case .climate: String(localized: "Cabin Climate", comment: "Widget topic title for cabin climate")
        case .security: String(localized: "Vehicle Security", comment: "Widget topic title for vehicle security")
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

    func handles(_ action: FleetWidgetAction) -> Bool {
        switch self {
        case .overview: true
        case .charging: action == .startCharging || action == .refresh
        case .climate: action == .startClimate || action == .refresh
        case .security: action == .lock || action == .refresh
        }
    }
}

// MARK: - SwiftUI Previews (Inspectable via Xcode RenderPreview)

#if DEBUG
private enum WidgetPreviewFixtures {
    static var base: FleetWidgetSnapshot {
        var s = FleetWidgetSnapshot.sample
        s.name = "Model Y"
        s.batteryLevel = 78
        s.rangeMiles = 242
        s.chargeLimit = 80
        s.chargingState = "Disconnected"
        s.insideTemperature = 68
        s.targetTemperature = 70
        s.climateOn = false
        s.locked = true
        s.sentryOn = true
        s.openClosures = []
        s.updatedAt = .now.addingTimeInterval(-180)
        return s
    }

    static var lockConfirmed: FleetWidgetSnapshot {
        var s = base
        s.actionFeedback = .confirmed(action: .lock)
        return s
    }

    static var climateWaking: FleetWidgetSnapshot {
        var s = base
        s.insideTemperature = 84
        s.targetTemperature = 70
        s.climateStartRequestedAt = .now
        s.actionFeedback = .waking(action: .startClimate)
        return s
    }

    static var chargingActive: FleetWidgetSnapshot {
        var s = base
        s.batteryLevel = 62
        s.rangeMiles = 192
        s.chargeLimit = 80
        s.chargingState = "Charging"
        s.chargerPowerKW = 11.5
        s.hoursToCharge = 1.25
        s.actionFeedback = .confirmed(action: .startCharging)
        return s
    }

    static var unlockedAlertAndError: FleetWidgetSnapshot {
        var s = base
        s.locked = false
        s.openClosures = ["Trunk"]
        s.actionFeedback = FleetWidgetActionFeedback(
            action: .lock,
            outcome: .failed,
            message: "Car timed out"
        )
        return s
    }

    static var pluggedPaused: FleetWidgetSnapshot {
        var s = base
        s.batteryLevel = 44
        s.rangeMiles = 136
        s.chargeLimit = 80
        s.chargingState = "Stopped"
        return s
    }
}

private struct WidgetPreviewFrame<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var snapshot: FleetWidgetSnapshot
    var topic: VehicleWidgetTopic
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(width: width, height: height)
            .background(VehicleWidgetBackdrop(snapshot: snapshot, topic: topic))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(WidgetPalette.tileStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

#Preview("Small — All Topics & Feedback") {
    ScrollView {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                WidgetPreviewFrame(width: 164, height: 164, snapshot: WidgetPreviewFixtures.base, topic: .overview) {
                    VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.base, topic: .overview, family: .systemSmall)
                }
                WidgetPreviewFrame(width: 164, height: 164, snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview) {
                    VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview, family: .systemSmall)
                }
            }
            HStack(spacing: 14) {
                WidgetPreviewFrame(width: 164, height: 164, snapshot: WidgetPreviewFixtures.chargingActive, topic: .charging) {
                    VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.chargingActive, topic: .charging, family: .systemSmall)
                }
                WidgetPreviewFrame(width: 164, height: 164, snapshot: WidgetPreviewFixtures.pluggedPaused, topic: .charging) {
                    VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.pluggedPaused, topic: .charging, family: .systemSmall)
                }
            }
            HStack(spacing: 14) {
                WidgetPreviewFrame(width: 164, height: 164, snapshot: WidgetPreviewFixtures.climateWaking, topic: .climate) {
                    VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.climateWaking, topic: .climate, family: .systemSmall)
                }
                WidgetPreviewFrame(width: 164, height: 164, snapshot: WidgetPreviewFixtures.unlockedAlertAndError, topic: .security) {
                    VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.unlockedAlertAndError, topic: .security, family: .systemSmall)
                }
            }
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Medium — All Topics & Feedback") {
    ScrollView {
        VStack(spacing: 14) {
            WidgetPreviewFrame(width: 344, height: 160, snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview) {
                VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview, family: .systemMedium)
            }
            WidgetPreviewFrame(width: 344, height: 160, snapshot: WidgetPreviewFixtures.chargingActive, topic: .charging) {
                VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.chargingActive, topic: .charging, family: .systemMedium)
            }
            WidgetPreviewFrame(width: 344, height: 160, snapshot: WidgetPreviewFixtures.climateWaking, topic: .climate) {
                VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.climateWaking, topic: .climate, family: .systemMedium)
            }
            WidgetPreviewFrame(width: 344, height: 160, snapshot: WidgetPreviewFixtures.unlockedAlertAndError, topic: .security) {
                VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.unlockedAlertAndError, topic: .security, family: .systemMedium)
            }
        }
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Large — Resting & Confirmed (Dark)") {
    ScrollView {
        VStack(spacing: 16) {
            WidgetPreviewFrame(width: 344, height: 356, snapshot: WidgetPreviewFixtures.chargingActive, topic: .overview) {
                VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.chargingActive, topic: .overview, family: .systemLarge)
            }
            WidgetPreviewFrame(width: 344, height: 356, snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview) {
                VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview, family: .systemLarge)
            }
        }
        .padding(16)
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Lock Screen Accessories (Dark)") {
    VStack(spacing: 18) {
        HStack(spacing: 16) {
            VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.chargingActive, topic: .charging, family: .accessoryCircular)
                .frame(width: 60, height: 60)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
            VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.base, topic: .charging, family: .accessoryCircular)
                .frame(width: 60, height: 60)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        VStack(spacing: 12) {
            VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.base, topic: .overview, family: .accessoryRectangular)
                .frame(width: 170, height: 66)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.lockConfirmed, topic: .overview, family: .accessoryRectangular)
                .frame(width: 170, height: 66)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VehicleWidgetPanel(snapshot: WidgetPreviewFixtures.unlockedAlertAndError, topic: .security, family: .accessoryRectangular)
                .frame(width: 170, height: 66)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
        LinearGradient(
            colors: [Color(red: 0.08, green: 0.11, blue: 0.18), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    )
    .preferredColorScheme(.dark)
}
#endif
