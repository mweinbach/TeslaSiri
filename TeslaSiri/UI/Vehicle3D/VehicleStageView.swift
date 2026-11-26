import RealityKit
import SwiftUI

/// Hosts a `VehicleStage` in a transparent RealityView so the car sits directly on the
/// page at its authored showroom, charging, or driving angle.
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
                VehicleStageCanvas(
                    stage: stage,
                    host: host,
                    isVisible: isShowingStage,
                    fadesEdges: state.mode == .driving
                )
            }

            if isShowingStage && isRendering {
                VehicleHotspotLayer(stage: stage, viewWidth: viewSize.width, onHotspot: onHotspot, hotspotLabel: hotspotLabel)
            }
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

    /// Soft horizontal studio horizon glow behind the car, matching Tesla's parked showroom.
    @ViewBuilder
    private var ambientLight: some View {
        if let paint = stage.paintHighlight {
            let colorInfo = Self.backdropTint(for: paint, dark: colorScheme == .dark)
            if colorInfo.opacity > 0 {
                EllipticalGradient(
                    stops: [
                        .init(color: colorInfo.color.opacity(colorInfo.opacity), location: 0),
                        .init(color: colorInfo.color.opacity(colorInfo.opacity * 0.45), location: 0.44),
                        .init(color: .clear, location: 1)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.55),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.56
                )
                .scaleEffect(x: 1.25, y: 0.88)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private static func backdropTint(for paint: UIColor, dark: Bool) -> (color: Color, opacity: Double) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        paint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation > 0.16 {
            return (Color(uiColor: paint), dark ? 0.20 : 0.06)
        }
        return dark ? (Color(red: 0.72, green: 0.76, blue: 0.84), 0.11) : (.clear, 0)
    }
}

/// Reads projected placements here so camera motion only invalidates the callouts.
private struct VehicleHotspotLayer<Overlay: View>: View {
    let stage: VehicleStage
    let viewWidth: CGFloat
    let onHotspot: ((VehicleHotspot) -> Void)?
    @ViewBuilder var hotspotLabel: (VehicleHotspot) -> Overlay

    @State private var measuredWidths: [VehicleHotspot: CGFloat] = [:]

    var body: some View {
        let layout = resolvedCallouts(for: stage.hotspots)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for item in layout {
                    guard let leader = item.leader else { continue }
                    var path = Path()
                    path.move(to: leader.start)
                    path.addLine(to: leader.end)
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [.primary.opacity(0.28), .primary.opacity(0.08)]),
                            startPoint: leader.start,
                            endPoint: leader.end
                        ),
                        lineWidth: 0.75
                    )
                    let dotRect = CGRect(x: leader.end.x - 1.75, y: leader.end.y - 1.75, width: 3.5, height: 3.5)
                    context.fill(Path(ellipseIn: dotRect), with: .color(.primary.opacity(0.28)))
                }
            }
            .allowsHitTesting(false)

            ForEach(layout) { item in
                Button {
                    onHotspot?(item.hotspot)
                } label: {
                    hotspotLabel(item.hotspot)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(onHotspot == nil)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard width > 1 else { return }
                    let current = measuredWidths[item.hotspot] ?? 0
                    if abs(current - width) > 0.5 {
                        measuredWidths[item.hotspot] = width
                    }
                }
                .position(item.labelCenter)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.22), value: layout.map(\.hotspot))
    }

    private struct ResolvedCallout: Identifiable {
        let hotspot: VehicleHotspot
        var labelCenter: CGPoint
        let estimatedWidth: CGFloat
        let anchor: CGPoint
        var leader: (start: CGPoint, end: CGPoint)?

        var id: VehicleHotspot { hotspot }
    }

    /// Arranges callout pills along a clean top rail above the car and spreads out any
    /// horizontal collisions (such as Trunk and Charge Port near each other) so pills never overlap.
    private func resolvedCallouts(for placements: [VehicleHotspotPlacement]) -> [ResolvedCallout] {
        guard !placements.isEmpty else { return [] }
        let width = max(viewWidth, 1)
        let horizontalInset: CGFloat = 14
        let gap: CGFloat = 10

        var items = placements.map { placement -> ResolvedCallout in
            let fallbackWidth: CGFloat = switch placement.hotspot {
            case .lock: 36
            case .frunk: 60
            case .trunk: 60
            case .chargePort: 64
            }
            let estimatedWidth = measuredWidths[placement.hotspot] ?? fallbackWidth
            let rowY: CGFloat = placement.hotspot == .lock ? 16 : 20
            let clampedX = min(max(placement.point.x, horizontalInset + estimatedWidth / 2), width - horizontalInset - estimatedWidth / 2)
            return ResolvedCallout(
                hotspot: placement.hotspot,
                labelCenter: CGPoint(x: clampedX, y: rowY),
                estimatedWidth: estimatedWidth,
                anchor: placement.point,
                leader: nil
            )
        }

        // Sort left-to-right and push overlapping pills apart cleanly.
        items.sort { $0.labelCenter.x < $1.labelCenter.x }
        for index in 1..<items.count {
            let minCenter = items[index - 1].labelCenter.x
                + items[index - 1].estimatedWidth / 2
                + gap
                + items[index].estimatedWidth / 2
            if items[index].labelCenter.x < minCenter {
                items[index].labelCenter.x = minCenter
            }
        }
        // Pull back inside the right margin if separation overflowed right.
        if let last = items.last {
            let maxRight = width - horizontalInset - last.estimatedWidth / 2
            if last.labelCenter.x > maxRight {
                let overflow = last.labelCenter.x - maxRight
                for index in items.indices {
                    items[index].labelCenter.x = max(
                        horizontalInset + items[index].estimatedWidth / 2,
                        items[index].labelCenter.x - overflow
                    )
                }
            }
        }

        for index in items.indices {
            let center = items[index].labelCenter
            let anchor = items[index].anchor
            let startY = center.y + 16
            if anchor.y > startY + 8 {
                items[index].leader = (
                    start: CGPoint(x: center.x, y: startY),
                    end: CGPoint(x: anchor.x, y: anchor.y - 3)
                )
            }
        }
        return items
    }
}

/// The RealityView itself. Its inputs change only when the stage loads or moves between
/// screens, so per-frame state changes elsewhere (speed, scrubbing) never rebuild it.
private struct VehicleStageCanvas: View {
    let stage: VehicleStage
    let host: VehicleStageHost
    let isVisible: Bool
    var fadesEdges: Bool = false

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
            let currentSurface = surface
            currentSurface.subscription?.cancel()
            currentSurface.anchor = anchor
            currentSurface.camera = camera
            host.surface = currentSurface
            stage.mount(for: host)
            currentSurface.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak currentSurface] event in
                let deltaTime = event.deltaTime
                // The stage publishes SwiftUI state, so every frame step runs on the main actor.
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        guard let currentSurface, host.surface === currentSurface, stage.hostID == ObjectIdentifier(host) else { return }
                        stage.tick(deltaTime)
                    }
                } else {
                    Task { @MainActor in
                        guard let currentSurface, host.surface === currentSurface, stage.hostID == ObjectIdentifier(host) else { return }
                        stage.tick(deltaTime)
                    }
                }
            }
        }
        .mask {
            if fadesEdges {
                VehicleStageEdgeFade()
            } else {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
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
