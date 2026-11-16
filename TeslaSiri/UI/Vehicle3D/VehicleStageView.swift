import RealityKit
import SwiftUI

/// Hosts a `VehicleStage` in a transparent RealityView so the car sits directly on the
/// page. Horizontal drags turn the car (vertical drags still scroll the page), pinch zooms,
/// double-tap recenters, and the stage glides back to its pose after a few seconds.
/// While the model loads, or if it can't, `placeholder` shows instead.
///
/// One loaded stage is shared by every screen that shows the same car. Whichever screen
/// appears last hosts it: the car moves into that screen's RealityView and takes on that
/// screen's state, such as live data on the Vehicle tab or a recorded drive on Drives.
struct VehicleStageView<Placeholder: View, Overlay: View>: View {
    let spec: VehicleModelSpec
    let state: VehicleStageState
    let stage: VehicleStage
    var framingZoom: Float = 1
    var accessibilityDescription: String
    /// Washes the background in the paint color, like the Tesla app's showroom.
    var showsAmbientLight = false
    var isRendering = true
    /// Runs every rendered frame while this view hosts the stage, before the stage moves.
    var onFrame: ((VehicleStage, Double) -> Void)?
    var onHotspot: ((VehicleHotspot) -> Void)?
    @ViewBuilder var hotspotLabel: (VehicleHotspot) -> Overlay
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var host = VehicleStageHost()
    @State private var isOnscreen = false
    @State private var lastMagnification: CGFloat = 1
    @State private var viewSize: CGSize = .zero

    private var isHost: Bool { stage.hostID == ObjectIdentifier(host) }
    private var isShowingStage: Bool { stage.isReady && isHost }

