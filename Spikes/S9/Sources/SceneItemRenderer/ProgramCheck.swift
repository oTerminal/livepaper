import Foundation
import Metal
import SceneImport

/// Compiles one translated program and links it into a pipeline, as load would: for reporting.
public enum ProgramCheck {
    public enum Result {
        case ok
        case compileFailed(String)
        case linkFailed(String)
    }

    public static func run(_ entry: ProgramManifest.Entry, device: any MTLDevice) -> Result {
        let vf: any MTLFunction, ff: any MTLFunction
        do {
            let v = try device.makeLibrary(source: entry.program.vertex.msl, options: nil)
            let f = try device.makeLibrary(source: entry.program.fragment.msl, options: nil)
            guard let a = v.makeFunction(name: entry.program.vertex.entryPoint),
                  let b = f.makeFunction(name: entry.program.fragment.entryPoint) else { return .compileFailed("no entry point") }
            vf = a
            ff = b
        } catch {
            return .compileFailed(firstError("\(error)"))
        }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vf
        d.fragmentFunction = ff
        d.vertexDescriptor = ProgramLibrary.vertexDescriptor(for: entry.program.vertex.attributes)
        d.colorAttachments[0].pixelFormat = .rgba8Unorm
        do {
            _ = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            return .linkFailed(firstError("\(error)"))
        }
        return .ok
    }

    static func firstError(_ s: String) -> String {
        let lines = s.split(separator: "\n").map(String.init)
        return lines.first { $0.contains("error:") } ?? lines.first ?? s
    }
}
