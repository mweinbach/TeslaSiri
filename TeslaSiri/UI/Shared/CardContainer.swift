import SwiftUI

struct AppScreenBackground: View {
    var body: some View {
        AppTheme.pageBackground
            .ignoresSafeArea()
    }
}

struct CardContainer<Content: View>: View {
    let title: String?
    let systemImage: String?
    var tint: Color = .secondary
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        tint: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                if let systemImage {
                    DashboardCardHeader(title: title, systemImage: systemImage, tint: tint)
                } else {
                    Text(title)
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
    let text: String
    let systemImage: String?
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    init(_ text: String, systemImage: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
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
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

