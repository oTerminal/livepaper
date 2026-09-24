import Foundation
import Metal
import SceneImport
import SceneItemFormat
import SceneShaderTranslation
import simd

/// A texture bound to a material slot, with what g_TextureNResolution reports for it.
struct Bound {
    let texture: any MTLTexture
    let resolution: SIMD4<Float>
    let sampler: any MTLSamplerState

    init(texture: any MTLTexture, resolution: SIMD4<Float>, sampler: any MTLSamplerState) {
        self.texture = texture
        self.resolution = resolution
        self.sampler = sampler
    }
}

/// Vertices other than the quad: particles (triangles) or a puppet mesh (indexed triangles).
struct Mesh {
    let vertices: any MTLBuffer
    let vertexCount: Int
    let indices: (buffer: any MTLBuffer, count: Int)?
}

extension SceneRenderer {
    func bound(_ g: GPUTexture, time: Float) -> Bound {
        let f = g.frame(at: time)
        return Bound(texture: f.texture, resolution: g.resolution, sampler: textures.sampler(point: g.pointFiltered, clamp: g.clamp))
    }

    func bound(target t: any MTLTexture) -> Bound {
        let w = Float(t.width), h = Float(t.height)
        return Bound(texture: t, resolution: SIMD4(w, h, w, h), sampler: textures.sampler(point: false, clamp: true))
    }

    /// Draws one material pass: the quad (or `mesh`) with a translated program, its uniforms filled from
    /// `extra`, the engine's values, the material's constants and the shader's defaults, in that order.
    func drawMaterial(_ cb: any MTLCommandBuffer, _ program: CompiledProgram, material: MaterialPass?, blending: Blending,
                      into target: any MTLTexture, clear: Bool, mvp: simd_float4x4, slots: [Int: Bound],
                      extra: [String: [Float]], time: Float, mesh: Mesh? = nil) {
        let pipeline: any MTLRenderPipelineState
        do {
            pipeline = try programs.pipeline(program, blending: blending, pixelFormat: target.pixelFormat)
        } catch {
            note("pipeline for \(program.name): \(error)")
            return
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = clear ? .clear : .load
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.label = program.name
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(mesh?.vertices ?? quad, offset: 0, index: VertexLayout.bufferIndex)
        let value = { (m: UniformLayout.Member) in
            self.uniformValue(m, program: program, material: material, mvp: mvp, slots: slots, extra: extra, time: time)
        }
        let vb = program.vertex.uniforms.pack(value)
        let fb = program.fragment.uniforms.pack(value)
        setBytes(enc, vb, vertex: true)
        setBytes(enc, fb, vertex: false)
        let white = bound(textures.white, time: time)
        for binding in program.fragment.samplers.values {
            let b = slots[binding] ?? white
            enc.setFragmentTexture(b.texture, index: binding)
            enc.setFragmentSamplerState(b.sampler, index: binding)
        }
        for binding in program.vertex.samplers.values {
            let b = slots[binding] ?? white
            enc.setVertexTexture(b.texture, index: binding)
            enc.setVertexSamplerState(b.sampler, index: binding)
        }
        if let mesh, let indices = mesh.indices {
            enc.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: .uint16,
                                      indexBuffer: indices.buffer, indexBufferOffset: 0)
        } else if let mesh {
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
        } else {
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
    }

    private func setBytes(_ enc: any MTLRenderCommandEncoder, _ bytes: [UInt8], vertex: Bool) {
        if bytes.count <= 4096 {
            if vertex { enc.setVertexBytes(bytes, length: bytes.count, index: 0) } else { enc.setFragmentBytes(bytes, length: bytes.count, index: 0) }
        } else if let buffer = device.makeBuffer(bytes: bytes, length: bytes.count) {
            if vertex { enc.setVertexBuffer(buffer, offset: 0, index: 0) } else { enc.setFragmentBuffer(buffer, offset: 0, index: 0) }
        }
    }

    static func flatten(_ m: simd_float4x4) -> [Float] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    func uniformValue(_ m: UniformLayout.Member, program: CompiledProgram, material: MaterialPass?, mvp: simd_float4x4,
                      slots: [Int: Bound], extra: [String: [Float]], time: Float) -> [Float]? {
        if let e = extra[m.name] { return e }
        if let s = engineValue(m.name, mvp: mvp, slots: slots, time: time) { return s }
        if let source = program.entry.uniforms[m.name] {
            if let key = source.materialKey, let v = material?.constants[key], let f = JSONValue.floats(v) { return f }
            if let d = source.defaultValue { return d }
        }
        note("uniform \(m.name) of \(program.name) has no value; zero")
        return nil
    }

    /// Values the engine supplies (Wallpaper Engine's names, inferred from how the shaders use them).
    func engineValue(_ name: String, mvp: simd_float4x4, slots: [Int: Bound], time: Float) -> [Float]? {
        switch name {
        case "g_ModelViewProjectionMatrix", "g_EffectModelViewProjectionMatrix":
            return Self.flatten(mvp)
        case "g_EffectTextureProjectionMatrix", "g_EffectTextureProjectionMatrixInverse":
            return Self.flatten(matrix_identity_float4x4)
        case "g_Time":
            return [time]
        case "g_Screen":
            return [Float(width), Float(height), Float(width) / Float(height)]
        case "g_ParallaxPosition", "g_PointerPosition", "g_PointerPositionLast":
            // No pointer on a wallpaper that is not interactive: the centre.
            return [0.5, 0.5]
        default:
            if name.hasPrefix("g_AudioSpectrum") {
                note("audio-reactive uniforms get silence (\(name))")
                return []
            }
            if name.hasPrefix("g_Texture"), name.hasSuffix("Resolution"),
               let slot = Int(name.dropFirst("g_Texture".count).dropLast("Resolution".count)) {
                let r = slots[slot]?.resolution ?? SIMD4(1, 1, 1, 1)
                return [r.x, r.y, r.z, r.w]
            }
            return nil
        }
    }
}
