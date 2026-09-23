import Foundation
import Metal
import SceneImport
import SceneItemFormat
import SceneShaderTranslation
import simd

/// Draws a Wallpaper Engine scene item with Metal. Every frame is computed from the scene time; nothing is
/// baked, so a scene never loops.
///
/// Import translated the shaders (`SceneImporter`); load (`init`) reads the item, uploads its textures and
/// compiles the translated MSL; `draw` encodes one frame into the caller's command buffer and texture.
public final class SceneRenderer {
    public let document: SceneDocument
    /// Effects on image layers (off: the layers as plain images, for comparison).
    public var drawsEffects = true
    public var drawsParticles = true
    /// Things skipped or stood in for, once each.
    public var notes: [String] { noteList + textures.notes + programs.failures.map { "program \($0)" } }
    /// What the last frame drew, for diagnostics.
    public private(set) var drawnLayers: [String] = []

    let device: any MTLDevice
    let textures: TextureStore
    let programs: ProgramLibrary
    let engine: EnginePasses
    let quad: any MTLBuffer

    var width = 0
    var height = 0
    var projection = matrix_identity_float4x4
    var pixelsPerUnit: Float = 1
    var sceneColor: (any MTLTexture)?
    var targets: [String: any MTLTexture] = [:]
    var particleLayers: [Int: ParticleLayer] = [:]
    var puppets: [Int: PuppetInstance] = [:]
    private var noteList: [String] = []
    private var noteSet = Set<String>()

    /// Load. `manifest` is what `SceneImporter` wrote for this item.
    public init(folder: URL, manifest: ProgramManifest, device: any MTLDevice) throws {
        self.device = device
        document = try SceneDocument(folder: folder)
        textures = TextureStore(device: device, item: document.item)
        programs = ProgramLibrary(device: device, manifest: manifest)
        engine = try EnginePasses(device: device)
        // Clip-space quad, triangle strip; UV (0,0) at the top left, as in Direct3D and Metal.
        let v: [Float] = [-1, 1, 0, 0, 0, 1, 1, 0, 1, 0, -1, -1, 0, 0, 1, 1, -1, 0, 1, 1]
        quad = device.makeBuffer(bytes: v, length: v.count * 4)!
        preload()
    }

    /// Load from a library folder that import prepared (`SceneImporter.prepare` wrote the manifest beside
    /// the item's files). The shape of LivepaperScene's `SceneDrawing.init(folder:device:)`.
    public convenience init(folder: URL, device: any MTLDevice) throws {
        let manifest = try ProgramManifest.read(from: folder.appendingPathComponent(ProgramManifest.fileName))
        try self.init(folder: folder, manifest: manifest, device: device)
    }

    /// The output size in pixels. The scene covers it, centred, cropping the longer axis.
    public func resize(width: Int, height: Int) {
        guard width != self.width || height != self.height, width > 0, height > 0 else { return }
        self.width = width
        self.height = height
        let outAspect = Float(width) / Float(height)
        let sceneAspect = document.width / document.height
        var l: Float = 0, r = document.width, b: Float = 0, t = document.height
        if outAspect > sceneAspect {
            let visible = document.width / outAspect
            b = (document.height - visible) / 2
            t = b + visible
        } else {
            let visible = document.height * outAspect
            l = (document.width - visible) / 2
            r = l + visible
        }
        projection = Self.ortho(l, r, b, t)
        pixelsPerUnit = Float(width) / (r - l)
        targets = [:]
        sceneColor = makeTarget(width, height)
    }

