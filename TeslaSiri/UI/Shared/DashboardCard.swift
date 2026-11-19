import SwiftUI

/// At-a-glance showroom card used across the app: quiet symbol + title header,
/// optional trailing status/action accessory, and free-form content below.
struct DashboardCard<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        _ title: String,
        systemImage: String,
        tint: Color = .secondary,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                DashboardCardHeader(title: title, systemImage: systemImage, tint: tint)
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
        _ title: String,
        systemImage: String,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, systemImage: systemImage, tint: tint, accessory: { EmptyView() }, content: content)
    }
}

/// Quiet automotive-styled symbol + title header shared by dashboard and detail cards.
struct DashboardCardHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(.semibold))
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
    let title: String
    let systemImage: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
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

