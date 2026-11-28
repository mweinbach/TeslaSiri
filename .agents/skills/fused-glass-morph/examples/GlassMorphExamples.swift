import SwiftUI

// Standalone reference fixtures. Dimensions and curves are illustrative.
@available(macOS 26.0, *)
@MainActor
struct PersistentGlassPairExample: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var expanded = false
    @State private var progress = 0.0
    @State private var revision = 0
    @State private var secondaryIsReady = false

    var body: some View {
        PersistentFusionTrack(
            progress: progress,
            namespace: glassNamespace,
            secondaryIsReady: secondaryIsReady,
            onToggle: { request(!expanded) },
            onSecondary: {
                onComplete()
                request(false)
            }
        )
        .onAppear { request(expanded, animated: false) }
        .onChange(of: reduceMotion) { _, _ in
            request(expanded, animated: false)
        }
        .onDisappear {
            revision &+= 1
            secondaryIsReady = false
        }
    }

    private func request(_ destination: Bool, animated: Bool = true) {
        revision &+= 1
        let requestRevision = revision
        expanded = destination
        secondaryIsReady = false

        guard animated && !reduceMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                progress = destination ? 1 : 0
                secondaryIsReady = destination
            }
            return
        }

        // This transaction owns only the local leaf's progress mutation.
        withAnimation(.spring(duration: 0.32, bounce: 0.08), completionCriteria: .removed) {
            progress = destination ? 1 : 0
        } completion: {
            guard revision == requestRevision, expanded == destination else { return }
            secondaryIsReady = destination
        }
    }
}

@available(macOS 26.0, *)
@Animatable
private nonisolated struct PersistentFusionTrack: View {
    var progress: Double
    let namespace: Namespace.ID
    let secondaryIsReady: Bool
    let onToggle: () -> Void
    let onSecondary: () -> Void

    @MainActor var body: some View {
        let t = min(max(progress, 0), 1)
        let hostWidth: CGFloat = 152
        let height: CGFloat = 44
        let seed: CGFloat = 10
        let gap: CGFloat = 18
        let diameter = seed + (height - seed) * t
        let startX = hostWidth - seed
        let endX = hostWidth + gap
        let glyphOpacity = min(max((t - 0.5) / 0.25, 0), 1)

        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .topLeading) {
                Button(action: onToggle) {
                    Label("Actions", systemImage: "ellipsis")
                }
                .buttonStyle(ExampleGlassControlStyle(id: "primary", namespace: namespace))
                .frame(width: hostWidth, height: height)
                .help("Reveal or hide the secondary action")

                Button(action: onSecondary) {
                    Image(systemName: "checkmark")
                        .opacity(glyphOpacity)
                }
                .buttonStyle(ExampleGlassControlStyle(id: "secondary", namespace: namespace))
                .frame(width: diameter, height: diameter)
                .offset(x: startX + (endX - startX) * t, y: (height - diameter) / 2)
                .disabled(!secondaryIsReady)
                .allowsHitTesting(secondaryIsReady)
                .accessibilityHidden(!secondaryIsReady)
                .accessibilityLabel("Complete the secondary action")
            }
            // The peeled guest never changes this example's layout reservation.
            .frame(width: hostWidth + gap + height, height: height, alignment: .topLeading)
        }
    }
}

@available(macOS 26.0, *)
@MainActor
private struct ExampleGlassControlStyle: ButtonStyle {
    let id: String
    let namespace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectID(id, in: namespace)
    }
}

@available(macOS 26.0, *)
@MainActor
struct InsertedGlassActionExample: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var expanded = false

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                Button(action: toggle) {
                    Label("Actions", systemImage: "ellipsis")
                }
                .buttonStyle(ExampleGlassControlStyle(id: "source", namespace: glassNamespace))
                .frame(width: 152, height: 44)

                if expanded {
                    Button {
                        onComplete()
                        setExpanded(false)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(ExampleGlassControlStyle(id: "inserted", namespace: glassNamespace))
                    .frame(width: 44, height: 44)
                    .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                    .accessibilityLabel("Complete the secondary action")
                }
            }
        }
    }

    private func toggle() {
        setExpanded(!expanded)
    }

    private func setExpanded(_ destination: Bool) {
        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { expanded = destination }
        } else {
            withAnimation(.smooth(duration: 0.3)) { expanded = destination }
        }
    }
}

/// A compact trigger in a host's glass becomes a round lens that grows while
/// it travels to a card's center, then takes the card's shape. One value
/// drives every stage, so a reversal springs back from what is on screen.
@available(macOS 26.0, *)
@MainActor
struct StagedLensCardExample: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var isOpen = false
    @State private var morph: CGFloat = 0

    var body: some View {
        let hostShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        GlassEffectContainer(spacing: 8) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: 320, height: 44)
                    .glassEffect(.regular.interactive(), in: hostShape)
                    .glassEffectID("host", in: glassNamespace)
                StagedLens(morph: morph, isOpen: isOpen, namespace: glassNamespace) { setOpen(!isOpen) }
            }
            // The lens draws above the host; opening never changes this reservation.
            .frame(width: 320, height: 44, alignment: .topLeading)
        }
        .onChange(of: reduceMotion) { _, reduce in
            if reduce { snap(to: isOpen) }
        }
    }

    private func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        guard !reduceMotion else { return snap(to: open) }
        isOpen = open
        // A bounce on open to settle like the system menu; none on close, so
        // nothing lingers over the host.
        withAnimation(open ? .spring(duration: 0.5, bounce: 0.16) : .spring(duration: 0.36, bounce: 0)) {
            morph = open ? 1 : 0
        }
    }

    private func snap(to open: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isOpen = open
            morph = open ? 1 : 0
        }
    }
}

