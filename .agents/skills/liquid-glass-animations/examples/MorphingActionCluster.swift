import SwiftUI

/// Production-ready Liquid Glass morphing action cluster demonstrating:
/// - Scoped `GlassEffectContainer(spacing:)` for batched GPU refraction and organic liquid pooling
/// - `glassEffectID` + `glassEffectUnion` for clean shape lineage across expansion states
/// - Safe inner-glyph rotation (rotating the `Image`, NEVER the `.glassEffect()` surface itself)
/// - Full `accessibilityReduceMotion` gating + restrained `.sensoryFeedback` haptics
@available(iOS 26, *)
struct MorphingActionCluster: View {
    let onNewNote: () -> Void
    let onAddPhoto: () -> Void
    let onScanDoc: () -> Void

    @State private var isExpanded = false
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                if isExpanded {
                    // Secondary actions emerge as one unified glass capsule pool
                    HStack(spacing: 4) {
                        actionButton("Note", systemImage: "square.and.pencil", id: "note") {
                            collapseAndRun(onNewNote)
                        }
                        actionButton("Photo", systemImage: "photo", id: "photo") {
                            collapseAndRun(onAddPhoto)
                        }
                        actionButton("Scan", systemImage: "doc.viewfinder", id: "scan") {
                            collapseAndRun(onScanDoc)
                        }
                    }
                    .glassEffectUnion(id: "secondaryCluster", namespace: glassNamespace)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                }

                // Primary FAB: single accent tint when collapsed, neutral close circle when expanded
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3, extraBounce: 0)) {
                        isExpanded.toggle()
                    }
                } label: {
                    // Rotate ONLY the inner glyph — never apply .rotationEffect() on the glass view itself
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isExpanded ? Color.primary : Color.white)
                        .rotationEffect(.degrees(isExpanded ? 45 : 0))
                        .frame(width: 52, height: 52)
                }
                .accessibilityLabel(isExpanded ? "Close actions" : "Create")
                .glassEffect(
                    isExpanded
                        ? .regular.interactive()
                        : .regular.tint(.accentColor).interactive(),
                    in: .circle
                )
                .glassEffectID("fabToggle", in: glassNamespace)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: isExpanded)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(title)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(id, in: glassNamespace)
    }

    private func collapseAndRun(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            isExpanded = false
        }
        action()
    }
}
