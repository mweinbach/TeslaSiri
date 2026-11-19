import Foundation
import RealityKit
import ImageIO
import simd

public struct VehicleManifest: Decodable {
    public struct Mount: Decodable { public let socket, child, source: String }
    public struct Configuration: Decodable {
        public struct Selections: Decodable {
            public let paint, wheel, caps, fascia, brakes, plate, rearlight: String?
        }
        public let wheel_scene: String
        public let selections: Selections
    }
    public struct Rig: Decodable {
        public struct Parked: Decodable {
            public struct Ground: Decodable {
                let path: String?
                let mask: String; let width, height: Int; let uvFromXZ: [[Float]]
                let bounds: [Float]
            }
            let ground: Ground?
            struct Shader: Decodable {
                let file: String; let bindings: [String:[String]]
                let wheelMaterials: [String]?
                let twoSided, paintGraphs: [String]?
                /// Every studio graph the parked look binds, on the body and the wheels.
                var graphNames: Set<String> { Set(bindings.keys).union(wheelMaterials ?? []) }
                var twoSidedNames: Set<String> { Set(twoSided ?? wheelMaterials ?? []) }
            }
            let shader: Shader?
            let panorama, highlight: String
            let highlights: [String:String]?
            let floorNormals: String; let normalSize: Int
            let sourceSkyRotation: [Float]?
            let skyEnergy, ambientEnergy: Float
        }
        public let parked: Parked?
        public struct Lighting: Decodable {
            public let rotation: [Float]
            public let skyEnergy, ambientEnergy: Float
            func orientation() throws -> simd_quatf {
                guard rotation.count == 3 else { throw VehicleError.invalid("Invalid sky rotation") }
                return eulerYXZ(SIMD3(rotation[0], rotation[1], rotation[2]))
            }
        }
        public struct Camera: Decodable {
            public let columns: [Float]
            public let verticalFOV, near, far: Float
            public let horizontal: Bool?
            public let width,height:Float?
        }
        public let panorama, defaultView, backgroundLight, backgroundDark: String
        public let presets: [String: Lighting]
        public let cameras: [String: Camera]
    }
    public struct Clip: Decodable {
        public struct Track: Decodable {
            public let target, channel: String
            public let times, transitions, restEuler: [Float]
            public let values: [[Float]]
            public let interpolation: Int
        }
        public let duration: Float
        public let tracks: [Track]
    }
    public let schemaVersion: Int
    public let model, source, file: String
    public let liveFile:String?
    public let hidden, paintSurfaces: [String]
    public let controls: [String:[String]]?
    public let roofFadeSurfaces: [String]?
    public let wheelMounts: [Mount]
    public let configuration: Configuration
    public let clips: [String: Clip]
    public let rig: Rig

    #if compiler(>=6.2)
    @concurrent
    #endif
    fileprivate static func load(from directory: URL) async throws -> sending VehicleManifest {
        try Task.checkCancellation()
        let data = try Data(contentsOf: directory.appendingPathComponent("vehicle.json"))
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.schemaVersion == 1 else { throw VehicleError.invalid("Unknown vehicle manifest version") }
        try Task.checkCancellation()
        return manifest
    }
}

public enum VehicleError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case let .invalid(reason): return reason }
    }
}

/// One exported configuration. `entity` can be attached to a RealityView or AR anchor.
@MainActor public final class VehicleScene {
    public let entity: Entity
    public let manifest: VehicleManifest
    public let directory: URL
    public let body: Entity
    public private(set) var environment: EnvironmentResource?
    public private(set) var parkedEnvironment: EnvironmentResource?
    private let studio = Entity()
    private var indexed: [String: Entity] = [:]
    private var restRotation:[String:Transform]=[:]
    private var parkedOriginals: [String: [any Material]] = [:]
    var originalParkedMaterials:[any Material] { parkedOriginals.values.flatMap { $0 } }
    private var parkedMaterialCache: [String: ShaderGraphMaterial] = [:]
    let classicTires: ClassicTires?
    private let classicComponents: ClassicComponents?
    var hasClassicDisplayGlass: Bool { classicComponents?.hasDisplayGlass == true }
    private(set) var meshRevision: UInt64 = 0
    private var tireLighting: VehicleManifest.Rig.Lighting?
    private var tireFinishes: [String: ShaderGraphMaterial] = [:]
    var replacementFinishes: [String:ShaderGraphMaterial] = [:]
    var wheelGeneration = 0
    private var lookGeneration = 0
    private var recolored: [String:ShaderGraphMaterial] = [:]
    private var customParkedWeights: (specular: TextureResource, diffuse: TextureResource)?
    private var originalPaint: [String:[any Material]] = [:]
    private var factoryPaintDraw=[String:Entity]()
    private var inParkedAppearance = false
    private var classicLoad: Task<Void, Never>?
    /// Whether the Classic finishes that the named views (CHARGING, DRIVE) use have loaded.
    public private(set) var classicFinishesLoaded = true
    private(set) var photo:Northlight?
    private(set) var photoActive=false
    var photographicPaint:NorthlightFinish?
    var photographicEnvironment:EnvironmentResource? {photo?.environment}
    var cameraSubject:CameraSubject? {photo?.subject}
    var photographicLamp:PhotographicLight? {photo?.lamp}
    private var keyAngle:VehicleKeyLight = .rake
    func moveKey(_ angle:VehicleKeyLight)throws{
        if photoActive,let photo,let site=photo.location{
            try photo.setEmitter(site,angle:angle);photo.rebindOptics()
            if let env=photo.environment,var light=studio.components[ImageBasedLightComponent.self]{
                light.source = .single(env);studio.components.set(light)
            }
        }
        keyAngle=angle
    }
    func attachGround(_ resource:TextureResource)throws {try photo?.attachGround(resource)}
    @_spi(Verification) public func inspectReflectedGround(_ on:Bool)throws {try photo?.inspectGround(on)}
    /// Number of refined mesh leaves bound to their original articulated parents.
    public var photographicPanelCount:Int {photoActive ? photo?.panels.count ?? 0 : 0}
    var hasCustomParkedPaint = false
    public internal(set) var parkedHighlightRGB: UInt32 = 0x878787

