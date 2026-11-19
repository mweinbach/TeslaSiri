import CoreGraphics
import Foundation
import Observation
import OSLog
import RealityKit
import TeslaVehicleFleet
import TeslaVehicleKit
import UIKit
import simd

/// A live RealityKit stage for one vehicle. It loads the bundled TeslaVehicleKit build,
/// mirrors the car's real state (doors, windows, trunks, charge port, lights, motion), and
/// moves between the Tesla app's own camera poses for parked, charging and driving.
/// `tick` runs once per rendered frame from the hosting `RealityView`.
@MainActor
@Observable
final class VehicleStage {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Screen positions of the interactive callouts, in the hosting view's coordinates.
    private(set) var hotspots: [VehicleHotspotPlacement] = []
    /// The paint's highlight color, which the showroom uses for its ambient light.
    private(set) var paintHighlight: UIColor?

    @ObservationIgnored let root = Entity()
    /// The `VehicleStageHost` of the view currently showing this stage.
    private(set) var hostID: ObjectIdentifier?
    @ObservationIgnored var viewSize: CGSize = .zero
    @ObservationIgnored var reduceMotion = false
    /// Narrows the field of view to frame the car more tightly than the Tesla pose.
    @ObservationIgnored var framingZoom: Float = 1

    /// The hosting view's camera. RealityView only renders through a camera that is in
    /// its content from the start, so each view owns one and the stage drives it.
    @ObservationIgnored private var camera = PerspectiveCamera()
    @ObservationIgnored private let carPivot = Entity()
    /// Which of Tesla's looks the car wears: the parked studio shaders, or the recovered
    /// named-view lighting for the CHARGING or DRIVE camera.
    @ObservationIgnored private var lightingLook: LightingLook = .studio
    @ObservationIgnored private var scene: VehicleScene?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var frame: VehicleFrame?
    @ObservationIgnored private var road: VehicleRoadScene?
    @ObservationIgnored private var clips: [VehicleOpening: ClipPose] = [:]
    @ObservationIgnored private var wheels: [WheelRig] = []
    @ObservationIgnored private var anchors: [VehicleHotspot: SIMD3<Float>] = [:]
    @ObservationIgnored private var poses: [PoseKind: CameraPose] = [:]
    @ObservationIgnored private var controls: [String: [String]] = [:]
    @ObservationIgnored private var baselineLights: Set<String> = []
    @ObservationIgnored private var activeLights: Set<String>?

    @ObservationIgnored private let reflection = Entity()
    @ObservationIgnored private var reflectionPairs: [(source: Entity, mirror: Entity)] = []
    @ObservationIgnored private var reflectionNeedsSync = false
    @ObservationIgnored private let floorSortGroup = ModelSortGroup(depthPass: .prePass)
    @ObservationIgnored private let shadow = Entity()
    @ObservationIgnored private var bakedShadow: VehicleScene.GroundShadow?
    @ObservationIgnored private var roadOpacity: Float = 0
    @ObservationIgnored private var floorRoadOpacity: Float?
    @ObservationIgnored private var isDarkAppearance = true

    @ObservationIgnored private(set) var state = VehicleStageState()
    @ObservationIgnored private var time: Double = 0
    @ObservationIgnored private var speed: Float = 0
    @ObservationIgnored private var acceleration: Float = 0
    @ObservationIgnored private var curvature: Float = 0
    @ObservationIgnored private var bodyRoll: Float = 0
    @ObservationIgnored private var bodyPitch: Float = 0
    @ObservationIgnored private var blinkStart: Double = -10
    @ObservationIgnored private var blinkCount = 0
    @ObservationIgnored private var flashStart: Double = -10

    @ObservationIgnored private var cameraFit: CameraFit?
    @ObservationIgnored private var lastProjection: HotspotProjection?
    @ObservationIgnored private var cameraTransform = Transform()
    @ObservationIgnored private var cameraFOV: Float = 30
    @ObservationIgnored private var cameraPivot: SIMD3<Float> = [0, 0.7, 0]
    @ObservationIgnored private var transition: CameraTransition?
    @ObservationIgnored private var currentPoseKind: PoseKind = .parked

    private static let log = Logger(subsystem: "com.maxweinbach.TeslaSiri", category: "VehicleStage")
    private static var cache: [String: VehicleStage] = [:]
    private static var cacheOrder: [String] = []

    /// One stage per purpose and vehicle, kept across view rebuilds so the model loads once.
    static func shared(for spec: VehicleModelSpec) -> VehicleStage {
        shared("\(spec.modelID)|\(spec.bodyStyle)|\(spec.paintName ?? "")")
    }

    static func shared(_ key: String) -> VehicleStage {
        if let stage = cache[key] {
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            return stage
        }
        let stage = VehicleStage()
        cache[key] = stage
        cacheOrder.append(key)
        while cacheOrder.count > 3 {
            let evicted = cacheOrder.removeFirst()
            cache[evicted] = nil
        }
        return stage
    }

    init() {
        root.name = "VehicleStage"
        Self.configure(camera)
        reflection.isEnabled = false
        root.addChild(carPivot)
        root.addChild(reflection)
        root.addChild(shadow)
    }

    var isReady: Bool { phase == .ready }

    private static func configure(_ camera: PerspectiveCamera) {
        camera.name = "VehicleStageCamera"
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.near = 0.05
        camera.camera.far = 400
    }

    /// Makes `host` the view showing this stage, and moves the car into its RealityView
    /// if it has one yet.
    func attach(to host: VehicleStageHost) {
        if hostID != ObjectIdentifier(host) { root.removeFromParent() }
        hostID = ObjectIdentifier(host)
        transition = nil
        onFrame = nil
        driveOverride = nil
        mount(for: host)
    }

    /// Moves the car and camera into the host's current RealityView. The host calls this
    /// whenever SwiftUI builds it a new RealityView. Ignored unless `host` shows this stage.
    func mount(for host: VehicleStageHost) {
        guard hostID == ObjectIdentifier(host), let surface = host.surface,
              let anchor = surface.anchor, let camera = surface.camera else { return }
        if root.parent !== anchor { anchor.addChild(root) }
        Self.configure(camera)
        self.camera = camera
        camera.transform = cameraTransform
        camera.camera.fieldOfViewInDegrees = cameraFOV
        lastProjection = nil
    }