    /// Encodes the frame at `time` seconds of scene time into `commandBuffer`, ending with `texture` (any
    /// size, any colour pixel format; the drawable's BGRA in the product). Does not commit or wait.
    public func draw(into texture: any MTLTexture, on cb: any MTLCommandBuffer, at sceneTime: Double) {
        if sceneColor == nil { resize(width: texture.width, height: texture.height) }
        guard let sceneColor else { return }
        let time = Float(sceneTime)
        textures.encodePendingWork(cb)
        drawnLayers = []
        clear(cb, sceneColor, document.clearColor)
        for (index, object) in document.objects.enumerated() {
            switch object {
            case .image(let layer) where layer.visible:
                switch layer.kind {
                case .image, .solid: drawImageLayer(cb, layer, time: time, into: sceneColor)
                case .fullscreen: drawFullscreenLayer(cb, layer, time: time, into: sceneColor)
                case .compose: drawComposeLayer(cb, layer, time: time, into: sceneColor)
                }
            case .particles(let p) where p.visible && drawsParticles:
                drawParticles(cb, p, index: index, time: time, into: sceneColor)
            case .sound(let s):
                note("sound is not played (\(s.files.joined(separator: ", ")))")
            default:
                break
            }
        }
        drawBloom(cb, into: sceneColor)
        engine.draw(cb, texture: sceneColor, sampler: textures.sampler(point: false, clamp: true), into: texture,
                    load: .dontCare, blending: .normal,
                    params: .init(mvp: matrix_identity_float4x4, rect: SIMD4(0, 0, 1, 1), color: .one, extra: .zero))
    }

    // MARK: Load

    /// Uploads every texture the scene names and reads its puppets and particle systems, so draw never
    /// decodes or parses.
    func preload() {
        for (index, object) in document.objects.enumerated() {
            switch object {
            case .image(let layer):
                if let name = layer.material?.textures.first ?? nil { _ = textures.texture(named: name) }
                for e in layer.effects {
                    for pass in e.passes {
                        for case let name? in pass.material?.textures ?? [] where !name.hasPrefix("_rt_") {
                            _ = textures.texture(named: name)
                        }
                    }
                }
                if let path = layer.puppetPath {
                    do {
                        puppets[layer.id] = try PuppetInstance(model: PuppetModel(data: document.item.data(path) ?? Data()),
                                                                device: device)
                    } catch {
                        note("puppet \(path): \(error)")
                    }
                }
            case .particles(let p):
                do {
                    let layer = try ParticleLayer(p, item: document.item)
                    particleLayers[index] = layer
                    let missing = Set(layer.unsupported)
                    if !missing.isEmpty { note("particle features not done: \(missing.sorted().joined(separator: ", ")) (\(p.file))") }
                } catch {
                    note("particles \(p.file): \(error)")
                }
                for def in ParticleLayer.definitions(p.file, item: document.item) {
                    if let m = ParticleLayer.material(def, item: document.item), let name = m.textures.first ?? nil {
                        _ = textures.texture(named: name)
                    }
                }
            default:
                break
            }
        }
        for entry in programs.manifest.programs.values {
            for name in entry.samplerDefaults.values where !name.hasPrefix("_rt_") { _ = textures.texture(named: name) }
        }
    }

    // MARK: Helpers

    func note(_ s: String) {
        if noteSet.insert(s).inserted { noteList.append(s) }
    }