    public convenience init(directory: URL, lighting: Bool = true) async throws {
        let parent = directory.deletingLastPathComponent()
        let fleet = parent.lastPathComponent == "BodyStyles" ? parent.deletingLastPathComponent() : parent
        try await self.init(directory: directory, lighting: lighting, fleet: fleet)
    }

    init(directory: URL, lighting: Bool = true, fleet: URL) async throws {
        self.directory = directory
        manifest = try await VehicleManifest.load(from: directory)
        classicTires = try ClassicTires(fleet: fleet, panorama: manifest.rig.panorama)
        classicComponents = ClassicComponents(vehicle: directory, wheelRoots: Set(manifest.wheelMounts.map { $0.socket + "/" + $0.child }))
        // The studio graphs depend only on the manifest and take longer to import than the
        // car itself, so they start now and import alongside the USD, tires and panoramas.
        let studioShader = lighting && VehicleScene.studioShadersRender ? manifest.rig.parked?.shader : nil
        async let studioGraphs = VehicleScene.importParkedGraphs(
            studioShader?.graphNames ?? [],
            from: directory.appendingPathComponent(studioShader?.file ?? ""),
            twoSided: studioShader?.twoSidedNames ?? [])
        entity = try await Entity(contentsOf: directory.appendingPathComponent(manifest.liveFile ?? manifest.file))
        guard let body = entity.findEntity(named: "Body") else { throw VehicleError.invalid("USDZ has no Body hierarchy") }
        self.body = body
        if let hex = manifest.rig.parked?.highlight, let value = UInt32(hex.dropFirst(),radix:16) {
            parkedHighlightRGB = value
        } else if let name = manifest.configuration.selections.paint {
            parkedHighlightRGB = namedHighlight(name) ?? parkedHighlightRGB
        }
        // Standalone USD tools consume the USD camera/light rig. RealityKit uses
        // the equivalent components below so no extra camera or light is active.
        entity.findEntity(named: "Cameras")?.removeFromParent()
        entity.findEntity(named: "Studio")?.removeFromParent()
        // Collect original material IDs while indexing, before HOME replaces the portable slots.
        let namedIDs = index(body, "Body", collectingMaterials: true)
        // The Classic finishes light the named views (CHARGING, DRIVE). A build with a parked
        // studio look opens in that look, so its Classic bank, about a hundred shader graphs,
        // loads after the scene is ready instead of holding it up. The simulator can't draw
        // the studio look and opens in a named view, so there the bank loads first.
        let opensParked = lighting && manifest.rig.parked != nil && VehicleScene.studioShadersRender
        async let namedMaterials: Void? = opensParked ? nil : classicComponents?.prepare(namedIDs)
        try await classicTires?.prepare(in: manifest.wheelMounts.compactMap { indexed[$0.socket + "/" + $0.child] })
        for clip in manifest.clips.values {for track in clip.tracks where track.channel=="quaternion" || track.channel.hasPrefix("rotation_degrees"){
            restRotation[track.target]=indexed[track.target]?.transform
        }}
        for path in Set((manifest.controls ?? [:]).values.flatMap{$0}) {
            if let node=indexed[path]{fixMirroredOverlay(node)}
        }
        for path in manifest.paintSurfaces { originalPaint[path] = indexed[path]?.components[ModelComponent.self]?.materials }
        for path in manifest.hidden { indexed[path]?.isEnabled = false }
        if manifest.model=="model_s_palladium" {
            // Keep group visibility faithful in the portable USD. In the
            // native scene, drawing both regional reflectors at the exact
            // same depth makes the inactive country's fascia flicker.
            for suffix in ["","_p3"] {
                if let local=indexed["Body/Lights_Rear_Fascia"+suffix],let global=indexed["Body/Lights_Rear_Fascia_Global"+suffix],
                   local.isEnabled && global.isEnabled {
                    (manifest.configuration.selections.rearlight=="Global" ? local:global).isEnabled=false
                }
            }
        }
        studio.name = "StudioIBL"
        entity.addChild(studio)
        if lighting {
            let url = directory.appendingPathComponent(manifest.rig.panorama)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw VehicleError.invalid("Unreadable environment panorama: \(url.lastPathComponent)")
            }
            let environment = try await EnvironmentResource(equirectangular: image)
            self.environment = environment
            if let settings = manifest.rig.parked {
                let parkedURL = directory.appendingPathComponent(settings.panorama)
                guard let source = CGImageSourceCreateWithURL(parkedURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw VehicleError.invalid("Unreadable parked panorama")
                }
                parkedEnvironment = try await EnvironmentResource(equirectangular: image)
            }
            studio.components.set(ImageBasedLightComponent(source: .single(parkedEnvironment ?? environment)))
            body.components.set(ImageBasedLightReceiverComponent(imageBasedLight: studio))
            if manifest.rig.parked != nil, Self.studioShadersRender {
                let graphs = try await studioGraphs
                for name in graphs.keys.sorted() {
                    if let graph = graphs[name] { _ = try await finishParkedMaterial(graph, named: name) }
                }
                try await applyParkedAppearance()
            }
        }
        try await namedMaterials
        if lighting, manifest.rig.parked == nil { try setLighting(view: manifest.rig.defaultView) }
        if lighting, manifest.rig.parked != nil, !Self.studioShadersRender { try await applyParkedAppearance() }
        if opensParked { loadClassicFinishes(namedIDs) }
    }

    /// Loads the Classic bank in the background. A named view applied before it arrives
    /// shows the washed-out portable materials and picks up its finishes afterwards, so
    /// callers that can wait should check `classicFinishesLoaded` first.
    private func loadClassicFinishes(_ identifiers: Set<String>) {
        guard let classicComponents else { return }
        classicFinishesLoaded = false
        classicLoad = Task { [weak self] in
            try? await classicComponents.prepare(identifiers)
            guard let self else { return }
            self.classicFinishesLoaded = true
            self.bindNamedTree(self.body, path: "Body", bodyPath: "Body")
        }
    }

    /// Returns once the Classic finishes for the named views have loaded.
    public func classicFinishes() async {
        await classicLoad?.value
    }

    /// The studio shader graphs bind more buffers than the simulator's Metal driver allows
    /// (it reports "only 31 buffers are supported"), so nothing they cover draws there.
    /// Simulator builds light the parked car with Tesla's PARKED named view instead, which
    /// uses the Classic finishes.
    static var studioShadersRender: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    public func node(at path: String) -> Entity? { indexed[path] }
    private func fixMirroredOverlay(_ e:Entity){
        // The truck's right-front turn indicator reuses the left lamp mesh
        // under a negative scale. Preserve the emitting face in native USD import.
        if simd_determinant(e.transformMatrix(relativeTo:entity))<0,var m=e.components[ModelComponent.self] {
            m.materials=m.materials.map{mat in
                guard var p=mat as? PhysicallyBasedMaterial else{return mat}
                p.faceCulling = .none;return p
            };e.components.set(m)
        }
        for c in e.children{fixMirroredOverlay(c)}
    }
    func factoryPaintName(at path:String)->String? { originalPaint[path]?.first?.name }
    func portableMaterialName(at path: String) -> String? {
        (parkedOriginals[path] ?? indexed[path]?.components[ModelComponent.self]?.materials)?.first?.name
    }
    func presentCustomPaint(_ m:ModelComponent,on node:Entity,path:String){
        if factoryPaintDraw[path]==nil,node.children.isEmpty,let parent=node.parent,
           let i=parent.children.firstIndex(where:{$0===node}){
            // Never assign the custom tint to the factory's native PBR draw.
            // Keep both its GPU identity and its original sibling order.
            let draw=node.clone(recursive:false);draw.components.set(m);factoryPaintDraw[path]=node
            parent.children[i]=draw;indexed[path]=draw
            meshRevision &+= 1
        }else{node.components.set(m)}
    }

    func namedHighlight(_ name: String) -> UInt32? {
        if let colors = manifest.rig.parked?.highlights {
            return colors[name].flatMap { UInt32($0.dropFirst(),radix:16) }
        }
        // Older exports omit the palette. These are the shipped terrain colors.
        return ["RedMulticoat":0xf13d3d,"SolidBlack":0x6d6d6d,"SilverMetallic":0xc1c1c1,
                "MidnightSilver":0x999ea9,"DeepBlue":0x1667ee,"PearlWhite":0xdadada,
                "MidnightCherryRed":0xeb4b69,"Quicksilver":0xd0d9f7,"UltraRed":0xf03042,
                "StealthGrey":0x929ba7,"GlacierBlue":0x42599c,"DiamondBlack":0x6d6d6d,
                "SilkroadSilver":0xc1c1c1,"MarineBlue":0x1f4b75][name]
    }

    static func highlight(for rgb: UInt32) -> UInt32 {
        let c = [16,8,0].map { Double((rgb >> $0)&255)/255 }
        let peak = c.max()!, v = min(0.7,peak*0.325*5), fade = max(0,(0.4-v)/0.4)*0.5
        // Scale saturation toward grey while retaining the source hue.
        return c.reduce(UInt32(0)) { result, channel in
            let normalized = peak == 0 ? 1 : channel/peak
            let value = (v+fade)*(normalized*(1-fade)+fade)
            return (result << 8) | UInt32((255*value).rounded(.toNearestOrEven))
        }
    }

    @discardableResult
    private func index(_ root: Entity, _ path: String, collectingMaterials: Bool = false) -> Set<String> {
        let components = collectingMaterials ? classicComponents : nil
        var identifiers: Set<String> = []
        func visit(_ node: Entity, at path: String, bodyPath: String?) {
            indexed[path] = node
            let bindingPath = components?.bodyPath(bodyPath)
            components?.collectIdentifiers(on: node, bodyPath: bindingPath, into: &identifiers)
            for child in node.children {
                let childPath = path + "/" + child.name
                visit(child, at: childPath, bodyPath: bindingPath == nil ? nil : childPath)
            }
        }
        visit(root, at: path, bodyPath: path)
        return identifiers
    }

    func replaceWheel(at path: String, socket: Entity, old: Entity, new: Entity) {
        if photoActive{photo?.forget(prefix:path)}
        indexed = indexed.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        parkedOriginals = parkedOriginals.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        meshRevision &+= 1
        new.name = old.name
        old.removeFromParent()
        socket.addChild(new)
        index(new, path)
        bindTires(in: new, path: path, finishes: tireFinishes, remember: true)
        bindNamedTree(new, path: path, bodyPath: nil)
        if inParkedAppearance { bindWheelFinish(new,path:path,remember:true) }
        if photoActive{photo?.bindTree(new,path:path,finish:photographicPaint)}
    }

    /// Convenience framing for a whole, life-size vehicle. This is intentionally
    /// separate from the untouched `PARKED` camera from the shipped reference scene.
    public func overviewCamera() throws -> PerspectiveCamera {
        let c = try camera(view: "SNAPSHOT_PARKED")
        let front = body.findEntity(named: "FrontMarker")?.position(relativeTo: entity)
        let rear = body.findEntity(named: "RearMarker")?.position(relativeTo: entity)
        let length = front.flatMap { f in rear.map { simd_distance(f, $0) } } ?? 7.5
        var center = ((front ?? .zero) + (rear ?? .zero)) * 0.5
        center.y += length * (manifest.model == "semi" ? 0.23 : 0.145)
        c.position = center + c.orientation.act([0, 0, length * 1.45])
        c.camera.fieldOfViewInDegrees = 38
        return c
    }

    /// Without a named pose, frame the parked landscape pane, not the editor overview.
    public func camera(view: String? = nil) throws -> PerspectiveCamera {
        guard let view else { return manifest.rig.parked != nil ? parkedCamera() : try camera(view: manifest.rig.defaultView) }
        guard let pose = manifest.rig.cameras[view], pose.columns.count == 16 else { throw VehicleError.invalid("Unknown camera: \(view)") }
        let c = pose.columns
        let camera = PerspectiveCamera()
        camera.name = view
        camera.transform = Transform(matrix: simd_float4x4(columns: (
            SIMD4(c[0],c[1],c[2],c[3]), SIMD4(c[4],c[5],c[6],c[7]),
            SIMD4(c[8],c[9],c[10],c[11]), SIMD4(c[12],c[13],c[14],c[15]))))
        camera.camera.fieldOfViewInDegrees = pose.verticalFOV
        camera.camera.fieldOfViewOrientation = pose.horizontal == true ? .horizontal : .vertical
        camera.camera.near = pose.near
        camera.camera.far = pose.far
        return camera
    }

    public func setLighting(view: String) throws {
        guard let preset = manifest.rig.presets[view] ?? (manifest.rig.cameras[view] != nil ? manifest.rig.presets[manifest.rig.defaultView] : nil) else { throw VehicleError.invalid("Unknown lighting preset: \(view)") }
        let rotation = try preset.orientation()
        let finishes = try classicTires?.materials(for: preset) ?? [:]
        lookGeneration += 1
        stopNorthlight()
        restoreSurfaceMaterials()
        inParkedAppearance = false
        tireLighting = preset
        tireFinishes = finishes
        classicComponents?.setLighting(preset)
        bindMountedTires(to: body, finishes: finishes, remember: true)
        bindNamedTree(body, path: "Body", bodyPath: "Body")
        if var light = studio.components[ImageBasedLightComponent.self] {
            if let environment { light.source = .single(environment) }
            // A single RealityKit IBL cannot independently scale Godot ambient and specular.
            light.intensityExponent = log2(max(0.0001, preset.skyEnergy * preset.ambientEnergy))
            light.inheritsRotation = true
            studio.components.set(light)
            studio.orientation = rotation
        }
    }

    public func setParkedLighting() {
        guard let env = parkedEnvironment ?? environment else { return }
        var ibl = ImageBasedLightComponent(source: .single(env), intensityExponent:parkedNativeExposure)
        ibl.inheritsRotation = false
        studio.components.set(ibl)
        studio.orientation = simd_quatf()
    }

    var parkedNativeExposure:Float {
        guard let settings=manifest.rig.parked,settings.shader != nil else{return 2}
        // Steel is lit by the low-luminance truck panorama through native PBR.
        // Do not apply the New_Studio trim exposure to that different light.
        return manifest.model=="cybertruck" ? log2(settings.skyEnergy*settings.ambientEnergy) : ParkedStudio.trimExposure
    }

    func changePhotographicPaint(_ finish:NorthlightFinish, classicPaint: ClassicComponents.Paint?, _ work:() throws -> Void) throws {
        if photoActive{photo?.remove(from:self,onlyPaint:true)}
        defer{if photoActive{photo?.bindPaint(to:self)}}
        try work()
        if photoActive{try photo?.pigment(finish)}
        photographicPaint=finish
        classicComponents?.setPaint(classicPaint)
        if classicComponents?.isActive == true {
            for path in manifest.paintSurfaces {
                if let node = indexed[path] { bindNamed(node, path: path, bodyPath: path) }
            }
        }
    }
    private func stopNorthlight(){
        if photoActive{photo?.remove(from:self);photo?.key.removeFromParent();photoActive=false}
    }
    func classicStillBody()->Entity {
        let clone = body.clone(recursive: true)
        if photoActive { photo?.unpackClassicClone(clone) }
        if !inParkedAppearance {
            // Restore the portable slots on the copy before HOME's own
            // shaders bind. The live camera keeps its named-view materials.
            for (path, originals) in parkedOriginals {
                guard let node = descendant(at: path, in: clone), var model = node.components[ModelComponent.self] else { continue }
                model.materials = originals
                node.components.set(model)
            }
        }
        return clone
    }
    func applyNorthlight(library:VehicleLibrary,location:VehicleLocation = .dayroom,profile:VehicleLightingProfile = .showroom) async throws {
        lookGeneration += 1;let token=lookGeneration
        try Task.checkCancellation()
        let dir=library.profileDirectory(profile)
        if photoActive,let rig=photo,rig.source?.directory==dir {
            if rig.location != location {rig.meter(location)}
            return
        }
        let source=try await library.illumination(at:dir)
        try Task.checkCancellation();guard token==lookGeneration else{throw CancellationError()}
        let rig:Northlight
        if let photo{rig=photo}else{rig=try await Northlight(car:self,library:library)}
        try Task.checkCancellation();guard token==lookGeneration else{throw CancellationError()}
        if photographicPaint==nil,let name=manifest.configuration.selections.paint,let src=library.models[manifest.model]?.paint_presets[name] {
            photographicPaint=try NorthlightFinish(name:name,source:src)
        }
        try rig.illuminate(location,source:source,finish:photographicPaint,angle:keyAngle)
        if photoActive{rig.rebindOptics()}else{
            restoreSurfaceMaterials();inParkedAppearance=false;photo=rig
            tireLighting = nil; tireFinishes = [:]
            classicComponents?.setLighting(nil)
            rig.bindTree(body,path:"Body",finish:photographicPaint);photoActive=true;entity.addChild(rig.key)
        }
        var light=ImageBasedLightComponent(source:.single(rig.environment ?? source.env),intensityExponent:0)
        light.inheritsRotation=false;studio.components.set(light);studio.orientation=simd_quatf()
    }
    var photoTarget:SIMD3<Float>{[0,manifest.model=="semi" ? 1.90 : (manifest.model=="cybertruck" ? 0.89:0.77),0]}
    func photoCamera()->PerspectiveCamera {
        let axles=manifest.wheelMounts.compactMap{indexed[$0.socket]?.position(relativeTo:entity).z}
        let span=(axles.max() ?? 1.45)-(axles.min() ?? -1.45)
        let d=max(9.3,span*3.32+0.75),eye:SIMD3<Float>=[-0.70*d,photoTarget.y+0.105*d,-0.714*d]
        let c=PerspectiveCamera();c.look(at:photoTarget,from:eye,relativeTo:nil)
        c.camera.fieldOfViewInDegrees=17.6;return c
    }

    /// Apply the authored, camera-dependent studio shaders to the interactive
    /// entity, including the HOME illumination of the mounted tires.
    public func applyParkedAppearance() async throws {
        guard Self.studioShadersRender else {
            try setLighting(view: manifest.rig.presets["PARKED"] != nil ? "PARKED" : manifest.rig.defaultView)
            return
        }
        lookGeneration += 1; let token = lookGeneration
        let shader = manifest.rig.parked?.shader
        if let shader { try await loadParkedMaterials(shader.graphNames, file: shader.file) }
        let preset = parkedTireLighting
        let finishes = try classicTires?.materials(for: preset) ?? [:]
        try Task.checkCancellation()
        guard token == lookGeneration else { throw CancellationError() }
        stopNorthlight()
        if !inParkedAppearance { restoreSurfaceMaterials() }
        classicComponents?.setLighting(nil)
        setParkedLighting()
        tireLighting = preset
        tireFinishes = finishes
        for (name, paths) in shader?.bindings ?? [:] {
            if !shouldBind(name) { continue }
            guard let material = recolored[name] ?? parkedMaterialCache[name] else { throw VehicleError.invalid("Studio material not loaded: \(name)") }
            for path in paths {
                guard let e = indexed[path], var m = e.components[ModelComponent.self] else { throw VehicleError.invalid("Missing studio surface: \(path)") }
                if parkedOriginals[path] == nil { parkedOriginals[path] = m.materials }
                m.materials = [material]
                e.components.set(m)
            }
        }
        bindMountedTires(to: body, finishes: finishes, remember: true)
        bindWheelFinish(body,path:"Body",remember:true)
        inParkedAppearance = true
    }

    // Cover variants can change both the order and the material of the rim.
    // Match the actual USD materials rather than a mounted mesh path.
    func applyParkedWheels(to root: Entity, remember: Bool) async throws {
        if let shader = manifest.rig.parked?.shader {
            try await loadParkedMaterials(Set(shader.wheelMaterials ?? []), file: shader.file)
        }
        let finishes = try classicTires?.materials(for: parkedTireLighting) ?? [:]
        bindMountedTires(to: root, finishes: finishes, remember: remember)
        bindWheelFinish(root,path:"Body",remember:remember)
    }

    private var parkedTireLighting: VehicleManifest.Rig.Lighting? {
        guard classicTires?.supportsParked == true, let parked = manifest.rig.parked,
              let rotation = parked.sourceSkyRotation else { return nil }
        return .init(rotation: rotation, skyEnergy: parked.skyEnergy, ambientEnergy: parked.ambientEnergy)
    }

    func prepareWheelMaterials(in wheel: Entity) async throws {
        try await classicTires?.prepare(in: [wheel])
        if let classicComponents {
            let needed = classicComponents.identifiers(inWheel: wheel)
            try await classicComponents.prepare(needed)
        }
        // A camera/look switch may have completed while the replacement loaded.
        tireFinishes = try classicTires?.materials(for: tireLighting) ?? [:]
    }

    private func descendant(at path: String, in root: Entity) -> Entity? {
        if root === body { return indexed[path] }
        return path.split(separator: "/").dropFirst().reduce(Optional(root)) { node, name in
            node?.children.first { $0.name == name }
        }
    }

    private func bindMountedTires(to root: Entity, finishes: [String: ShaderGraphMaterial], remember: Bool) {
        guard !finishes.isEmpty else { return }
        for mount in manifest.wheelMounts {
            let path = mount.socket + "/" + mount.child
            if let wheel = descendant(at: path, in: root) {
                bindTires(in: wheel, path: path, finishes: finishes, remember: remember)
            }
        }
    }

    private func bindNamedTree(_ node: Entity, path: String, bodyPath: String?) {
        guard let classicComponents, classicComponents.isActive else { return }
        let bodyPath = classicComponents.bodyPath(bodyPath)
        bindNamed(node, path: path, bodyPath: bodyPath)
        for child in node.children {
            let childPath = path + "/" + child.name
            bindNamedTree(child, path: childPath, bodyPath: bodyPath == nil ? nil : childPath)
        }
    }

    private func bindNamed(_ node: Entity, path: String, bodyPath: String?) {
        guard let classicComponents, var model = node.components[ModelComponent.self] else { return }
        let originals = model.materials
        let isCustomPaint = hasCustomParkedPaint && originalPaint[path] != nil
        lazy var reversedWinding = simd_determinant(node.transformMatrix(relativeTo: self.entity)) < 0
        var changed = false
        for (slot, material) in originals.enumerated() where material is PhysicallyBasedMaterial {
            if let finish = classicComponents.finish(for: material, path: bodyPath, slot: slot,
                                                     customPaintSurface: slot == 0 && isCustomPaint,
                                                     reversedWinding: reversedWinding) {
                model.materials[slot] = finish
                changed = true
            }
        }
        if changed {
            // A multi-material draw can contain both a tire and a rim. The
            // first substitution owns the pristine source list for this draw.
            if parkedOriginals[path] == nil { parkedOriginals[path] = originals }
            node.components.set(model)
        }
    }

    private func bindTires(in node: Entity, path: String, finishes: [String: ShaderGraphMaterial], remember: Bool) {
        guard !finishes.isEmpty else { return }
        if var model = node.components[ModelComponent.self] {
            let originals = model.materials
            var changed = false
            for (slot, material) in originals.enumerated() {
                if let pbr = material as? PhysicallyBasedMaterial, let name = pbr.name, let graph = finishes[name] {
                    model.materials[slot] = graph
                    changed = true
                }
            }
            if changed {
                if remember && parkedOriginals[path] == nil { parkedOriginals[path] = originals }
                node.components.set(model)
            }
        }
        for child in node.children {
            bindTires(in: child, path: path + "/" + child.name, finishes: finishes, remember: remember)
        }
    }

    private func bindWheelFinish(_ node: Entity,path: String,remember: Bool) {
        if var m = node.components[ModelComponent.self],
           let original = m.materials.first as? PhysicallyBasedMaterial,
           let name = original.name, let finish = replacementFinishes[name] ??
             ((manifest.rig.parked?.shader?.wheelMaterials ?? []).contains(name) ? parkedMaterialCache[name] : nil) {
            if remember && parkedOriginals[path] == nil { parkedOriginals[path] = m.materials }
            m.materials[0] = finish; node.components.set(m)
        }
        for child in node.children { bindWheelFinish(child,path:path+"/"+child.name,remember:remember) }
    }

    /// Selecting the original named factory finish is a round trip, not a
    /// conversion from the studio shader into a custom RGB material.
    func restoreNamedFactoryPaint(_ name: String) -> Bool {
        guard name == manifest.configuration.selections.paint, !originalPaint.isEmpty else { return false }
        recolored.removeAll()
        customParkedWeights = nil
        let names=manifest.rig.parked?.shader?.paintGraphs ?? ["Paint"]
        let coated=Dictionary(uniqueKeysWithValues:names.flatMap { n in (manifest.rig.parked?.shader?.bindings[n] ?? []).map { ($0,n) } })
        for (path, original) in originalPaint {
            guard let node = indexed[path], var model = node.components[ModelComponent.self] else { continue }
            if inParkedAppearance, let n=coated[path], let graph = parkedMaterialCache[n] {
                parkedOriginals[path] = original; model.materials = [graph]
            } else {
                parkedOriginals.removeValue(forKey:path); model.materials = original
            }
            if let leaf=factoryPaintDraw.removeValue(forKey:path),let parent=node.parent,
               let i=parent.children.firstIndex(where:{$0===node}) {
                if leaf.transform.matrix != node.transform.matrix{leaf.transform=node.transform}
                leaf.isEnabled=node.isEnabled;leaf.components.set(model);parent.children[i]=leaf;indexed[path]=leaf
                meshRevision &+= 1
            } else {node.components.set(model)}
        }
        hasCustomParkedPaint = false
        return true
    }

    func parkedMaterial(_ name: String, file: String) async throws -> ShaderGraphMaterial {
        if let m=recolored[name] { return m }
        if let cached = parkedMaterialCache[name] { return cached }
        let graphs = try await Self.importParkedGraphs([name], from: directory.appendingPathComponent(file),
                                                       twoSided: manifest.rig.parked?.shader?.twoSidedNames ?? [])
        guard let graph = graphs[name] else { throw VehicleError.invalid("Studio material not loaded: \(name)") }
        return try await finishParkedMaterial(graph, named: name)
    }

    /// Loads the studio graphs that aren't cached yet, all in one batch.
    private func loadParkedMaterials(_ names: Set<String>, file: String) async throws {
        let missing = names.filter { recolored[$0] == nil && parkedMaterialCache[$0] == nil }
        guard !missing.isEmpty else { return }
        let graphs = try await Self.importParkedGraphs(missing, from: directory.appendingPathComponent(file),
                                                       twoSided: manifest.rig.parked?.shader?.twoSidedNames ?? [])
        for name in missing.sorted() {
            if let graph = graphs[name] { _ = try await finishParkedMaterial(graph, named: name) }
        }
    }

    /// Imports studio shader graphs from one material file, up to eight at a time. Each
    /// graph is parsed and compiled separately, so importing them one after another was
    /// most of a vehicle's load time.
    nonisolated static func importParkedGraphs(_ names: Set<String>, from file: URL,
                                               twoSided: Set<String>) async throws -> [String: ShaderGraphMaterial] {
        guard !names.isEmpty else { return [:] }
        var jobs = names.sorted().makeIterator()
        var graphs: [String: ShaderGraphMaterial] = [:]
        try await withThrowingTaskGroup(of: (String, ShaderGraphMaterial).self) { group in
            func enqueue() {
                guard let name = jobs.next() else { return }
                group.addTask {
                    try Task.checkCancellation()
                    var graph = try await ShaderGraphMaterial(named: "/"+name, from: file)
                    if twoSided.contains(name) { graph.faceCulling = .none }
                    return (name, graph)
                }
            }
            for _ in 0..<8 { enqueue() }
            while let (name, graph) = try await group.next() {
                graphs[name] = graph
                enqueue()
            }
        }
        return graphs
    }

    /// Gives an imported paint graph its weight textures and caches the result.
    private func finishParkedMaterial(_ graph: ShaderGraphMaterial, named name: String) async throws -> ShaderGraphMaterial {
        var material = graph
        let isPaint = manifest.rig.parked?.shader?.paintGraphs?.contains(name) == true
        if isPaint, let file = manifest.rig.parked?.shader?.file {
            // Bind both defaults explicitly. On a persistent renderer an unset
            // texture parameter can otherwise keep the previous paint's GPU binding.
            let dir=directory.appendingPathComponent(file).deletingLastPathComponent()
            for key in ["SpecWeight","DiffuseWeight"] {
                let tex=try await TextureResource(contentsOf:dir.appendingPathComponent(name+key+".png"),options:.init(semantic:.color))
                try material.setParameter(name:key,value:.textureResource(tex))
            }
        }
        parkedMaterialCache[name] = material
        if isPaint, let weights = customParkedWeights {
            try material.setParameter(name: "SpecWeight", value: .textureResource(weights.specular))
            try material.setParameter(name: "DiffuseWeight", value: .textureResource(weights.diffuse))
            recolored[name] = material
        }
        return material
    }

    func shouldBind(_ name: String) -> Bool {
        !hasCustomParkedPaint || !(manifest.rig.parked?.shader?.paintGraphs ?? ["Paint"]).contains(name) || recolored[name] != nil
    }

    func updateStudioPaint(rgb: SIMD3<Float>,metallic: Float,roughness: Float) throws {
        guard let s=manifest.rig.parked?.shader, let names=s.paintGraphs,!names.isEmpty else { return }
        let (spec,diff)=try StudioPaint.weights(rgb:rgb,metallic:metallic,roughness:roughness)
        customParkedWeights = (spec, diff)
        var changes=[String:ShaderGraphMaterial]()
        for name in names {
            // A standalone scene may change paint before it first enters HOME
            // or loads the parked shader. Resolve that template when HOME opens.
            guard var m=parkedMaterialCache[name] else { continue }
            try m.setParameter(name:"SpecWeight",value:.textureResource(spec))
            try m.setParameter(name:"DiffuseWeight",value:.textureResource(diff))
            changes[name]=m
        }
        recolored=changes
        if inParkedAppearance {
            for (name,mat) in changes {
                for path in s.bindings[name] ?? [] {
                    if let e=indexed[path],var m=e.components[ModelComponent.self] {
                        parkedOriginals[path]=m.materials; m.materials=[mat]; e.components.set(m)
                    }
                }
            }
        }
    }

    func restoreSurfaceMaterials(onlyPaint: Bool = false) {
        guard !parkedOriginals.isEmpty else { return }
        func restore(_ path: String, _ materials: [any Material]) -> Bool {
            guard let node = indexed[path], var model = node.components[ModelComponent.self] else { return false }
            model.materials = materials
            node.components.set(model)
            return true
        }

        if onlyPaint {
            for path in manifest.paintSurfaces {
                if let materials = parkedOriginals[path], restore(path, materials) {
                    parkedOriginals.removeValue(forKey: path)
                }
            }
        } else {
            let originals = parkedOriginals
            parkedOriginals = [:]
            for (path, materials) in originals {
                if !restore(path, materials) { parkedOriginals[path] = materials }
            }
        }
    }

    /// World-space contact shadow baked from Tesla's per-model `FloorMask.r8`.
    public struct GroundShadow {
        public let texture: TextureResource
        public let center: SIMD3<Float>
        public let width: Float
        public let depth: Float
    }

    /// Builds a world-aligned opacity mask texture from the model's bundled `FloorMask.r8`
    /// contact shadow so live RealityKit stages use the exact tire and underbody silhouette.
    public func bakedGroundShadow() -> GroundShadow? {
        guard let ground = manifest.rig.parked?.ground,
              ground.width > 0, ground.height > 0,
              ground.bounds.count == 4,
              ground.uvFromXZ.count == 2,
              ground.uvFromXZ[0].count == 3,
              ground.uvFromXZ[1].count == 3,
              let raw = try? Data(contentsOf: directory.appendingPathComponent(ground.mask)),
              raw.count == ground.width * ground.height else {
            return nil
        }

        let minX = ground.bounds[0]
        let minZ = ground.bounds[1]
        let maxX = ground.bounds[2]
        let maxZ = ground.bounds[3]
        let width = maxX - minX
        let depth = maxZ - minZ
        guard width > 0.1, depth > 0.1 else { return nil }

        let uRow = ground.uvFromXZ[0]
        let vRow = ground.uvFromXZ[1]
        let srcW = ground.width
        let srcH = ground.height
        let outSize = 512
        var rgba = [UInt8](repeating: 0, count: outSize * outSize * 4)

        raw.withUnsafeBytes { bytes in
            guard let src = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            func sampleBilinear(u: Float, v: Float) -> Float {
                let fx = u * Float(srcW) - 0.5
                let fy = v * Float(srcH) - 0.5
                let x0 = Int(floor(fx))
                let y0 = Int(floor(fy))
                let tx = fx - Float(x0)
                let ty = fy - Float(y0)
                let cx0 = min(max(x0, 0), srcW - 1)
                let cx1 = min(max(x0 + 1, 0), srcW - 1)
                let cy0 = min(max(y0, 0), srcH - 1)
                let cy1 = min(max(y0 + 1, 0), srcH - 1)
                let p00 = Float(src[cy0 * srcW + cx0])
                let p10 = Float(src[cy0 * srcW + cx1])
                let p01 = Float(src[cy1 * srcW + cx0])
                let p11 = Float(src[cy1 * srcW + cx1])
                let top = p00 + (p10 - p00) * tx
                let bot = p01 + (p11 - p01) * tx
                return (top + (bot - top) * ty) / 255.0
            }

            for row in 0..<outSize {
                let z = minZ + (Float(row) + 0.5) / Float(outSize) * depth
                for col in 0..<outSize {
                    let x = minX + (Float(col) + 0.5) / Float(outSize) * width
                    let rawU = uRow[0] * x + uRow[1] * z + uRow[2]
                    let rawV = vRow[0] * x + vRow[1] * z + vRow[2]
                    let u = rawU - floor(rawU)
                    let v = rawV - floor(rawV)
                    let value = sampleBilinear(u: u, v: v)
                    // Gentle gamma tightens the penumbra slightly while keeping tire contact crisp.
                    let shaped = pow(min(max(value, 0), 1), 1.15)
                    let byte = UInt8((shaped * 255).rounded())
                    let idx = (row * outSize + col) * 4
                    rgba[idx] = byte
                    rgba[idx + 1] = byte
                    rgba[idx + 2] = byte
                    rgba[idx + 3] = 255
                }
            }
        }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: outSize,
                height: outSize,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: outSize * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ),
              let texture = try? TextureResource(image: image, options: .init(semantic: .raw)) else {
            return nil
        }
        return GroundShadow(
            texture: texture,
            center: SIMD3((minX + maxX) * 0.5, 0, (minZ + maxZ) * 0.5),
            width: width,
            depth: depth
        )
    }

    /// Hermes MOVE_CAMERA's tablet override, expressed in the life-size USD world.
    /// Recenter on the vehicle rather than reproducing the app sidebar's off-axis frustum.
    public func parkedCamera() -> PerspectiveCamera {
        let scale: Float
        switch manifest.model {
        case "cybertruck": scale = 0.875
        case "semi": scale = 0.627
        case "model_s", "model_s_palladium": scale = 0.945
        case "model_x", "model_x_palladium": scale = 0.93
        case "model_y", "bayberry", "bayberry_e41", "bayberry_e80": scale = 0.987
        default: scale = 1
        }
        let eye = eulerYXZ([85,-140,0]).act([-0.06,3.5,0]) / (0.42 * scale)
        let c = PerspectiveCamera()
        c.name = "HomeParked"
        c.look(at: [0, manifest.model == "semi" ? 1.5 : 0.65, 0], from: eye, relativeTo: nil)
        // FramedCamera scales the design FOV by the pane, not the entire screen.
        // Here the asset occupies a dedicated landscape canvas without the sidebar.
        c.camera.fieldOfViewInDegrees = 2 * atan(tan(Float.pi / 6) * 0.36) * 180 / .pi
        return c
    }

    /// Independent normalized pose, e.g. doors and tonneau can be posed simultaneously.
    public func seek(_ clipName: String, progress: Float) throws {
        guard progress.isFinite, let clip = manifest.clips[clipName] else { throw VehicleError.invalid("Unknown clip or invalid progress: \(clipName)") }
        let time = max(0, min(progress, 1)) * clip.duration
        var rotations = [String: SIMD3<Float>]()
        func rotate(_ node:Entity,_ path:String,_ q:simd_quatf){
            // Euler keys and the imported rest basis were rounded separately.
            // Keep the exact rest basis when the first key denotes that angle.
            if time==0,let rest=restRotation[path],
               min(simd_length(q.vector-rest.rotation.vector),simd_length(q.vector+rest.rotation.vector))<0.00002 {
                if node.position==rest.translation && node.scale==rest.scale{node.transform=rest}
                else{node.orientation=rest.rotation}
            }else{node.orientation=q}
        }
        for track in clip.tracks {
            guard let node = indexed[track.target] else { throw VehicleError.invalid("Missing animation entity: \(track.target)") }
            guard let v = sample(track, at: time) else { continue }
            let parts = track.channel.split(separator: ":")
            let axis = parts.count > 1 ? ["x": 0, "y": 1, "z": 2][String(parts[1])] : nil
            switch parts.first {
            case "translation":
                if let axis { node.position[axis] = v[0] } else { node.position = SIMD3(v[0], v[1], v[2]) }
            case "scale":
                if let axis { node.scale[axis] = v[0] } else { node.scale = SIMD3(v[0], v[1], v[2]) }
            case "quaternion":
                rotate(node,track.target,simd_normalize(simd_quatf(vector: SIMD4(v[0], v[1], v[2], v[3]))))
            case "rotation_degrees":
                if let axis {
                    var r = rotations[track.target] ?? SIMD3(track.restEuler[0], track.restEuler[1], track.restEuler[2])
                    r[axis] = v[0]
                    rotations[track.target] = r
                } else { rotations[track.target] = SIMD3(v[0],v[1],v[2]) }
            case "visible": node.isEnabled = v[0] != 0
            case "albedo_color": try setSensorColor(v,on:node)
            default: throw VehicleError.invalid("Unsupported track \(track.channel)")
            }
        }
        for (path, degrees) in rotations {if let e=indexed[path]{rotate(e,path,eulerYXZ(degrees))}}
        // The final scale key can follow the rest rotation and re-decompose
        // the imported matrix. Resolve the entire closed independent pose,
        // but never reset another part or overwrite a non-rest channel.
        if time==0 {
            for path in Set(clip.tracks.map(\.target)){
                guard let node=indexed[path],let rest=restRotation[path],
                      simd_distance(node.position,rest.translation)<0.000002,simd_distance(node.scale,rest.scale)<0.000002,
                      min(simd_distance(node.orientation.vector,rest.rotation.vector),simd_distance(node.orientation.vector,-rest.rotation.vector))<0.000002
                else{continue}
                node.transform=rest
            }
        }
    }
}

