import Foundation
import Metal
import SceneImport
import SceneShaderTranslation

/// A translated program compiled for this device.
final class CompiledProgram {
    let key: String
    let entry: ProgramManifest.Entry
    let vertexFunction: any MTLFunction
    let fragmentFunction: any MTLFunction
    var pipelines: [String: any MTLRenderPipelineState] = [:]

    init(key: String, entry: ProgramManifest.Entry, vertexFunction: any MTLFunction, fragmentFunction: any MTLFunction) {
        self.key = key
        self.entry = entry
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
    }

    var name: String { entry.shader }
    var vertex: TranslatedStage { entry.program.vertex }
    var fragment: TranslatedStage { entry.program.fragment }
}

/// Blend states the materials ask for.
enum Blending: String {
    case normal, translucent, additive

    init(_ material: String) { self = Blending(rawValue: material) ?? .normal }

    func apply(to c: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .normal:
            c.isBlendingEnabled = false
        case .translucent:
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .sourceAlpha
            c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .sourceAlpha
            c.destinationRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .zero
            c.destinationAlphaBlendFactor = .one
        }
    }
}

/// Vertex buffer layouts the renderer feeds.
enum VertexLayout {
    /// Position (float3) and UV (float2): quads.
    static let quadStride = 20
    /// Position, UV, colour (float4): particles.
    static let particleStride = 36
    /// Position, UV, bone indices (float4), bone weights (float4): puppets.
    static let skinnedStride = 52
    static let bufferIndex = 16
}

/// Compiles the manifest's MSL at load and builds pipelines on first use.
final class ProgramLibrary {
    let device: any MTLDevice
    let manifest: ProgramManifest
    private var programs: [String: CompiledProgram] = [:]
    private(set) var failures: [String] = []

    init(device: any MTLDevice, manifest: ProgramManifest) {
        self.device = device
        self.manifest = manifest
        for (key, entry) in manifest.programs.sorted(by: { $0.key < $1.key }) {
            do {
                let v = try device.makeLibrary(source: entry.program.vertex.msl, options: nil)
                let f = try device.makeLibrary(source: entry.program.fragment.msl, options: nil)
                guard let vf = v.makeFunction(name: entry.program.vertex.entryPoint),
                      let ff = f.makeFunction(name: entry.program.fragment.entryPoint) else {
                    failures.append("\(key): no entry point")
                    continue
                }
                programs[key] = CompiledProgram(key: key, entry: entry, vertexFunction: vf, fragmentFunction: ff)
            } catch {
                let first = "\(error)".split(separator: "\n").first { $0.contains("error:") } ?? "\(error)".split(separator: "\n").first ?? ""
                failures.append("\(key): Metal compile: \(first)")
            }
        }
        for (signature, reason) in manifest.failures { failures.append("\(signature): \(reason)") }
    }

    func program(for request: ProgramRequest) -> CompiledProgram? {
        manifest.requests[request.signature].flatMap { programs[$0] }
    }

    func pipeline(_ program: CompiledProgram, blending: Blending, pixelFormat: MTLPixelFormat) throws -> any MTLRenderPipelineState {
        let key = "\(blending.rawValue)-\(pixelFormat.rawValue)"
        if let p = program.pipelines[key] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = program.vertexFunction
        d.fragmentFunction = program.fragmentFunction
        d.vertexDescriptor = Self.vertexDescriptor(for: program.vertex.attributes)
        d.colorAttachments[0].pixelFormat = pixelFormat
        blending.apply(to: d.colorAttachments[0])
        let p = try device.makeRenderPipelineState(descriptor: d)
        program.pipelines[key] = p
        return p
    }

    static func stride(for attributes: [VertexAttribute]) -> Int {
        let names = Set(attributes.map(\.name))
        if names.contains("a_BlendIndices") { return VertexLayout.skinnedStride }
        if names.contains("a_Color") { return VertexLayout.particleStride }
        return VertexLayout.quadStride
    }

    static func vertexDescriptor(for attributes: [VertexAttribute]) -> MTLVertexDescriptor {
        let vd = MTLVertexDescriptor()
        for a in attributes {
            let (format, offset): (MTLVertexFormat, Int) = switch a.name {
            case "a_Position": (.float3, 0)
            case "a_TexCoord": (.float2, 12)
            case "a_Color": (.float4, 20)
            case "a_BlendIndices": (.float4, 20)
            case "a_BlendWeights": (.float4, 36)
            // Not fed by S9: read the UV again so the pipeline links.
            default: (.float2, 12)
            }
            vd.attributes[a.location].format = format
            vd.attributes[a.location].offset = offset
            vd.attributes[a.location].bufferIndex = VertexLayout.bufferIndex
        }
        vd.layouts[VertexLayout.bufferIndex].stride = stride(for: attributes)
        return vd
    }
}
