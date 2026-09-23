import Foundation
import SceneItemFormat
import SceneShaderTranslation

/// Import-time work for a scene item: find every program it draws with and translate each to MSL.
public enum SceneImporter {
    /// Our base materials (genericimage, genericimage2, genericimage4, genericparticle). Wallpaper Engine
    /// ships its own with the app, not with items; these are written from scratch.
    public static var builtinMaterialsDirectory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("materials")
    }

    public struct Sources {
        public let vertex: String
        public let fragment: String
        /// "item" or "builtin".
        public let origin: String
    }

    /// The item's own copy of a shader first; otherwise ours.
    public static func sources(for shader: String, in doc: SceneDocument) -> Sources? {
        if let v = doc.itemShader(shader, stage: "vert"), let f = doc.itemShader(shader, stage: "frag") {
            return Sources(vertex: v, fragment: f, origin: "item")
        }
        let base = shader.hasPrefix("genericimage") ? "genericimage" : shader
        let dir = builtinMaterialsDirectory
        guard let v = try? String(contentsOf: dir.appendingPathComponent("\(base).vert"), encoding: .utf8),
              let f = try? String(contentsOf: dir.appendingPathComponent("\(base).frag"), encoding: .utf8) else { return nil }
        return Sources(vertex: v, fragment: f, origin: "builtin")
    }

    public static func programKey(shader: String, defines: [(String, Int)]) -> String {
        "\(shader)|" + defines.map { "\($0.0)=\($0.1)" }.joined(separator: ",")
    }

    /// Translates one request into `manifest`. Returns the failure, if any.
    @discardableResult
    public static func add(_ request: ProgramRequest, doc: SceneDocument, translator: ShaderTranslator,
                           to manifest: inout ProgramManifest) -> String? {
        guard let src = sources(for: request.shader, in: doc) else {
            let reason = "no source for \(request.shader)"
            manifest.failures[request.signature] = reason
            return reason
        }
        let annotations = ShaderAnnotations(sources: [src.vertex, src.fragment])
        let defines = annotations.defines(explicit: request.combos, boundSlots: request.boundSlots)
        let key = programKey(shader: request.shader, defines: defines)
        if manifest.programs[key] == nil {
            switch translator.translate(vertex: src.vertex, fragment: src.fragment, defines: defines) {
            case .success(let program):
                var uniforms: [String: ProgramManifest.UniformSource] = [:]
                var samplerDefaults: [String: String] = [:]
                for (name, u) in annotations.uniforms {
                    if u.type.hasPrefix("sampler") {
                        if let slot = ShaderAnnotations.textureSlot(name), let d = u.json?["default"] as? String {
                            samplerDefaults[String(slot)] = d
                        }
                    } else {
                        uniforms[name] = .init(materialKey: u.materialKey, defaultValue: JSONValue.floats(u.defaultValue))
                    }
                }
                manifest.programs[key] = .init(shader: request.shader, defines: Dictionary(uniqueKeysWithValues: defines),
                                               origin: src.origin, program: program, uniforms: uniforms,
                                               samplerDefaults: samplerDefaults)
            case .failure(let f):
                manifest.failures[request.signature] = f.description
                return f.description
            }
        }
        manifest.requests[request.signature] = key
        return nil
    }

    /// Every program of the scene. Programs that fail are listed in `failures`; the renderer skips what uses them.
    public static func translateShaders(of doc: SceneDocument, translator: ShaderTranslator) -> ProgramManifest {
        var manifest = ProgramManifest()
        for request in ProgramRequest.all(in: doc) {
            add(request, doc: doc, translator: translator, to: &manifest)
        }
        return manifest
    }

    /// The import step for a library folder holding the item's files: writes the manifest beside them,
    /// where `SceneRenderer(folder:device:)` reads it. The shape of LivepaperScene's `ScenePreparation.prepare`.
    @discardableResult
    public static func prepare(_ folder: URL, translator: ShaderTranslator) throws -> ProgramManifest {
        let manifest = translateShaders(of: try SceneDocument(folder: folder), translator: translator)
        try manifest.write(to: folder.appendingPathComponent(ProgramManifest.fileName))
        return manifest
    }
}