    func detach(from host: VehicleStageHost) {
        guard hostID == ObjectIdentifier(host) else { return }
        root.removeFromParent()
        hostID = nil
        onFrame = nil
        driveOverride = nil
    }

    /// Called once per rendered frame, before the stage moves, with the frame's duration.
    /// A drive replay uses it to advance its playhead in step with rendering.
    @ObservationIgnored var onFrame: ((Double) -> Void)?

    /// Frame-by-frame driving input that replaces the speed and road shape from `state`:
    /// a replay supplies the real road geometry around the car's position along the drive.
    struct DriveOverride {
        var speedMPH: Double
        /// Meters per second the car actually moves along the road this frame.
        var travelSpeed: Float
        var shape: RoadShape
        var isSelfDriving: Bool
    }

    @ObservationIgnored private var driveOverride: DriveOverride?

    func setDriveOverride(_ override: DriveOverride?) {
        driveOverride = override
    }

    // MARK: - Loading

    func load(_ spec: VehicleModelSpec) async {
        if let loadTask {
            await loadTask.value
            return
        }
        guard scene == nil else { return }

        // The stage outlives a tab. A host disappearing must not cancel another host's load.
        let task = Task { await self.loadModel(spec) }
        loadTask = task
        await task.value
    }

    private func loadModel(_ spec: VehicleModelSpec) async {
        defer { loadTask = nil }
        guard let library = VehicleLibraryProvider.shared else {
            phase = .failed("The vehicle library isn't bundled with this build.")
            return
        }
        Self.log.info("Loading \(spec.modelID, privacy: .public)/\(spec.bodyStyle, privacy: .public)")
        phase = .loading

        do {
            let loaded: VehicleScene
            do {
                loaded = try await library.load(spec.modelID, bodyStyle: spec.bodyStyle)
            } catch {
                guard !(error is CancellationError), spec.bodyStyle != "default" else { throw error }
                loaded = try await library.load(spec.modelID)
            }

            let presets = library.models[spec.modelID]?.paint_presets.keys.sorted() ?? []
            if let paint = VehicleModelSpec.matchPaint(spec.paintName, in: presets),
               paint != loaded.manifest.configuration.selections.paint {
                try? library.setPaint(paint, on: loaded)
            }

            install(loaded)
            phase = .ready
            Self.log.info("Loaded \(spec.modelID, privacy: .public)/\(spec.bodyStyle, privacy: .public)")
        } catch is CancellationError {
            phase = .idle
            Self.log.debug("Load of \(spec.modelID, privacy: .public) cancelled")
        } catch {
            Self.log.error("Load of \(spec.modelID, privacy: .public)/\(spec.bodyStyle, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            phase = .failed(String(describing: error))
        }
    }

    private func install(_ loaded: VehicleScene) {
        scene?.entity.removeFromParent()
        road?.root.removeFromParent()
        scene = loaded
        carPivot.transform = .identity
        carPivot.addChild(loaded.entity)

        for name in ["GroundPlane", "Ground_Shadow2", "Floor", "Floor_LongRange"] {
            loaded.body.findEntity(named: name)?.isEnabled = false
        }
        _ = Self.removeEmbeddedCameras(in: loaded.entity)

        let bodyBounds = loaded.body.visualBounds(relativeTo: loaded.entity)
        let frame = Self.measureFrame(of: loaded, bounds: bodyBounds)
        self.frame = frame
        wheels = Self.rigWheels(of: loaded, frame: frame)
        clips = Self.findClips(in: loaded)
        anchors = Self.findAnchors(in: loaded, clips: clips, frame: frame, bodyBounds: bodyBounds)
        lastProjection = nil
        controls = loaded.manifest.controls ?? [:]
        baselineLights = Set(controls.compactMap { name, paths in
            paths.contains { loaded.node(at: $0)?.isEnabled == true } ? name : nil
        })
        activeLights = nil
        poses = Self.cameraPoses(of: loaded, frame: frame, anchors: anchors)
        cameraFit = nil
        lightingLook = .studio

        road = nil
        speed = 0
        acceleration = 0
        curvature = 0
        bodyRoll = 0
        bodyPitch = 0
        roadOpacity = 0
        floorRoadOpacity = nil
        reflection.children.removeAll()
        reflectionPairs.removeAll()
        reflection.isEnabled = false

        let rgb = loaded.parkedHighlightRGB
        paintHighlight = UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
        bakedShadow = loaded.bakedGroundShadow()
        if isDarkAppearance { buildReflection(of: loaded, frame: frame) }
        buildFloorEffects(frame: frame)
        applyState(state, animated: false)
        updateFloorOpacity()
        snapCamera()
    }

    // MARK: - State

    func apply(_ newState: VehicleStageState) {
        applyState(newState, animated: true)
    }

    func setAppearance(dark: Bool) {
        guard dark != isDarkAppearance else { return }
        isDarkAppearance = dark
        road?.setAppearance(dark: dark)
        guard let scene, let frame else { return }
        if dark && reflection.children.isEmpty {
            buildReflection(of: scene, frame: frame)
        }
        buildFloorEffects(frame: frame)
        floorRoadOpacity = nil
        updateFloorOpacity()
    }

    private func applyState(_ newState: VehicleStageState, animated: Bool) {
        let previous = state
        state = newState

        if newState.mode == .driving, road == nil, let frame {
            let road = VehicleRoadScene(frame: frame, dark: isDarkAppearance)
            road.root.components.set(OpacityComponent(opacity: roadOpacity))
            road.root.isEnabled = roadOpacity > 0.01
            root.addChild(road.root)
            self.road = road
        }

        if scene != nil {
            var open = newState.openings
            if newState.isChargePortOpen { open.insert(.chargePort) }
            for (opening, clip) in clips {
                clip.target = open.contains(opening) ? 1 : 0
                if !animated || (reduceMotion && clip.progress != clip.target) {
                    clip.progress = clip.target
                    try? scene?.seek(clip.name, progress: clip.progress)
                    reflectionNeedsSync = true
                }
            }

            if animated, let wasLocked = previous.isLocked, let isLocked = newState.isLocked, wasLocked != isLocked {
                blinkStart = time
                blinkCount = isLocked ? 1 : 2
            }
        }

        let kind = poseKind(for: newState)
        if kind != currentPoseKind {
            currentPoseKind = kind
            if animated && !reduceMotion && scene != nil {
                transition = CameraTransition(
                    from: cameraTransform,
                    fromFOV: cameraFOV,
                    fromPivot: cameraPivot,
                    start: time,
                    duration: 1.4
                )
            } else {
                snapCamera()
            }
        }

        applyLighting(for: newState.mode)
    }

    /// Briefly flashes the headlights, mirroring a Flash Lights command.
    func flashLights() {
        flashStart = time
    }

    /// The studio shaders are tuned for Tesla's front three-quarter HOME camera; seen from the
    /// rear they fall into the dark side of the studio. While charging or driving, the car
    /// switches to Tesla's own recovered lighting for its CHARGING or DRIVE camera, which
    /// lights the rear of the car.
    private func applyLighting(for mode: VehicleStageState.Mode) {
        guard let scene else { return }
        let wanted: LightingLook = switch mode {
        case .parked: .studio
        case .charging: .charging
        case .driving: .driving
        }
        guard wanted != lightingLook else { return }
        lightingLook = wanted
        switch wanted {
        case .charging:
            applyNamedLighting("CHARGING", for: wanted, on: scene)
        case .driving:
            applyNamedLighting("DRIVE", for: wanted, on: scene)
        case .studio:
            Task {
                guard self.scene === scene, lightingLook == .studio else { return }
                try? await scene.applyParkedAppearance()
            }
        }
    }

    /// The named views use the Classic finishes, which load after the car is on screen.
    /// Applied before they arrive, a named view shows washed-out portable materials, so
    /// the car keeps its current look until they have.
    private func applyNamedLighting(_ view: String, for look: LightingLook, on scene: VehicleScene) {
        if scene.classicFinishesLoaded {
            try? scene.setLighting(view: view)
            return
        }
        Task {
            await scene.classicFinishes()
            guard self.scene === scene, lightingLook == look else { return }
            try? scene.setLighting(view: view)
        }
    }

    private func poseKind(for state: VehicleStageState) -> PoseKind {
        switch state.mode {
        case .parked: .parked
        case .charging: poses[.charging] == nil ? .parked : .charging
        case .driving:
            state.isReversing && poses[.reverse] != nil ? .reverse : (poses[.drive] == nil ? .parked : .drive)
        }
    }

    // MARK: - Frame

    func tick(_ deltaTime: TimeInterval) {
        guard let scene, let frame else { return }
        let dt = Float(min(max(deltaTime, 0), 0.1))
        time += Double(dt)

        onFrame?(Double(dt))
        stepClips(dt, scene: scene)
        stepMotion(dt, frame: frame)
        stepLights()
        stepEffects()
        stepCamera(dt)
        updateHotspots()
    }

    private func stepClips(_ dt: Float, scene: VehicleScene) {
        for clip in clips.values where clip.progress != clip.target {
            let step = dt / max(clip.duration, 0.3)
            if clip.progress < clip.target {
                clip.progress = min(clip.target, clip.progress + step)
            } else {
                clip.progress = max(clip.target, clip.progress - step)
            }
            try? scene.seek(clip.name, progress: clip.progress)
            reflectionNeedsSync = true
        }
    }

    private func stepMotion(_ dt: Float, frame: VehicleFrame) {
        let driving = state.mode == .driving
        if !driving, roadOpacity == 0, speed == 0, acceleration == 0,
           curvature == 0, bodyRoll == 0, bodyPitch == 0 { return }
        let speedMPH = driveOverride?.speedMPH ?? state.speedMPH
        let targetSpeed = driving ? Float(speedMPH * 0.44704) * (state.isReversing ? -1 : 1) : 0
        let previousSpeed = speed
        let previousRoll = bodyRoll
        let previousPitch = bodyPitch
        let previousRoadOpacity = roadOpacity
        if let override = driveOverride, driving {
            // A replay moves the car exactly; follow it without lag. Lane dashes stop reading as
            // motion (and start to strobe) past about 40 m/s, so cap their pace at fast replay
            // speeds while the road shape keeps sweeping past at the true rate.
            let travel = max(-40, min(40, override.travelSpeed))
            speed += (travel - speed) * min(1, dt * 8)
        } else {
            speed += (targetSpeed - speed) * min(1, dt * 1.2)
        }
        let instantAcceleration = dt > 0 ? (speed - previousSpeed) / dt : 0
        acceleration += (instantAcceleration - acceleration) * min(1, dt * 3)
        let targetCurvature = driving ? Float(state.curvature) : 0
        curvature += (targetCurvature - curvature) * min(1, dt * 1.5)

        roadOpacity += ((driving ? 1 : 0) - roadOpacity) * min(1, dt * (reduceMotion ? 20 : 2.2))
        if !driving, roadOpacity < 0.0001, abs(speed) < 0.0001, abs(acceleration) < 0.0001,
           abs(curvature) < 0.00001, abs(bodyRoll) < 0.0001, abs(bodyPitch) < 0.0001 {
            speed = 0
            acceleration = 0
            curvature = 0
            roadOpacity = 0
            bodyRoll = 0
            bodyPitch = 0
        }
        if let road {
            if roadOpacity != previousRoadOpacity {
                road.root.components.set(OpacityComponent(opacity: roadOpacity))
                road.root.isEnabled = roadOpacity > 0.01
            }
            if road.root.isEnabled {
                // The planned-path ribbon is Tesla's Autopilot/FSD path, so it only shows when
                // the car was actually steering itself.
                let selfDriving = driveOverride?.isSelfDriving ?? state.isSelfDriving
                road.update(
                    deltaTime: dt,
                    speed: speed,
                    shape: driveOverride?.shape ?? .arc(curvature: curvature),
                    showsPath: driving && selfDriving && !state.isReversing && speedMPH > 1
                )
            }
        }

        // Steer toward where the road is heading a few meters ahead.
        var roadCurvature = curvature
        if let shape = driveOverride?.shape, driving {
            roadCurvature = shape.point(at: 6).z / 6
            curvature += (roadCurvature - curvature) * min(1, dt * 3)
        }
        let steer = max(-0.5, min(0.5, -atan(frame.wheelbase * curvature)))
        for wheel in wheels {
            if wheel.advance(distance: speed * dt, steer: wheel.isFront ? steer : 0) {
                reflectionNeedsSync = true
            }
        }

        let targetRoll = driving ? max(-0.03, min(0.03, -curvature * speed * speed * 0.0035)) : 0
        let targetPitch = driving ? max(-0.015, min(0.015, -acceleration * 0.004)) : 0
        bodyRoll += (targetRoll - bodyRoll) * min(1, dt * 2.5)
        bodyPitch += (targetPitch - bodyPitch) * min(1, dt * 2.5)
        if bodyRoll != previousRoll || bodyPitch != previousPitch {
            carPivot.orientation = simd_quatf(angle: bodyRoll, axis: frame.forward)
                * simd_quatf(angle: bodyPitch, axis: frame.right)
        }
    }

    private func stepLights() {
        guard let scene, !controls.isEmpty else { return }
        if state.mode != .driving, time - blinkStart >= Double(blinkCount) * 0.7,
           time - flashStart >= 1.2, activeLights == baselineLights { return }
        var desired = baselineLights
        if state.mode == .driving {
            desired.insert("daytimeLights")
            let braking = acceleration < -0.7 || (abs(speed) < 0.4 && !state.isReversing)
            if braking { desired.insert("brakeLights") }
            if state.isReversing { desired.insert("reverseLights") }
        }
        let blinkElapsed = time - blinkStart
        if blinkElapsed >= 0, blinkElapsed < Double(blinkCount) * 0.7 {
            if blinkElapsed.truncatingRemainder(dividingBy: 0.7) < 0.38 {
                desired.formUnion(["leftSignal", "rightSignal", "parkingLights"])
            }
        }
        let flashElapsed = time - flashStart
        if flashElapsed >= 0, flashElapsed < 1.2, flashElapsed.truncatingRemainder(dividingBy: 0.6) < 0.32 {
            desired.insert("headlights")
        }
        desired.formIntersection(controls.keys)
        guard desired != activeLights else { return }
        activeLights = desired
        reflectionNeedsSync = true
        let lit = Set(desired.flatMap { controls[$0] ?? [] })
        for path in Set(controls.values.flatMap { $0 }) {
            scene.node(at: path)?.isEnabled = lit.contains(path)
        }
    }

    private func stepEffects() {
        updateFloorOpacity()
        guard reflectionNeedsSync, reflection.isEnabled else { return }
        for pair in reflectionPairs {
            if pair.mirror.transform != pair.source.transform { pair.mirror.transform = pair.source.transform }
            if pair.mirror.isEnabled != pair.source.isEnabled { pair.mirror.isEnabled = pair.source.isEnabled }
        }
        reflectionNeedsSync = false
    }

    private func updateFloorOpacity() {
        guard floorRoadOpacity != roadOpacity else { return }
        floorRoadOpacity = roadOpacity
        let showroom = 1 - roadOpacity
        reflection.components.set(OpacityComponent(opacity: reflectionStrength * showroom))
        reflection.isEnabled = reflectionStrength > 0 && showroom > 0.05
    }

    private func stepCamera(_ dt: Float) {
        let aspect = viewSize.height > 1 ? Float(viewSize.width / viewSize.height) : 1.9
        if cameraFit?.kind != currentPoseKind || cameraFit?.aspect != aspect {
            guard let pose = poses[currentPoseKind] ?? poses[.parked] else { return }
            cameraFit = CameraFit(
                kind: currentPoseKind,
                aspect: aspect,
                transform: pose.resolvedTransform(aspect: aspect),
                fieldOfView: pose.fittedFOV(aspect: aspect),
                pivot: pose.pivot
            )
        }
        guard let cameraFit else { return }
        var transform = cameraFit.transform
        var fov = cameraFit.fieldOfView / framingZoom
        var pivot = cameraFit.pivot

        if let transition {
            let linear = Float(min(1, (time - transition.start) / transition.duration))
            let eased = linear * linear * (3 - 2 * linear)
            transform = Transform(
                scale: .one,
                rotation: simd_slerp(transition.from.rotation, transform.rotation, eased),
                translation: simd_mix(transition.from.translation, transform.translation, SIMD3(repeating: eased))
            )
            fov = transition.fromFOV + (fov - transition.fromFOV) * eased
            pivot = simd_mix(transition.fromPivot, pivot, SIMD3(repeating: eased))
            if linear >= 1 { self.transition = nil }
        }

        if transform != cameraTransform {
            camera.transform = transform
            cameraTransform = transform
        }
        if fov != cameraFOV {
            camera.camera.fieldOfViewInDegrees = fov
            cameraFOV = fov
        }
        cameraPivot = pivot
    }

    private func snapCamera() {
        transition = nil
        stepCamera(0)
    }

    // MARK: - Hotspots

    private func updateHotspots() {
        guard let scene, viewSize.width > 1, viewSize.height > 1 else { return }
        guard state.mode != .driving, transition == nil else {
            lastProjection = nil
            if !hotspots.isEmpty { hotspots = [] }
            return
        }
        let projection = HotspotProjection(
            camera: cameraTransform, fieldOfView: cameraFOV, size: viewSize,
            mode: state.mode, roll: bodyRoll, pitch: bodyPitch
        )
        guard lastProjection != projection else { return }
        lastProjection = projection

        let visible: [VehicleHotspot] = state.mode == .charging ? [.lock, .chargePort] : [.lock, .frunk, .trunk, .chargePort]
        let cameraMatrix = camera.transformMatrix(relativeTo: root)
        let view = cameraMatrix.inverse
        let modelMatrix = scene.entity.transformMatrix(relativeTo: root)
        func rootPosition(_ anchor: SIMD3<Float>) -> SIMD3<Float> {
            let point = modelMatrix * SIMD4(anchor, 1)
            return SIMD3(point.x, point.y, point.z)
        }
        let tanHalf = tan(cameraFOV * .pi / 360)
        let aspect = Float(viewSize.width / viewSize.height)
        var placements: [VehicleHotspotPlacement] = []
        for hotspot in visible {
            guard let anchor = anchors[hotspot] else { continue }
            let world = rootPosition(anchor)
            // Hide the charge-port callout when its side of the car faces away. The roof,
            // frunk and trunk lids face up, so their callouts always show.
            if hotspot == .chargePort, let frame {
                let center = rootPosition(frame.origin)
                let eyePosition = cameraMatrix.columns.3
                let cameraPosition = SIMD3(eyePosition.x, eyePosition.y, eyePosition.z)
                var outward = world - center
                var toCamera = cameraPosition - center
                outward.y = 0
                toCamera.y = 0
                outward = frame.right * simd_dot(outward, frame.right)
                if simd_length(outward) > 0.3, simd_length(toCamera) > 0.01,
                   simd_dot(simd_normalize(outward), simd_normalize(toCamera)) < -0.05 {
                    continue
                }
            }
            let eye = view * SIMD4(world, 1)
            guard eye.z < -0.2 else { continue }
            let ndcX = (eye.x / -eye.z) / (tanHalf * aspect)
            let ndcY = (eye.y / -eye.z) / tanHalf
            guard abs(ndcX) < 0.92, abs(ndcY) < 0.92 else { continue }
            let point = CGPoint(
                x: CGFloat((ndcX + 1) / 2) * viewSize.width,
                y: CGFloat((1 - ndcY) / 2) * viewSize.height
            )
            placements.append(VehicleHotspotPlacement(hotspot: hotspot, point: point))
        }

        let changed = placements.count != hotspots.count || zip(placements, hotspots).contains { new, old in
            new.hotspot != old.hotspot || abs(new.point.x - old.point.x) > 0.75 || abs(new.point.y - old.point.y) > 0.75
        }
        if changed { hotspots = placements }
    }

    // MARK: - Floor shadow & satin reflection

    /// Subtle PBR-shaded mirror of the car below `y = 0` (dark mode only), matching the
    /// Tesla app's dark satin showroom floor (`~14%` strength). Shares `floorSortGroup`
    /// (`order: 0`) with the baked contact shadow (`order: 1`) so the contact shadow always
    /// masks the reflection directly underneath the tires and sills from every orbit angle.
    private func buildReflection(of scene: VehicleScene, frame: VehicleFrame) {
        reflectionNeedsSync = true
        let mirror = scene.entity.clone(recursive: true)
        let paint = paintHighlight ?? UIColor(white: 0.45, alpha: 1)
        let wheelRoots = Self.activeMounts(of: scene).map { $0.socket + "/" + $0.child }
        Self.applyReflectionMaterials(
            to: mirror,
            path: "",
            sortGroup: floorSortGroup,
            paintPaths: Set(scene.manifest.paintSurfaces),
            wheelRoots: wheelRoots,
            paint: Self.reflectionPBR(color: paint, brightness: 0.52, roughness: 0.34, metallic: 0.45),
            wheel: Self.reflectionPBR(color: UIColor(white: 0.22, alpha: 1), brightness: 1, roughness: 0.5, metallic: 0.25),
            other: Self.reflectionPBR(color: UIColor(white: 0.05, alpha: 1), brightness: 1, roughness: 0.65, metallic: 0.1)
        )
        let groundY = frame.origin.y
        reflection.transform = Transform(
            scale: [1, -1, 1],
            rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
            translation: [0, 2 * groundY, 0]
        )
        reflection.addChild(mirror)

        // Fade smoothly from the tires down toward the rocker panels so only the lower body
        // and wheels reflect into the floor.
        let reach = max(frame.length, frame.width) * 0.75 + 1
        let fadeHeight = frame.height * 0.48
        var clipping = ClippingComponent(bounds: BoundingBox(
            min: [frame.origin.x - reach, groundY - 0.04, frame.origin.z - reach],
            max: [frame.origin.x + reach, groundY + fadeHeight, frame.origin.z + reach]
        ))
        var feather = ClippingComponent.FeatheredEdge(falloff: .linear)
        feather.positiveEdgeInset = [0, fadeHeight, 0]
        clipping.featheredEdge = feather
        clipping.shouldClipSelf = true
        clipping.shouldClipChildren = true
        reflection.components.set(clipping)

        var paths = Set<String>()
        for clip in clips.values {
            for track in scene.manifest.clips[clip.name]?.tracks ?? [] { paths.insert(track.target) }
        }
        for list in controls.values { paths.formUnion(list) }
        for mount in Self.activeMounts(of: scene) {
            paths.insert(mount.socket)
            paths.insert(mount.socket + "/" + mount.child)
        }
        reflectionPairs = paths.compactMap { path in
            guard let source = scene.node(at: path), let target = Self.descendant(of: mirror, path: path) else { return nil }
            return (source, target)
        }
    }

    private var reflectionStrength: Float { isDarkAppearance ? 0.15 : 0 }

    /// Ground contact shadow positioned just below the tires (`origin.y - 0.001`), sorted
    /// directly above `reflection` (`order: 1`) so it cleanly anchors the car from every angle.
    private func buildFloorEffects(frame: VehicleFrame) {
        let shadowAlpha: CGFloat = isDarkAppearance ? 0.92 : 0.56
        let groundY = frame.origin.y - 0.001
        if let baked = bakedShadow {
            shadow.components.set(ModelComponent(
                mesh: .generatePlane(width: baked.width, depth: baked.depth),
                materials: [UnlitMaterial.stageSprite(
                    baked.texture,
                    color: UIColor(white: 0, alpha: shadowAlpha)
                )]
            ))
            shadow.position = SIMD3(baked.center.x, groundY, baked.center.z)
            shadow.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        } else {
            shadow.components.set(ModelComponent(
                mesh: .generatePlane(width: frame.width * 1.28, depth: frame.length * 1.16),
                materials: [UnlitMaterial.stageSprite(
                    VehicleStageTextures.contactShadow,
                    color: UIColor(white: 0, alpha: shadowAlpha)
                )]
            ))
            shadow.position = SIMD3(frame.origin.x, groundY, frame.origin.z)
            shadow.orientation = frame.orientation(heading: 0)
        }
        shadow.components.set(ModelSortGroupComponent(group: floorSortGroup, order: 1))
    }
}

// MARK: - Supporting types

@MainActor
enum VehicleLibraryProvider {
    static let shared: VehicleLibrary? = try? VehicleLibrary(directory: TeslaVehicleFleet.directory)
}

enum VehicleHotspot: String, Hashable, Identifiable {
    case lock
    case frunk
    case trunk
    case chargePort