private func eulerYXZ(_ degrees: SIMD3<Float>) -> simd_quatf {
    let r = degrees * (.pi / 180)
    return simd_quatf(angle: r.y, axis: [0,1,0]) * simd_quatf(angle: r.x, axis: [1,0,0]) * simd_quatf(angle: r.z, axis: [0,0,1])
}

private func sample(_ track: VehicleManifest.Clip.Track, at time: Float) -> [Float]? {
    let t = track.times, v = track.values
    guard !t.isEmpty else { return nil }
    guard t.count > 1, time > t[0] else { return v[0] }
    guard let j = t.firstIndex(where: { $0 > time }) else { return v.last }
    let i = j - 1
    if track.interpolation == 0 { return v[i] }
    var f = (time - t[i]) / (t[j] - t[i])
    let e = i < track.transitions.count ? track.transitions[i] : 1
    if e == 0 { f = 0 }
    else if e > 0 && e < 1 { f = 1 - pow(1 - f, 1/e) }
    else if e > 1 { f = pow(f, e) }
    else if e < 0 { f = f < 0.5 ? pow(2*f, -e)*0.5 : 1 - pow(2*(1-f), -e)*0.5 }
    if track.channel == "quaternion" {
        func q(_ a: [Float]) -> simd_quatf { simd_quatf(vector: SIMD4(a[0],a[1],a[2],a[3])) }
        let q = simd_slerp(q(v[i]), q(v[j]), f).vector
        return [q.x,q.y,q.z,q.w]
    }
    return v[i].indices.map { k in
        let a = v[i][k], b = v[j][k]
        if track.interpolation == 2 {
            let pre = v[max(i-1,0)][k], post = v[min(j+1,v.count-1)][k]
            return 0.5 * (2*a + (b-pre)*f + (2*pre-5*a+4*b-post)*f*f + (3*(a-b)+post-pre)*f*f*f)
        }
        return a + (b-a)*f
    }
}
