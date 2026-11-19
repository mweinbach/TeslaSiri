import RealityKit
import UIKit
import simd

/// Ground-plane geometry of a loaded vehicle, in the vehicle entity's coordinates.
struct VehicleFrame {
    /// Center of the wheelbase at ground height.
    var origin: SIMD3<Float>
    var forward: SIMD3<Float>
    var up: SIMD3<Float> = [0, 1, 0]
    var length: Float
    var width: Float
    var height: Float
    var wheelbase: Float

    var right: SIMD3<Float> { simd_normalize(simd_cross(forward, up)) }
    /// Rotation about `up` that maps local +Z onto `forward`.
    var yaw: Float { atan2(forward.x, forward.z) }
    var center: SIMD3<Float> { origin + up * (height * 0.45) }

    func orientation(heading: Float) -> simd_quatf {
        simd_quatf(angle: yaw - heading, axis: up)
    }
}

/// The road ahead of and behind the car, in the car's frame: `x` meters forward, `y` meters
/// to the right, and `z` the road's heading relative to the car (radians, positive bends
/// right). Either a constant-curvature arc or samples taken from a real, map-matched road.
struct RoadShape: Equatable {
    var curvature: Float = 0
    var start: Float = 0
    var step: Float = 1
    var samples: [SIMD3<Float>] = []

    static let straight = RoadShape()

    static func arc(curvature: Float) -> RoadShape { RoadShape(curvature: curvature) }

    func point(at s: Float) -> SIMD3<Float> {
        guard samples.count >= 2 else {
            let heading = curvature * s
            if abs(curvature) < 1e-4 {
                return SIMD3(s, curvature * s * s / 2, heading)
            }
            return SIMD3(sin(heading) / curvature, (1 - cos(heading)) / curvature, heading)
        }
        let position = (s - start) / step
        if position <= 0 { return extend(samples[0], by: s - start) }
        let last = Float(samples.count - 1)
        if position >= last { return extend(samples[samples.count - 1], by: s - (start + last * step)) }
        let index = Int(position)
        let fraction = position - Float(index)
        let a = samples[index], b = samples[index + 1]
        return SIMD3(a.x + (b.x - a.x) * fraction, a.y + (b.y - a.y) * fraction, a.z + (b.z - a.z) * fraction)
    }

    /// Continues straight along the end heading beyond the sampled range.
    private func extend(_ sample: SIMD3<Float>, by distance: Float) -> SIMD3<Float> {
        SIMD3(sample.x + cos(sample.z) * distance, sample.y + sin(sample.z) * distance, sample.z)
    }
}

/// The road the car drives on while in Drive: a pool of asphalt that dissolves into the
/// page, lane lines that stream past at the car's real speed, and a planned-path ribbon in
/// the style of the Full Self-Driving visualization. Everything bends with the measured
/// curvature of the road.
@MainActor
final class VehicleRoadScene {
    let root = Entity()

    private typealias LanePair = (left: Entity, right: Entity)

    private let frame: VehicleFrame
    private let right: SIMD3<Float>
    private let pool = Entity()
    private let ribbon = Entity()
    private var dividers: [LanePair] = []
    private var edges: [LanePair] = []
    private var path: [Entity] = []
    private var lastShape: RoadShape?
    private var travelled: Float = 0
    private var time: Float = 0

    private static let laneWidth: Float = 3.6
    private static let dashLength: Float = 3
    private static let dashPeriod: Float = 12
    private static let edgeSegment: Float = 4
    private static let pathSegment: Float = 2
    private static let nearLimit: Float = -24
    private static let farLimit: Float = 140

    init(frame: VehicleFrame, dark: Bool) {
        self.frame = frame
        right = frame.right
        root.name = "VehicleRoad"

        pool.components.set(ModelComponent(mesh: .generatePlane(width: 30, depth: 190), materials: []))
        pool.position = frame.origin + frame.forward * 40 - frame.up * 0.006
        pool.orientation = frame.orientation(heading: 0)
        root.addChild(pool)

        let dashMesh = MeshResource.generatePlane(width: 0.11, depth: Self.dashLength)
        let dashCount = Int((Self.farLimit - Self.nearLimit) / Self.dashPeriod) + 2
        for _ in 0..<dashCount {
            dividers.append(makeLanePair(mesh: dashMesh))
        }

        let edgeMesh = MeshResource.generatePlane(width: 0.10, depth: Self.edgeSegment)
        let edgeCount = Int((Self.farLimit - Self.nearLimit) / Self.edgeSegment) + 1
        for index in 0..<edgeCount {
            let pair = makeLanePair(mesh: edgeMesh)
            let opacity = OpacityComponent(opacity: Self.distanceFade(at: Self.edgeDistance(index)))
            pair.left.components.set(opacity)
            pair.right.components.set(opacity)
            edges.append(pair)
        }

        root.addChild(ribbon)
        ribbon.isEnabled = false
        let pathMesh = MeshResource.generatePlane(width: 1.55, depth: Self.pathSegment)
        for _ in 0..<26 {
            let segment = ModelEntity(mesh: pathMesh, materials: [])
            ribbon.addChild(segment)
            path.append(segment)
        }

        setAppearance(dark: dark)
    }