    var id: String { rawValue }
}

struct VehicleHotspotPlacement: Equatable, Identifiable {
    var hotspot: VehicleHotspot
    var point: CGPoint
    var id: VehicleHotspot { hotspot }
}

private enum LightingLook {
    case studio
    case charging
    case driving
}

private enum PoseKind: Hashable {
    case parked
    case charging
    case drive
    case reverse
}

private struct CameraPose {
    var transform: Transform
    /// Vertical field of view in degrees at the pose's design aspect.
    var verticalFOV: Float
    var designAspect: Float
    var pivot: SIMD3<Float>
    /// For showroom poses: orbit `pivot` from this direction at whatever distance frames
    /// a sphere of `radius` in the current view, instead of a fixed position.
    var fitDirection: SIMD3<Float>?
    var fitRadius: Float = 0
    /// Extra room around the car; side views need more because the car's length faces the camera.
    var fitMargin: Float = 1

    /// Keeps the designed horizontal coverage when the view is narrower than the design.
    func fittedFOV(aspect: Float) -> Float {
        guard fitDirection == nil else { return verticalFOV }
        let k = max(1, designAspect / max(aspect, 0.1))
        return min(120, atan(tan(verticalFOV * .pi / 360) * k) * 360 / .pi)
    }

    func resolvedTransform(aspect: Float) -> Transform {
        guard let fitDirection else { return transform }
        let tanVertical = tan(verticalFOV * .pi / 360)
        let tanHorizontal = tanVertical * max(aspect, 0.3)
        let distance = max(fitRadius * 0.67 * fitMargin / tanHorizontal, fitRadius * 0.44 / tanVertical)
        // Camera basis looking from the eye toward the pivot (cameras look down -Z).
        let back = simd_normalize(fitDirection)
        let side = simd_normalize(simd_cross([0, 1, 0], back))
        let up = simd_cross(back, side)
        let rotation = simd_quatf(simd_float3x3(side, up, back))
        return Transform(scale: .one, rotation: rotation, translation: pivot + back * distance)
    }
}

private struct CameraFit {
    let kind: PoseKind
    let aspect: Float
    let transform: Transform
    let fieldOfView: Float
    let pivot: SIMD3<Float>
}

private struct HotspotProjection: Equatable {
    let camera: Transform
    let fieldOfView: Float
    let size: CGSize
    let mode: VehicleStageState.Mode
    let roll: Float
    let pitch: Float
}

private struct CameraTransition {
    var from: Transform
    var fromFOV: Float
    var fromPivot: SIMD3<Float>
    var start: Double
    var duration: Double
}

@MainActor
private final class ClipPose {
    let name: String
    let duration: Float
    var progress: Float = 0
    var target: Float = 0

