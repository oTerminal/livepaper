import Foundation
import Metal
import simd

/// The renderer's own passes, in plain MSL (not Workshop materials): copying a layer onto the scene,
/// presenting the scene into the caller's texture, and the scene-wide bloom.
final class EnginePasses {
    struct Params {
        var mvp: simd_float4x4
        var rect: SIMD4<Float>
        var color: SIMD4<Float>
        /// x: bloom threshold; zw: blur step in UV.
        var extra: SIMD4<Float>
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct QuadOut { float4 position [[position]]; float2 uv; };
    struct Params { float4x4 mvp; float4 rect; float4 color; float4 extra; };

    vertex QuadOut lp_quad(uint vid [[vertex_id]], constant Params& p [[buffer(0)]]) {
        float2 corner = float2(vid & 1, vid >> 1);
        QuadOut o;
        o.position = p.mvp * float4(corner.x * 2 - 1, 1 - corner.y * 2, 0, 1);
        o.uv = p.rect.xy + corner * p.rect.zw;
        return o;
    }

    fragment float4 lp_textured(QuadOut in [[stage_in]], constant Params& p [[buffer(0)]],
                                texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        return t.sample(s, in.uv) * p.color;
    }

    // Bloom bright pass: what is above the threshold, scaled down smoothly.
    fragment float4 lp_bright(QuadOut in [[stage_in]], constant Params& p [[buffer(0)]],
                              texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        float3 c = t.sample(s, in.uv).rgb;
        float l = max(c.r, max(c.g, c.b));
        float k = max(0.0, l - p.extra.x) / max(l, 1e-4);
        return float4(c * k, 1);
    }

    // Nine-tap binomial blur along extra.zw.
    fragment float4 lp_blur(QuadOut in [[stage_in]], constant Params& p [[buffer(0)]],
                            texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        const float w[5] = { 70.0, 56.0, 28.0, 8.0, 1.0 };
        float4 sum = t.sample(s, in.uv) * w[0];
        for (int i = 1; i < 5; i++) {
            sum += (t.sample(s, in.uv + p.extra.zw * i) + t.sample(s, in.uv - p.extra.zw * i)) * w[i];
        }
        return sum / 256.0;
    }
    """

    let device: any MTLDevice
    let library: any MTLLibrary
    private var pipelines: [String: any MTLRenderPipelineState] = [:]

    init(device: any MTLDevice) throws {
        self.device = device
        library = try device.makeLibrary(source: Self.source, options: nil)
    }

    func pipeline(_ fragment: String, blending: Blending, pixelFormat: MTLPixelFormat) -> any MTLRenderPipelineState {
        let key = "\(fragment)-\(blending.rawValue)-\(pixelFormat.rawValue)"
        if let p = pipelines[key] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "lp_quad")
        d.fragmentFunction = library.makeFunction(name: fragment)
        d.colorAttachments[0].pixelFormat = pixelFormat
        blending.apply(to: d.colorAttachments[0])
        let p = try! device.makeRenderPipelineState(descriptor: d)
        pipelines[key] = p
        return p
    }

    /// Draws `texture` over `rect` of itself onto `target` with `mvp`.
    func draw(_ cb: any MTLCommandBuffer, fragment: String = "lp_textured", texture: any MTLTexture,
              sampler: any MTLSamplerState, into target: any MTLTexture, load: MTLLoadAction = .load,
              blending: Blending, params: Params) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = load
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.label = fragment
        enc.setRenderPipelineState(pipeline(fragment, blending: blending, pixelFormat: target.pixelFormat))
        var p = params
        enc.setVertexBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
        enc.setFragmentBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }
}