    private func makeLanePair(mesh: MeshResource) -> LanePair {
        let left = ModelEntity(mesh: mesh, materials: [])
        let right = ModelEntity(mesh: mesh, materials: [])
        root.addChild(left)
        root.addChild(right)
        return (left, right)
    }

    func setAppearance(dark: Bool) {
        let road = dark ? UIColor(white: 0.10, alpha: 1) : UIColor(white: 0.85, alpha: 1)
        let line = dark ? UIColor(white: 1, alpha: 0.72) : UIColor(white: 1, alpha: 0.92)
        let edge = dark ? UIColor(white: 0.65, alpha: 0.45) : UIColor(white: 0.96, alpha: 0.85)
        let ribbon = UIColor(red: 0.16, green: 0.52, blue: 1.0, alpha: dark ? 0.82 : 0.68)

        pool.components[ModelComponent.self]?.materials = [UnlitMaterial.stageSprite(VehicleStageTextures.roadPool, color: road)]
        let dashMaterial = UnlitMaterial.stageSprite(VehicleStageTextures.dash, color: line)
        for pair in dividers {
            pair.left.components[ModelComponent.self]?.materials = [dashMaterial]
            pair.right.components[ModelComponent.self]?.materials = [dashMaterial]
        }
        let edgeMaterial = UnlitMaterial.stageSprite(nil, color: edge)
        for pair in edges {
            pair.left.components[ModelComponent.self]?.materials = [edgeMaterial]
            pair.right.components[ModelComponent.self]?.materials = [edgeMaterial]
        }
        let pathMaterial = UnlitMaterial.stageSprite(VehicleStageTextures.pathRibbon, color: ribbon)
        for segment in path { segment.components[ModelComponent.self]?.materials = [pathMaterial] }
    }

    /// Advances the road by one frame. `speed` is signed meters per second.
    func update(deltaTime: Float, speed: Float, shape: RoadShape, showsPath: Bool) {
        time += deltaTime
        let previousPhase = travelled
        travelled = (travelled + speed * deltaTime).truncatingRemainder(dividingBy: Self.dashPeriod)
        if travelled < 0 { travelled += Self.dashPeriod }

        let shapeChanged = lastShape != shape
        if shapeChanged || travelled != previousPhase {
            for (index, pair) in dividers.enumerated() {
                let s = Self.nearLimit + Float(index) * Self.dashPeriod - travelled
                place(pair, at: shape.point(at: s), lateral: 0.5 * Self.laneWidth, lift: -0.004)
                let opacity = OpacityComponent(opacity: Self.distanceFade(at: s))
                pair.left.components.set(opacity)
                pair.right.components.set(opacity)
            }
        }

        if shapeChanged {
            for (index, pair) in edges.enumerated() {
                place(pair, at: shape.point(at: Self.edgeDistance(index)), lateral: 1.5 * Self.laneWidth, lift: -0.0045)
            }
            lastShape = shape
        }

        let ribbonNeedsPlacement = shapeChanged || !ribbon.isEnabled
        if ribbon.isEnabled != showsPath { ribbon.isEnabled = showsPath }
        guard showsPath else { return }
        let pathStart = frame.length * 0.5 + 0.6
        for (index, segment) in path.enumerated() {
            let s = pathStart + (Float(index) + 0.5) * Self.pathSegment
            if ribbonNeedsPlacement {
                let point = shape.point(at: s)
                segment.transform = Transform(
                    rotation: frame.orientation(heading: point.z),
                    translation: center(of: point, lift: -0.0035)
                )
            }
            let shimmer = 0.78 + 0.22 * sin(s * 0.32 - time * 3.2)
            let fade = min(1, (s - pathStart) / 4) * max(0, 1 - s / 56)
            segment.components.set(OpacityComponent(opacity: fade * shimmer))
        }
    }

    private static func edgeDistance(_ index: Int) -> Float {
        nearLimit + (Float(index) + 0.5) * edgeSegment
    }

    private static func distanceFade(at s: Float) -> Float {
        s < 0 ? max(0, 1 + s / 22) : max(0, min(1, 1 - (s - 50) / 85))
    }

    private func center(of point: SIMD3<Float>, lift: Float) -> SIMD3<Float> {
        frame.origin + frame.forward * point.x + right * point.y + frame.up * lift
    }

    private func place(_ pair: LanePair, at point: SIMD3<Float>, lateral: Float, lift: Float) {
        let center = center(of: point, lift: lift)
        let offset = (right * cos(point.z) - frame.forward * sin(point.z)) * lateral
        let orientation = frame.orientation(heading: point.z)
        pair.left.transform = Transform(rotation: orientation, translation: center - offset)
        pair.right.transform = Transform(rotation: orientation, translation: center + offset)
    }
}