    init(name: String, duration: Float) {
        self.name = name
        self.duration = duration
    }
}

@MainActor
private final class WheelRig {
    let wheel: Entity
    let socket: Entity
    let restWheel: simd_quatf
    let restSocket: simd_quatf
    let spinAxis: SIMD3<Float>
    let steerAxis: SIMD3<Float>
    let radius: Float
    let isFront: Bool
    /// Left-side sockets reuse the right wheel under a negative scale, which reverses rotation.
    let spinSign: Float
    let steerSign: Float
    private var spin: Float = 0
    private var appliedSteer: Float = 0

    init(wheel: Entity, socket: Entity, frame: VehicleFrame, carRoot: Entity, isFront: Bool) {
        self.wheel = wheel
        self.socket = socket
        self.isFront = isFront
        restWheel = wheel.orientation
        restSocket = socket.orientation
        let parent = socket.parent ?? carRoot
        let rightInSocket = socket.convert(direction: frame.right, from: carRoot)
        spinAxis = simd_normalize(restWheel.inverse.act(rightInSocket))
        let upInParent = parent.convert(direction: frame.up, from: carRoot)
        steerAxis = simd_normalize(restSocket.inverse.act(upInParent))
        let bounds = wheel.visualBounds(relativeTo: socket)
        radius = max(0.25, max(bounds.extents.y, bounds.extents.z) / 2)
        spinSign = Self.handedness(of: socket, in: carRoot)
        steerSign = Self.handedness(of: parent, in: carRoot)
    }

