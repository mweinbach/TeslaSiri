import SwiftUI

/// Demonstrates GPU-efficient Liquid Glass state animations for 120Hz ProMotion:
/// 1. Toggles glass via `.identity` instead of conditionally adding/removing `.glassEffect()`
/// 2. Uses discrete trigger-based `PhaseAnimator` so the GPU is 100% idle at rest (no `.repeatForever()`)
/// 3. Uses `.materialize` for transient HUD banners that shouldn't stretch across the screen
@available(iOS 26, *)
struct EfficientGlassStateToggle: View {
    enum FilterScope: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case pinned = "Pinned"
        var id: Self { self }
    }

    @State private var selectedScope: FilterScope = .all
    @State private var saveConfirmCount = 0
    @State private var showTransientBanner = false
    @Namespace private var filterNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            // 1. Batched segmented filter bar using `.identity` for inactive chips (zero view-tree churn)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(FilterScope.allCases) { scope in
                        let isSelected = (scope == selectedScope)
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                                selectedScope = scope
                            }
                        } label: {
                            Text(scope.rawValue)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                        }
                        // ✅ Toggle via `.identity` instead of branching `if isSelected`
                        .glassEffect(isSelected ? .regular.interactive() : .identity, in: .capsule)
                        .glassEffectID(isSelected ? "activeScope" : scope.rawValue, in: filterNS)
                    }
                }
                .padding(4)
            }
            .sensoryFeedback(.selection, trigger: selectedScope)

            // 2. Event-driven confirmation bounce via PhaseAnimator — zero idle GPU cost
            Button {
                saveConfirmCount += 1
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    showTransientBanner = true
                }
            } label: {
                Label("Save Preset", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 44)
            }
            .buttonStyle(.glassProminent)
            .phaseAnimator([false, true], trigger: saveConfirmCount) { content, active in
                // Keep transform subtle and strictly event-triggered
                content.scaleEffect(active && !reduceMotion ? 1.04 : 1.0)
            } animation: { _ in
                .snappy(duration: 0.2)
            }
            .sensoryFeedback(.success, trigger: saveConfirmCount)

            // 3. Unrelated transient HUD uses `.materialize`, NOT geometric morphing
            if showTransientBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Preset saved")
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular, in: .capsule)
                .glassEffectTransition(reduceMotion ? .identity : .materialize)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                .task(id: saveConfirmCount) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        showTransientBanner = false
                    }
                }
            }
        }
    }
}