@available(macOS 26.0, *)
@Animatable
private nonisolated struct StagedLens: View {
    var morph: CGFloat
    let isOpen: Bool
    let namespace: Namespace.ID
    let onToggle: () -> Void

    /// Rest and open poses in the host's coordinates.
    private static let slot = CGRect(x: 12, y: 11, width: 22, height: 22)
    private static let card = CGRect(x: 0, y: -170, width: 260, height: 160)
    private static let glyphRest: CGFloat = 14
    private static let glyphOpen: CGFloat = 36

    @MainActor var body: some View {
        // Each part follows its own stretch of the one value.
        let grown = Self.lead(morph, until: 0.6)
        let travelled = Self.ease(Self.lead(morph, until: 0.85))
        let formed = max(0, (morph - 0.5) / 0.5)
        let shaped = Self.clamp(formed)

        let slot = Self.slot, card = Self.card
        let center = CGPoint(x: Self.mix(slot.midX, card.midX, travelled), y: Self.mix(slot.midY, card.midY, travelled))
        // Round until the lens reaches the card's shorter side.
        let lens = Self.mix(slot.width, min(card.width, card.height), grown)
        let size = CGSize(width: Self.mix(lens, card.width, formed), height: Self.mix(lens, card.height, formed))
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let shape = RoundedRectangle(cornerRadius: Self.mix(min(size.width, size.height) / 2, 18, shaped), style: .continuous)

        let glyph = Self.mix(Self.glyphRest, Self.glyphOpen, grown)
        let hit = Self.mix(slot.width, 44, grown)
        let corner = CGPoint(x: card.maxX - 16 - Self.glyphOpen / 2, y: card.maxY - 16 - Self.glyphOpen / 2)
        let glyphCenter = CGPoint(x: center.x + (corner.x - card.midX) * shaped, y: center.y + (corner.y - card.midY) * shaped)
        let rowsOpacity = Self.reveal(morph, from: 0.25, to: 0.6)

        ZStack(alignment: .topLeading) {
            // Built only while visible, so a closed card leaves nothing to lay
            // out or for accessibility to find.
            if rowsOpacity > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details").font(.headline)
                    Text("The rows ride inside the lens magnified and blurred, and sharpen as it takes the card's shape.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(width: card.width, height: card.height, alignment: .topLeading)
                .scaleEffect(Self.mix(1.18, 1, shaped))
                .blur(radius: 12 * (1 - shaped))
                .opacity(rowsOpacity)
                .offset(x: center.x - card.width / 2 - frame.minX, y: center.y - card.height / 2 - frame.minY)
                // Above the host only; the part of the lens still inside it
                // shows the glyph alone.
                .mask(alignment: .top) {
                    Rectangle().frame(height: max(0, -frame.minY))
                }
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
            }

            // The same button from rest to open. Its frame, not a larger
            // content shape, sets the hit area.
            Button(action: onToggle) {
                Image(systemName: "circle.dashed")
                    .resizable()
                    .frame(width: glyph, height: glyph)
                    .frame(width: hit, height: hit)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .offset(x: glyphCenter.x - hit / 2 - frame.minX, y: glyphCenter.y - hit / 2 - frame.minY)
            .accessibilityLabel(isOpen ? "Hide details" : "Show details")
        }
        .frame(width: max(4, frame.width), height: max(4, frame.height), alignment: .topLeading)
        .clipShape(shape)
        .contentShape(shape)
        .glassEffect(.regular.interactive(), in: shape)
        .glassEffectID("lens", in: namespace)
        .offset(x: frame.minX, y: frame.minY)
        // This leaf computes every frame from `morph`; nothing inside it runs
        // an animation of its own.
        .transaction { $0.animation = nil }
    }

    /// Reaches 1 at `end` and holds, keeping any overshoot past 1.
    private static func lead(_ progress: CGFloat, until end: CGFloat) -> CGFloat {
        min(max(progress, 0) / end, 1) + max(0, progress - 1)
    }

    /// Smoothstep below 1, unchanged past it so overshoot still shows.
    private static func ease(_ progress: CGFloat) -> CGFloat {
        progress < 1 ? progress * progress * (3 - 2 * progress) : progress
    }

    private static func clamp(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    private static func mix(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private static func reveal(_ progress: CGFloat, from start: CGFloat, to end: CGFloat) -> Double {
        Double(min(max((progress - start) / (end - start), 0), 1))
    }
}

@available(macOS 26.0, *)
@MainActor
struct StaticGlassUnionExample: View {
    @Namespace private var glassNamespace
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(ExampleGlassControlStyle(id: "previous", namespace: glassNamespace))
                .frame(width: 44, height: 44)
                .glassEffectUnion(id: "navigation", namespace: glassNamespace)
                .accessibilityLabel("Previous item")

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(ExampleGlassControlStyle(id: "next", namespace: glassNamespace))
                .frame(width: 44, height: 44)
                .glassEffectUnion(id: "navigation", namespace: glassNamespace)
                .accessibilityLabel("Next item")
            }
        }
    }
}