    func advance(distance: Float, steer: Float) -> Bool {
        let nextSpin = (spin + distance / max(radius, 0.2)).truncatingRemainder(dividingBy: 2 * .pi)
        let changesSpin = nextSpin != spin
        let changesSteering = steer != appliedSteer
        if changesSpin {
            spin = nextSpin
            wheel.orientation = restWheel * simd_quatf(angle: -spin * spinSign, axis: spinAxis)
        }
        if changesSteering {
            appliedSteer = steer
            socket.orientation = restSocket * simd_quatf(angle: steer * steerSign, axis: steerAxis)
        }
        return changesSpin || changesSteering
    }

    private static func handedness(of entity: Entity, in root: Entity) -> Float {
        guard entity !== root else { return 1 }
        let m = entity.transformMatrix(relativeTo: root)
        let basis = simd_float3x3(
            SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        )
        return simd_determinant(basis) < 0 ? -1 : 1
    }
}

// MARK: - Scene analysis

extension VehicleStage {
    /// The exported USD carries Tesla's snapshot cameras. A RealityView renders through the
    /// first camera it finds, so strip them and leave the stage camera as the only one.
    fileprivate static func removeEmbeddedCameras(in entity: Entity) -> Int {
        var removed = 0
        if entity.components.has(PerspectiveCameraComponent.self) {
            entity.components.remove(PerspectiveCameraComponent.self)
            removed += 1
        }
        if entity.components.has(OrthographicCameraComponent.self) {
            entity.components.remove(OrthographicCameraComponent.self)
            removed += 1
        }
        for child in entity.children {
            removed += removeEmbeddedCameras(in: child)
        }
        return removed
    }

