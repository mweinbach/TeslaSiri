import SwiftUI

struct DiagnosticMonospacedValue: View {
    let title: String
    let value: String

    var body: some View {
        // Short values sit on the trailing edge; long ones (scopes, URLs, paths) wrap below the label.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleText
                Spacer(minLength: 8)
                valueText
                    .lineLimit(1)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                titleText
                valueText
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value)
            .font(.footnote.monospaced())
            .textSelection(.enabled)
    }
}

/// Quiet section label used to split diagnostic cards into scannable engineering groups.
struct DiagnosticGroupHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

