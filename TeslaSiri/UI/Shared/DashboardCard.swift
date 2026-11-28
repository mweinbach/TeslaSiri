import SwiftUI

/// At-a-glance showroom card used across the app: quiet symbol + title header,
/// optional trailing status/action accessory, and free-form content below.
struct DashboardCard<Content: View, Accessory: View>: View {
    let title: Text
    let systemImage: String
    var tint: Color = .secondary
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color = .secondary,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    @_disfavoredOverload
    init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        tint: Color = .secondary,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                DashboardCardHeader(titleText: title, systemImage: systemImage, tint: tint)
                Spacer(minLength: 8)
                accessory
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appSurface(cornerRadius: AppTheme.cardCornerRadius)
    }
}

extension DashboardCard where Accessory == EmptyView {
    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, systemImage: systemImage, tint: tint, accessory: { EmptyView() }, content: content)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, systemImage: systemImage, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

/// Quiet automotive-styled symbol + title header shared by dashboard and detail cards.
struct DashboardCardHeader: View {
    let titleText: Text
    let systemImage: String
    var tint: Color = .secondary

    init(titleText: Text, systemImage: String, tint: Color = .secondary) {
        self.titleText = titleText
        self.systemImage = systemImage
        self.tint = tint
    }

    init(title: LocalizedStringKey, systemImage: String, tint: Color = .secondary) {
        self.titleText = Text(title)
        self.systemImage = systemImage
        self.tint = tint
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, systemImage: String, tint: Color = .secondary) {
        self.titleText = Text(title)
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            titleText
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Large rounded tabular numeral with a smaller trailing unit, used for headline metrics.
struct MetricValueText: View {
    let value: String
    var unit: String? = nil
    var font: Font = .system(.largeTitle, design: .rounded, weight: .semibold)
    var unitFont: Font = .headline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(unitFont)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Plain-styled navigation row with a trailing chevron, for links inside dashboard cards.
struct DashboardCardLinkLabel: View {
    let titleText: Text
    let systemImage: String
    var detail: String? = nil

    init(title: LocalizedStringKey, systemImage: String, detail: String? = nil) {
        self.titleText = Text(title)
        self.systemImage = systemImage
        self.detail = detail
    }

    @_disfavoredOverload
    init<S: StringProtocol>(title: S, systemImage: String, detail: String? = nil) {
        self.titleText = Text(title)
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            titleText
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .contentShape(.rect)
    }
}