    static func ortho(_ l: Float, _ r: Float, _ b: Float, _ t: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(2 / (r - l), 0, 0, 0), SIMD4(0, 2 / (t - b), 0, 0), SIMD4(0, 0, 1, 0),
                                SIMD4(-(r + l) / (r - l), -(t + b) / (t - b), 0.5, 1)))
    }

    /// Scene units → clip space for an object: translate to its origin, rotate about z, scale.
    func modelViewProjection(_ t: Transform2D, halfSize: SIMD2<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.origin.x, t.origin.y, 0, 1)
        let c = cos(t.angles.z), s = sin(t.angles.z)
        let rot = simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
        let scale = simd_float4x4(diagonal: SIMD4(halfSize.x * t.scale.x, halfSize.y * t.scale.y, 1, 1))
        return projection * m * rot * scale
    }

    func makeTarget(_ w: Int, _ h: Int) -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: max(1, w), height: max(1, h),
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }

    /// A named render target that lives as long as the output size does (effects with history keep theirs).
    func target(_ key: String, _ w: Int, _ h: Int) -> any MTLTexture {
        if let t = targets[key], t.width == max(1, w), t.height == max(1, h) { return t }
        let t = makeTarget(w, h)
        targets[key] = t
        return t
    }

    func clear(_ cb: any MTLCommandBuffer, _ texture: any MTLTexture, _ color: SIMD3<Float>) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = texture
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: Double(color.x), green: Double(color.y),
                                                          blue: Double(color.z), alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rp)?.endEncoding()
    }

    func copy(_ cb: any MTLCommandBuffer, from: any MTLTexture, to: any MTLTexture) {
        guard let blit = cb.makeBlitCommandEncoder() else { return }
        blit.copy(from: from, to: to)
        blit.endEncoding()
    }

    // MARK: Layers

    func drawImageLayer(_ cb: any MTLCommandBuffer, _ layer: ImageLayer, time: Float, into scene: any MTLTexture) {
        var material = layer.material ?? MaterialPass(json: ["shader": "genericimage2", "blending": "translucent"])
        let texture: GPUTexture
        if layer.kind == .solid {
            texture = textures.white
        } else if let name = material.textures.first ?? nil, let t = textures.texture(named: name) {
            texture = t
        } else {
            note("layer \(layer.name) has no texture")
            return
        }
        var size = layer.size
        if size.x == 0 || size.y == 0 { size = SIMD2(texture.resolution.z, texture.resolution.w) }
        let frame = texture.frame(at: time)
        let tint = layer.kind == .solid ? layer.color : layer.color * layer.brightness
        let base = Bound(texture: frame.texture, resolution: texture.resolution,
                         sampler: textures.sampler(point: texture.pointFiltered, clamp: texture.clamp))
        let puppet = puppets[layer.id]
        var combos = material.combos
        if puppet != nil { combos["SKINNING"] = 1 }
        material.combos = combos
        let request = ProgramRequest(shader: material.shader, combos: combos, boundSlots: [0])
        guard let program = programs.program(for: request) else {
            note("no program for \(request.signature)")
            return
        }
        let effects = drawsEffects ? layer.effects.filter(\.visible) : []
        let mvp = modelViewProjection(layer.transform, halfSize: size / 2)
        drawnLayers.append("\(layer.name) [\(material.shader)\(puppet != nil ? " puppet" : "")" +
                           (effects.isEmpty ? "" : " + " + effects.map(\.name).joined(separator: ", ")) + "]")
        var extra: [String: [Float]] = ["g_FrameRect": Self.floats(frame.rect)]
        var mesh: Mesh?
        if let puppet {
            extra["g_Bones"] = puppet.pose(at: time, halfSize: size / 2)
            mesh = puppet.mesh
        }
        if effects.isEmpty {
            extra["g_Color4"] = [tint.x, tint.y, tint.z, layer.alpha]
            drawMaterial(cb, program, material: material, blending: Blending(material.blending), into: scene, clear: false,
                         mvp: mvp, slots: [0: base], extra: extra, time: time, mesh: mesh)
            return
        }
        // Effects run in the layer's own space, at the size the layer covers on the output.
        let w = min(8192, Int((abs(size.x * layer.transform.scale.x) * pixelsPerUnit).rounded()))
        let h = min(8192, Int((abs(size.y * layer.transform.scale.y) * pixelsPerUnit).rounded()))
        let key = "layer\(layer.id)"
        let a = target("\(key).a", w, h)
        extra["g_Color4"] = [tint.x, tint.y, tint.z, 1]
        // A puppet's parts overlap, so they blend; a plain image replaces.
        drawMaterial(cb, program, material: material, blending: puppet == nil ? .normal : .translucent, into: a, clear: true,
                     mvp: matrix_identity_float4x4, slots: [0: base], extra: extra, time: time, mesh: mesh)
        let result = runEffects(cb, effects, layerKey: key, input: a, scene: scene, time: time)
        composite(cb, result, into: scene, mvp: mvp, blending: Blending(material.blending), alpha: layer.alpha)
    }

    /// Effects over everything drawn so far.
    func drawFullscreenLayer(_ cb: any MTLCommandBuffer, _ layer: ImageLayer, time: Float, into scene: any MTLTexture) {
        let effects = drawsEffects ? layer.effects.filter(\.visible) : []
        guard !effects.isEmpty else { return }
        drawnLayers.append("\(layer.name) [fullscreen + \(effects.map(\.name).joined(separator: ", "))]")
        let key = "layer\(layer.id)"
        let a = target("\(key).a", scene.width, scene.height)
        copy(cb, from: scene, to: a)
        let result = runEffects(cb, effects, layerKey: key, input: a, scene: scene, time: time)
        composite(cb, result, into: scene, mvp: matrix_identity_float4x4, blending: .normal, alpha: layer.alpha)
    }

    /// Effects over what is behind the layer's rectangle.
    func drawComposeLayer(_ cb: any MTLCommandBuffer, _ layer: ImageLayer, time: Float, into scene: any MTLTexture) {
        let effects = drawsEffects ? layer.effects.filter(\.visible) : []
        guard !effects.isEmpty, layer.size.x > 0, layer.size.y > 0 else { return }
        drawnLayers.append("\(layer.name) [compose + \(effects.map(\.name).joined(separator: ", "))]")
        let mvp = modelViewProjection(layer.transform, halfSize: layer.size / 2)
        // The layer's rectangle in the scene texture's UV (no rotation in the samples).
        let tl = mvp * SIMD4<Float>(-1, 1, 0, 1), br = mvp * SIMD4<Float>(1, -1, 0, 1)
        let u0 = (tl.x + 1) / 2, v0 = (1 - tl.y) / 2, u1 = (br.x + 1) / 2, v1 = (1 - br.y) / 2
        let w = max(1, Int((abs(u1 - u0) * Float(scene.width)).rounded()))
        let h = max(1, Int((abs(v1 - v0) * Float(scene.height)).rounded()))
        let key = "layer\(layer.id)"
        let a = target("\(key).a", w, h)
        engine.draw(cb, texture: scene, sampler: textures.sampler(point: false, clamp: true), into: a, load: .clear,
                    blending: .normal, params: .init(mvp: matrix_identity_float4x4, rect: SIMD4(u0, v0, u1 - u0, v1 - v0),
                                                     color: .one, extra: .zero))
        let result = runEffects(cb, effects, layerKey: key, input: a, scene: scene, time: time)
        composite(cb, result, into: scene, mvp: mvp, blending: .translucent, alpha: layer.alpha)
    }

    func composite(_ cb: any MTLCommandBuffer, _ texture: any MTLTexture, into scene: any MTLTexture,
                   mvp: simd_float4x4, blending: Blending, alpha: Float) {
        engine.draw(cb, texture: texture, sampler: textures.sampler(point: false, clamp: true), into: scene,
                    blending: blending, params: .init(mvp: mvp, rect: SIMD4(0, 0, 1, 1), color: SIMD4(1, 1, 1, alpha),
                                                      extra: .zero))
    }

    /// The scene's bloom (`general.bloom`): bright pass at quarter size, blurred, added back.
    func drawBloom(_ cb: any MTLCommandBuffer, into scene: any MTLTexture) {
        guard JSONValue.bool(document.general["bloom"], false) else { return }
        let strength = JSONValue.float(document.general["bloomstrength"], 2)
        let threshold = JSONValue.float(document.general["bloomthreshold"], 0.65)
        let w = max(1, scene.width / 4), h = max(1, scene.height / 4)
        let a = target("bloom.a", w, h), b = target("bloom.b", w, h)
        let linear = textures.sampler(point: false, clamp: true)
        let full = SIMD4<Float>(0, 0, 1, 1)
        engine.draw(cb, fragment: "lp_bright", texture: scene, sampler: linear, into: a, load: .dontCare, blending: .normal,
                    params: .init(mvp: matrix_identity_float4x4, rect: full, color: .one, extra: SIMD4(threshold, 0, 0, 0)))
        for _ in 0..<2 {
            engine.draw(cb, fragment: "lp_blur", texture: a, sampler: linear, into: b, load: .dontCare, blending: .normal,
                        params: .init(mvp: matrix_identity_float4x4, rect: full, color: .one, extra: SIMD4(0, 0, 1 / Float(w), 0)))
            engine.draw(cb, fragment: "lp_blur", texture: b, sampler: linear, into: a, load: .dontCare, blending: .normal,
                        params: .init(mvp: matrix_identity_float4x4, rect: full, color: .one, extra: SIMD4(0, 0, 0, 1 / Float(h))))
        }
        engine.draw(cb, texture: a, sampler: linear, into: scene, blending: .additive,
                    params: .init(mvp: matrix_identity_float4x4, rect: full, color: SIMD4(1, 1, 1, strength / 2), extra: .zero))
    }

    static func floats(_ s: SIMD4<Float>) -> [Float] { [s.x, s.y, s.z, s.w] }
}