    var body: some View {
        ZStack {
            ambientLight
                .opacity(isShowingStage && showsAmbientLight && state.mode != .driving ? 1 : 0)
                .animation(.smooth(duration: 0.8), value: isShowingStage && showsAmbientLight && state.mode != .driving)

            placeholder()
                .opacity(isShowingStage && isRendering ? 0 : 1)
                .animation(.smooth(duration: 0.6), value: isShowingStage)

            if isOnscreen && isHost && isRendering {
                VehicleStageCanvas(stage: stage, host: host, isVisible: isShowingStage)
            }

            if isShowingStage && isRendering {
                VehicleHotspotLayer(stage: stage, viewWidth: viewSize.width, onHotspot: onHotspot, hotspotLabel: hotspotLabel)
            }
        }
        .contentShape(.rect)
        .gesture(VehicleOrbitPanGesture(stage: stage))
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    stage.beginInteraction()
                    stage.zoom(by: value.magnification / max(lastMagnification, 0.01))
                    lastMagnification = value.magnification
                }
                .onEnded { _ in
                    lastMagnification = 1
                    stage.endInteraction()
                }
        )
        .onTapGesture(count: 2) {
            stage.resetView()
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            viewSize = size
            if isHost { stage.viewSize = size }
        }
        .onAppear {
            isOnscreen = true
            hostStage()
        }
        .onDisappear {
            isOnscreen = false
            stage.detach(from: host)
        }
        .onChange(of: state) { _, newValue in
            if isHost { stage.apply(newValue) }
        }
        .onChange(of: colorScheme) { _, scheme in
            if isHost { stage.setAppearance(dark: scheme == .dark) }
        }
        .onChange(of: reduceMotion) { _, value in
            if isHost { stage.reduceMotion = value }
        }
        .onChange(of: framingZoom) { _, value in
            if isHost { stage.framingZoom = value }
        }
        .task(id: spec) {
            await stage.load(spec)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Moves the shared stage into this view and applies this view's state.
    private func hostStage() {
        stage.attach(to: host)
        if let onFrame {
            let stage = stage
            stage.onFrame = { [weak stage] deltaTime in
                guard let stage else { return }
                onFrame(stage, deltaTime)
            }
        }
        stage.viewSize = viewSize
        stage.reduceMotion = reduceMotion
        stage.framingZoom = framingZoom
        stage.setAppearance(dark: colorScheme == .dark)
        stage.apply(state)
    }

    /// The paint color as soft studio light behind and around the car.
    @ViewBuilder
    private var ambientLight: some View {
        if let paint = stage.paintHighlight {
            let strength = colorScheme == .dark ? 0.34 : 0.14
            EllipticalGradient(
                stops: [
                    .init(color: Color(uiColor: paint).opacity(strength), location: 0),
                    .init(color: Color(uiColor: paint).opacity(strength * 0.45), location: 0.45),
                    .init(color: .clear, location: 1)
                ],
                center: UnitPoint(x: 0.5, y: 0.55),
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Reads projected placements here so camera motion only invalidates the callouts.
private struct VehicleHotspotLayer<Overlay: View>: View {
    let stage: VehicleStage
    let viewWidth: CGFloat
    let onHotspot: ((VehicleHotspot) -> Void)?
    @ViewBuilder var hotspotLabel: (VehicleHotspot) -> Overlay

    var body: some View {
        let placements = stage.hotspots
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for placement in placements {
                    guard let leader = callout(for: placement).leader else { continue }
                    var path = Path()
                    path.move(to: leader.start)
                    path.addLine(to: leader.end)
                    context.stroke(path, with: .color(.primary.opacity(0.5)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            ForEach(placements) { placement in
                let geometry = callout(for: placement)
                Button {
                    onHotspot?(placement.hotspot)
                } label: {
                    hotspotLabel(placement.hotspot)
                        .frame(width: geometry.labelWidth, alignment: geometry.alignment)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(onHotspot == nil)
                .position(geometry.label)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: placements.map(\.hotspot))
    }

    private struct Callout {
        var label: CGPoint
        var labelWidth: CGFloat?
        var alignment: Alignment = .center
        var leader: (start: CGPoint, end: CGPoint)?
    }

    private func callout(for placement: VehicleHotspotPlacement) -> Callout {
        let width = max(viewWidth, 1)
        let anchor = placement.point
        switch placement.hotspot {
        case .lock:
            let top: CGFloat = 18
            let leader = anchor.y > top + 34
                ? (start: CGPoint(x: anchor.x, y: top + 18), end: CGPoint(x: anchor.x, y: anchor.y - 4))
                : nil
            return Callout(label: CGPoint(x: anchor.x, y: top), labelWidth: 44, leader: leader)
        case .frunk, .trunk, .chargePort:
            // Above the car, with a hairline leader down to the part. Text sits on whichever
            // side of the leader has room.
            let x = min(max(anchor.x, 10), width - 10)
            let labelWidth: CGFloat = placement.hotspot == .chargePort ? 96 : 64
            let textOnRight = x + labelWidth + 8 < width
            let labelY: CGFloat = 52
            let leader = anchor.y > 44
                ? (start: CGPoint(x: x, y: 32), end: CGPoint(x: x, y: anchor.y - 2))
                : nil
            return Callout(
                label: CGPoint(x: textOnRight ? x + 6 + labelWidth / 2 : x - 6 - labelWidth / 2, y: labelY),
                labelWidth: labelWidth,
                alignment: textOnRight ? .leading : .trailing,
                leader: leader
            )
        }
    }
}

/// The RealityView itself. Its inputs change only when the stage loads or moves between
/// screens, so per-frame state changes elsewhere (speed, scrubbing) never rebuild it.
private struct VehicleStageCanvas: View {
    let stage: VehicleStage
    let host: VehicleStageHost
    let isVisible: Bool

    @State private var surface = VehicleStageSurface()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            // SwiftUI builds a new RealityView whenever this canvas comes back (returning to
            // the tab, scrolling back into view, the app becoming active). Entities that were
            // in an earlier RealityView don't draw in a later one, so each gets its own
            // anchor and camera and the stage moves the car across.
            let anchor = Entity()
            let camera = PerspectiveCamera()
            anchor.addChild(camera)
            content.add(anchor)
            surface.subscription?.cancel()
            surface.anchor = anchor
            surface.camera = camera
            host.surface = surface
            stage.mount(for: host)
            surface.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak surface] event in
                let deltaTime = event.deltaTime
                // The stage publishes SwiftUI state, so every frame step runs on the main actor.
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        guard let surface, host.surface === surface, stage.hostID == ObjectIdentifier(host) else { return }
                        stage.tick(deltaTime)
                    }
                } else {
                    Task { @MainActor in
                        guard let surface, host.surface === surface, stage.hostID == ObjectIdentifier(host) else { return }
                        stage.tick(deltaTime)
                    }
                }
            }
        }
        .mask { VehicleStageEdgeFade() }
        .opacity(isVisible ? 1 : 0)
        .animation(.smooth(duration: 0.6), value: isVisible)
        .accessibilityHidden(true)
    }
}

/// Identifies one view that can show a stage, and points at the RealityView it currently
/// has on screen.
@MainActor
final class VehicleStageHost {
    weak var surface: VehicleStageSurface?
}

/// One RealityView's anchor, camera and frame subscription. It lives exactly as long as
/// that RealityView, and the entities are created when the RealityView is.
@MainActor
final class VehicleStageSurface {
    var anchor: Entity?
    var camera: PerspectiveCamera?
    var subscription: EventSubscription?

    deinit {
        subscription?.cancel()
    }
}

/// Dissolves the scene's edges into the page so the road and floor have no hard border.
private struct VehicleStageEdgeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.07),
                .init(color: .black, location: 0.93),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// A pan that only begins when the drag is mostly horizontal, so it never steals
/// vertical scrolling from the surrounding scroll view.
struct VehicleOrbitPanGesture: UIGestureRecognizerRepresentable {
    let stage: VehicleStage

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastTranslation: CGFloat = 0

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            var motion = pan.velocity(in: pan.view)
            if motion == .zero { motion = pan.translation(in: pan.view) }
            guard motion != .zero else { return false }
            return abs(motion.x) > abs(motion.y) * 1.2
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            context.coordinator.lastTranslation = translation
            stage.beginInteraction()
        case .changed:
            stage.orbit(by: translation - context.coordinator.lastTranslation)
            context.coordinator.lastTranslation = translation
        default:
            stage.endInteraction()
        }
    }
}