    private static func reflectionPBR(color: UIColor, brightness: CGFloat, roughness: Float, metallic: Float) -> PhysicallyBasedMaterial {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: r * brightness, green: g * brightness, blue: b * brightness, alpha: 1))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.faceCulling = .front
        return material
    }

    /// Replaces mirrored car materials with satin PBR reflection materials (front-face culled
    /// for the inverted Y winding) inside a pre-pass sort group so internal geometry never shows through.
    fileprivate static func applyReflectionMaterials(
        to entity: Entity,
        path: String,
        sortGroup: ModelSortGroup,
        paintPaths: Set<String>,
        wheelRoots: [String],
        paint: PhysicallyBasedMaterial,
        wheel: PhysicallyBasedMaterial,
        other: PhysicallyBasedMaterial
    ) {
        if var model = entity.components[ModelComponent.self] {
            let material: PhysicallyBasedMaterial
            if paintPaths.contains(path) {
                material = paint
            } else if wheelRoots.contains(where: { path.hasPrefix($0) }) {
                material = wheel
            } else {
                material = other
            }
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
            entity.components.set(ModelSortGroupComponent(group: sortGroup, order: 0))
        }
        for child in entity.children {
            let childPath = path.isEmpty ? child.name : path + "/" + child.name
            applyReflectionMaterials(
                to: child,
                path: childPath,
                sortGroup: sortGroup,
                paintPaths: paintPaths,
                wheelRoots: wheelRoots,
                paint: paint,
                wheel: wheel,
                other: other
            )
        }
    }

    fileprivate static func descendant(of root: Entity, path: String) -> Entity? {
        var node: Entity? = root
        for name in path.split(separator: "/") {
            node = node?.children.first { $0.name == name }
        }
        return node
    }

    fileprivate static func measureFrame(of scene: VehicleScene, bounds: BoundingBox) -> VehicleFrame {
        let mounts = activeMounts(of: scene)
        var front: [SIMD3<Float>] = []
        var rear: [SIMD3<Float>] = []
        for mount in mounts {
            guard let socket = scene.node(at: mount.socket) else { continue }
            let position = socket.position(relativeTo: scene.entity)
            if isFront(mount.socket) { front.append(position) } else { rear.append(position) }
        }
        let frontCenter = front.isEmpty ? SIMD3<Float>(0, 0, 1.4) : front.reduce(.zero, +) / Float(front.count)
        let rearCenter = rear.isEmpty ? SIMD3<Float>(0, 0, -1.4) : rear.reduce(.zero, +) / Float(rear.count)
        var forward = frontCenter - rearCenter
        forward.y = 0
        if simd_length(forward) < 0.5 { forward = [0, 0, 1] }
        let wheelbase = simd_length(forward)
        forward = simd_normalize(forward)
        var origin = (frontCenter + rearCenter) / 2
        // Tesla models rest directly on world y = 0; pin to 0 when visualBounds dips slightly
        // from wheel-well or underbody geometry so the contact shadow never detaches from the tires.
        origin.y = (bounds.min.y.isFinite && abs(bounds.min.y) > 0.15) ? bounds.min.y : 0

        // Light-beam cards and floor helpers inflate the visual bounds, so clamp the body
        // size to proportions of the wheelbase (every Tesla is 1.55–1.75 wheelbases long).
        let extents = bounds.extents
        let lengthAxis = abs(forward.x) > abs(forward.z) ? extents.x : extents.z
        let widthAxis = abs(forward.x) > abs(forward.z) ? extents.z : extents.x
        let length = lengthAxis.isFinite ? min(max(lengthAxis, wheelbase * 1.5), wheelbase * 1.75) : wheelbase * 1.66
        let width = widthAxis.isFinite ? min(max(widthAxis, wheelbase * 0.62), wheelbase * 0.74) : wheelbase * 0.7
        let height = extents.y.isFinite ? min(max(extents.y, wheelbase * 0.48), wheelbase * 0.72) : wheelbase * 0.55
        return VehicleFrame(
            origin: origin,
            forward: forward,
            length: length,
            width: width,
            height: height,
            wheelbase: wheelbase
        )
    }

    fileprivate static func activeMounts(of scene: VehicleScene) -> [VehicleManifest.Mount] {
        let wheelScene = scene.manifest.configuration.wheel_scene
        let matching = scene.manifest.wheelMounts.filter { $0.source == wheelScene }
        return matching.isEmpty ? scene.manifest.wheelMounts : matching
    }

    fileprivate static func isFront(_ socketPath: String) -> Bool {
        let name = socketPath.split(separator: "/").last.map(String.init) ?? socketPath
        return ["LF", "RF", "FL", "FR"].contains { name.contains($0) }
    }

    fileprivate static func rigWheels(of scene: VehicleScene, frame: VehicleFrame) -> [WheelRig] {
        var seen: Set<String> = []
        return activeMounts(of: scene).compactMap { mount in
            guard !seen.contains(mount.socket),
                  let socket = scene.node(at: mount.socket),
                  let wheel = socket.children.first(where: { $0.name == mount.child }) ?? socket.children.first
            else { return nil }
            seen.insert(mount.socket)
            return WheelRig(wheel: wheel, socket: socket, frame: frame, carRoot: scene.entity, isFront: isFront(mount.socket))
        }
    }

    fileprivate static func findClips(in scene: VehicleScene) -> [VehicleOpening: ClipPose] {
        var result: [VehicleOpening: ClipPose] = [:]
        let clips = scene.manifest.clips
        let names = clips.keys.sorted()
        for opening in VehicleOpening.allCases {
            for prefix in opening.clipPrefixes {
                guard let name = names.first(where: { $0.split(separator: "/").first.map(String.init) == prefix }),
                      let clip = clips[name],
                      clip.tracks.allSatisfy({ scene.node(at: $0.target) != nil })
                else { continue }
                result[opening] = ClipPose(name: name, duration: clip.duration)
                break
            }
        }
        return result
    }

    fileprivate static func findAnchors(
        in scene: VehicleScene,
        clips: [VehicleOpening: ClipPose],
        frame: VehicleFrame,
        bodyBounds: BoundingBox
    ) -> [VehicleHotspot: SIMD3<Float>] {
        func bounds(for opening: VehicleOpening) -> BoundingBox? {
            guard let clip = clips[opening],
                  let target = scene.manifest.clips[clip.name]?.tracks.first?.target,
                  let node = scene.node(at: target)
            else { return nil }
            let box = node.visualBounds(relativeTo: scene.entity)
            return box.isEmpty || !box.extents.x.isFinite ? nil : box
        }

        let halfLength = frame.length / 2
        var anchors: [VehicleHotspot: SIMD3<Float>] = [:]
        let frunkFallback = frame.origin + frame.forward * (halfLength * 0.72) + frame.up * (frame.height * 0.62)
        let trunkFallback = frame.origin - frame.forward * (halfLength * 0.8) + frame.up * (frame.height * 0.78)
        if let box = bounds(for: .frunk), simd_length(box.extents) < frame.length {
            anchors[.frunk] = SIMD3(box.center.x, box.max.y, box.center.z)
        } else {
            anchors[.frunk] = frunkFallback
        }
        if let box = bounds(for: .trunk), simd_length(box.extents) < frame.length {
            anchors[.trunk] = SIMD3(box.center.x, box.max.y, box.center.z)
        } else {
            anchors[.trunk] = trunkFallback
        }
        if let box = bounds(for: .chargePort), simd_length(box.extents) < 1.2 {
            anchors[.chargePort] = box.center
        } else if let node = clips[.chargePort].flatMap({ scene.manifest.clips[$0.name]?.tracks.first?.target }).flatMap({ scene.node(at: $0) }) {
            anchors[.chargePort] = node.position(relativeTo: scene.entity)
        }
        let roofHeight = bodyBounds.max.y.isFinite ? min(bodyBounds.max.y, frame.origin.y + frame.height) : frame.origin.y + frame.height
        anchors[.lock] = SIMD3(frame.origin.x, roofHeight, frame.origin.z) - frame.forward * (frame.length * 0.06)
        return anchors
    }

    fileprivate static func cameraPoses(
        of scene: VehicleScene,
        frame: VehicleFrame,
        anchors: [VehicleHotspot: SIMD3<Float>]
    ) -> [PoseKind: CameraPose] {
        let showroomPivot = frame.origin + frame.up * (frame.height * 0.42)
        let radius = 0.5 * sqrt(frame.length * frame.length + frame.width * frame.width + frame.height * frame.height)
        func showroom(_ direction: SIMD3<Float>, margin: Float = 1, pivot: SIMD3<Float>? = nil) -> CameraPose {
            CameraPose(
                transform: Transform(),
                verticalFOV: 22,
                designAspect: 1.9,
                pivot: pivot ?? showroomPivot,
                fitDirection: simd_normalize(direction),
                fitRadius: radius,
                fitMargin: margin
            )
        }

        // Parked: match Tesla's own low eye-level HomeParked showroom angle (~9.5° front
        // three-quarter, telephoto 22° FOV) so the car fills the stage dramatically with a
        // crisp horizontal ground shadow and subtle floor reflection.
        let home = scene.parkedCamera().position(relativeTo: nil) - showroomPivot
        var homeFlat = SIMD3<Float>(home.x, 0, home.z)
        if simd_length(homeFlat) < 0.1 { homeFlat = frame.forward - frame.right }
        var poses: [PoseKind: CameraPose] = [
            .parked: showroom(simd_normalize(simd_normalize(homeFlat) + frame.forward * 0.14) + frame.up * 0.17)
        ]

        // Charging: rear three-quarter from the charge-port side at ~14° elevation so the
        // rear quarter and port fill the frame cleanly.
        var portSide = -frame.right
        var chargingPivot = showroomPivot
        if let port = anchors[.chargePort] {
            let lateral = simd_dot(port - frame.origin, frame.right)
            portSide = lateral >= 0 ? frame.right : -frame.right
            var towardPort = port - showroomPivot
            towardPort.y = 0
            chargingPivot = showroomPivot + towardPort * 0.30
        }
        poses[.charging] = showroom(
            portSide * 0.78 - frame.forward * 0.76 + frame.up * 0.25,
            margin: 0.88,
            pivot: chargingPivot
        )
        poses[.drive] = chasePose(frame: frame, behind: true)
        poses[.reverse] = chasePose(frame: frame, behind: false)
        return poses
    }

    /// The Full Self-Driving visualization's chase camera: elevated behind the car, looking
    /// down the road so the lane lines and planned path recede ahead of it. In reverse the
    /// camera swings to the front and looks back along the path.
    fileprivate static func chasePose(frame: VehicleFrame, behind: Bool) -> CameraPose {
        let direction: SIMD3<Float> = behind ? frame.forward : -frame.forward
        let eye = frame.origin - direction * (frame.length * 1.65) + frame.up * (frame.height * 1.95)
        let target = frame.origin + direction * (frame.length * 1.15)
        let camera = PerspectiveCamera()
        camera.look(at: target, from: eye, relativeTo: nil)
        return CameraPose(
            transform: Transform(scale: .one, rotation: camera.orientation, translation: camera.position),
            verticalFOV: 34,
            designAspect: 1.9,
            pivot: frame.center
        )
    }
}
