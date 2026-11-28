import SwiftUI

@available(macOS 14.0, *)
@MainActor
struct ScopedDisclosure: View {
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .animation(reduceMotion ? nil : .smooth(duration: 0.18)) { content in
                            content.rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                    Text("Details")
                }
            }
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                Text("Additional details appear here.")
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

@available(macOS 14.0, *)
@MainActor
struct CompletionAwarePanel: View {
    @State private var expanded = false
    @State private var revision = 0
    @State private var settled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading) {
            Button(expanded ? "Collapse" : "Expand") { toggle() }
            RoundedRectangle(cornerRadius: 12)
                .fill(.tint)
                .frame(width: expanded ? 240 : 120, height: 70)
            Text(settled ? "Ready" : "Changing")
                .transaction { $0.animation = nil }
        }
        .onDisappear { revision += 1 }
    }

    private func toggle() {
        revision += 1
        let request = revision
        settled = false
        withAnimation(
            reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08),
            completionCriteria: .logicallyComplete
        ) {
            expanded.toggle()
        } completion: {
            guard request == revision else { return }
            settled = true
        }
    }
}

private struct ConfirmationValues: Sendable {
    var scale: CGFloat = 1
    var verticalOffset: CGFloat = 0
}

@available(macOS 14.0, *)
@MainActor
struct KeyframeConfirmation: View {
    @State private var count = 0
    @State private var motionTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let suppressMotion = reduceMotion // Sendable snapshot for frame callback.
        Button {
            count += 1
            if !reduceMotion { motionTrigger += 1 }
        } label: {
            Label("Confirm", systemImage: "checkmark.circle.fill")
                .keyframeAnimator(
                    initialValue: ConfirmationValues(),
                    trigger: motionTrigger
                ) { content, value in
                    content
                        .scaleEffect(suppressMotion ? 1 : value.scale)
                        .offset(y: suppressMotion ? 0 : value.verticalOffset)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.12, duration: 0.12)
                        CubicKeyframe(1, duration: 0.24)
                    }
                    KeyframeTrack(\.verticalOffset) {
                        CubicKeyframe(-4, duration: 0.16)
                        CubicKeyframe(0, duration: 0.20)
                    }
                }
        }
        .accessibilityValue(Text("\(count) confirmations"))
    }
}

// Requires an SDK/compiler that provides @Animatable. The macro's deployment
// behavior is verified by compiling against the intended runtime baseline.
@Animatable
struct AnimatedInsetShape: Shape {
    var inset: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        let bounded = min(max(inset, 0), min(rect.width, rect.height) / 2)
        let inner = rect.insetBy(dx: bounded, dy: bounded)
        return Path(roundedRect: inner, cornerRadius: inner.height / 2)
    }
}

/// Explicit interpolation only because this example applies custom bounds.
@available(macOS 26.0, *)
struct BoundedInsetShape: Shape {
    var inset: CGFloat
    var radius: CGFloat

    var animatableData: AnimatableValues<CGFloat, CGFloat> {
        get { AnimatableValues(inset, radius) }
        set {
            inset = max(0, newValue.value.0)
            radius = max(0, newValue.value.1)
        }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let bounded = min(inset, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect.insetBy(dx: bounded, dy: bounded), cornerRadius: radius)
    }
}
