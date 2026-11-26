import SwiftUI

struct AppScreenBackground: View {
    var body: some View {
        AppTheme.pageBackground
            .ignoresSafeArea()
    }
}

struct CardContainer<Content: View>: View {
    let title: Text?
    let systemImage: String?
    var tint: Color = .secondary
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title.map { Text($0) }
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    @_disfavoredOverload
    init<S: StringProtocol>(
        title: S,
        systemImage: String? = nil,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                if let systemImage {
                    DashboardCardHeader(titleText: title, systemImage: systemImage, tint: tint)
                } else {
                    title
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appSurface()
    }
}

struct StatusBadge: View {
    let label: Text
    let systemImage: String?
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    init(_ text: LocalizedStringKey, systemImage: String? = nil, tint: Color = .secondary) {
        self.label = Text(text)
        self.systemImage = systemImage
        self.tint = tint
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ text: S, systemImage: String? = nil, tint: Color = .secondary) {
        self.label = Text(text)
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            label
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.30 : 0.18), lineWidth: 0.5)
        }
        .foregroundStyle(tint)
    }
}

struct LoadingRow: View {
    let label: Text

    init(label: LocalizedStringKey) {
        self.label = Text(label)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(label: S) {
        self.label = Text(label)
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            label
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

