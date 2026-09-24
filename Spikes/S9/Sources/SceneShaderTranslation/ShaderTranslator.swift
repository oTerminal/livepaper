import CryptoKit
import Foundation

public enum ShaderStage: String, Sendable {
    case vertex = "vert"
    case fragment = "frag"
}

public struct Varying: Codable, Sendable {
    public let name: String
    public let type: String
}

public struct VertexAttribute: Codable, Sendable {
    public let name: String
    public let type: String
    public let location: Int
}

/// One stage after translation: the Vulkan GLSL we handed glslang, the MSL SPIRV-Cross gave back, and what
/// the renderer needs to bind it.
public struct TranslatedStage: Codable, Sendable {
    public var glsl = ""
    public var msl = ""
    /// Entry point in `msl`.
    public var entryPoint = "main0"
    /// Every non-sampler uniform, in one block at buffer index 0.
    public var uniforms = UniformLayout()
    /// Sampler name → texture and sampler index. `g_TextureN` is always N.
    public var samplers: [String: Int] = [:]
    /// Vertex: the varyings written, in location order. Fragment: the varyings read.
    public var varyings: [Varying] = []
    /// Vertex attributes (`a_Position` 0, `a_TexCoord` 1, `a_Color` 2, …).
    public var attributes: [VertexAttribute] = []
}

public struct TranslatedProgram: Codable, Sendable {
    public let vertex: TranslatedStage
    public let fragment: TranslatedStage
}

public struct TranslationFailure: Error, CustomStringConvertible {
    public enum Step: String, Sendable {
        case preprocess, glslang = "glslang → SPIR-V", spirvCross = "SPIRV-Cross → MSL"
    }

    public let stage: ShaderStage
    public let step: Step
    public let message: String
    public var description: String { "\(stage.rawValue) \(step.rawValue): \(message)" }
}

/// Workshop GLSL → Metal Shading Language:
///
/// 1. prepend the combo defines and our `common.h`, run glslang's preprocessor (`#include` resolves against
///    our headers, written from scratch);
/// 2. rewrite the GLSL 1.x declarations for Vulkan GLSL 4.50: `attribute`/`varying` get locations (varyings
///    matched by name across the stages), loose uniforms move into one std140 block, samplers get bindings;
/// 3. glslang → SPIR-V; SPIRV-Cross → MSL with bindings taken from the SPIR-V decorations.
///
/// The spike runs Homebrew's command-line tools; the product would link the two libraries instead.
public final class ShaderTranslator {
    public let includeDirectory: URL
    public let workDirectory: URL
    public var glslangPath = "/opt/homebrew/bin/glslang"
    public var spirvCrossPath = "/opt/homebrew/bin/spirv-cross"

    /// Our replacements for the headers Wallpaper Engine ships (common.h, common_blending.h, …).
    public static var bundledIncludeDirectory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("include")
    }

    public init(includeDirectory: URL = ShaderTranslator.bundledIncludeDirectory, workDirectory: URL) {
        self.includeDirectory = includeDirectory
        self.workDirectory = workDirectory
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    public func translate(vertex: String, fragment: String, defines: [(String, Int)]) -> Result<TranslatedProgram, TranslationFailure> {
        let v: TranslatedStage
        switch translate(stage: .vertex, source: vertex, defines: defines) {
        case .success(let s): v = s
        case .failure(let f): return .failure(f)
        }
        switch translate(stage: .fragment, source: fragment, defines: defines, vertexVaryings: v.varyings) {
        case .success(let f): return .success(TranslatedProgram(vertex: v, fragment: f))
        case .failure(let f): return .failure(f)
        }
    }

    static let attributeLocations = ["a_Position": 0, "a_TexCoord": 1, "a_Color": 2, "a_TexCoordVec4": 3,
                                     "a_TexCoordVec4C1": 4, "a_Normal": 5, "a_Tangent4": 6, "a_TexCoordC2": 7]

    static let declaration = try! NSRegularExpression(
        pattern: #"^\s*(attribute|varying|uniform)\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*(?:\[\s*(\w+)\s*\])?\s*;\s*$"#)

    /// - Parameter vertexVaryings: for a fragment stage, the vertex stage's varyings (locations by position).
    public func translate(stage: ShaderStage, source: String, defines: [(String, Int)],
                          vertexVaryings: [Varying] = []) -> Result<TranslatedStage, TranslationFailure> {
        func fail(_ step: TranslationFailure.Step, _ output: String) -> Result<TranslatedStage, TranslationFailure> {
            .failure(TranslationFailure(stage: stage, step: step, message: Self.firstError(output)))
        }
        var pre = "#version 450\n#extension GL_GOOGLE_include_directive : enable\n"
        for (name, value) in defines { pre += "#define \(name) \(value)\n" }
        if stage == .fragment { pre += "#define gl_FragColor _lpFragColor\n" }
        pre += "#include \"common.h\"\n" + source
        let work = workDirectory.appendingPathComponent(Self.hash(stage.rawValue + pre))
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let input = work.appendingPathComponent("in.\(stage.rawValue)")
        try? pre.write(to: input, atomically: true, encoding: .utf8)

        // 1. Preprocess.
        let (ppStatus, preprocessed, ppErr) = run(glslangPath, ["-E", "-I\(includeDirectory.path)", input.path])
        guard ppStatus == 0 else { return fail(.preprocess, ppErr + preprocessed) }

        // 2. Rewrite declarations.
        var result = TranslatedStage()
        var body: [String] = []
        var block: [(type: String, name: String, count: Int?)] = []
        var nextSampler = 8, nextAttribute = 8
        for line in preprocessed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let s = String(line)
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#version") || t.hasPrefix("#extension") || t.hasPrefix("#line") || t.hasPrefix("#pragma") {
                continue
            }
            let ns = s as NSString
            guard let m = Self.declaration.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
                body.append(s)
                continue
            }
            let kind = ns.substring(with: m.range(at: 1))
            let type = ns.substring(with: m.range(at: 2))
            let name = ns.substring(with: m.range(at: 3))
            let count = m.range(at: 4).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 4)))
            switch kind {
            case "attribute":
                let loc = Self.attributeLocations[name] ?? { nextAttribute += 1; return nextAttribute - 1 }()
                result.attributes.append(VertexAttribute(name: name, type: type, location: loc))
                body.append("layout(location = \(loc)) in \(type) \(name);")
            case "varying" where stage == .vertex:
                body.append("layout(location = \(result.varyings.count)) out \(type) \(name);")
                result.varyings.append(Varying(name: name, type: type))
            case "varying":
                if let loc = vertexVaryings.firstIndex(where: { $0.name == name }) {
                    let vtype = vertexVaryings[loc].type
                    result.varyings.append(Varying(name: name, type: type))
                    if vtype == type {
                        body.append("layout(location = \(loc)) in \(type) \(name);")
                    } else {
                        // Declared with a different type in the two stages: read the vertex's, convert.
                        body.append("layout(location = \(loc)) in \(vtype) _lpIn_\(name);")
                        body.append("\(type) \(name) = \(type)(_lpIn_\(name));")
                    }
                } else {
                    // Read but never written by the vertex stage (waterripple.frag's v_Scroll): a plain zero.
                    body.append("\(type) \(name);")
                }
            default:
                if type.hasPrefix("sampler") {
                    let binding = ShaderAnnotations.textureSlot(name) ?? { nextSampler += 1; return nextSampler - 1 }()
                    result.samplers[name] = binding
                    body.append("layout(set = 0, binding = \(binding)) uniform \(type) \(name);")
                } else if !block.contains(where: { $0.name == name }) {
                    block.append((type, name, count))
                }
            }
        }
        result.uniforms = UniformLayout.std140(block)
        var glsl = "#version 450\n"
        if stage == .fragment { glsl += "layout(location = 0) out vec4 _lpFragColor;\n" }
        if !block.isEmpty {
            glsl += "layout(std140, set = 1, binding = 0) uniform LPUniforms {\n"
            for d in block { glsl += "    \(d.type) \(d.name)\(d.count.map { "[\($0)]" } ?? "");\n" }
            glsl += "};\n"
        }
        glsl += body.joined(separator: "\n")
        result.glsl = glsl
        let glslFile = work.appendingPathComponent("lp.\(stage.rawValue)")
        try? glsl.write(to: glslFile, atomically: true, encoding: .utf8)

        // 3. SPIR-V, then MSL.
        let spv = work.appendingPathComponent("\(stage.rawValue).spv")
        let (gStatus, gOut, gErr) = run(glslangPath, ["-V", "--target-env", "vulkan1.1", "-o", spv.path, glslFile.path])
        guard gStatus == 0 else { return fail(.glslang, gOut + gErr) }
        let mslFile = work.appendingPathComponent("\(stage.rawValue).metal")
        let (cStatus, cOut, cErr) = run(spirvCrossPath, [spv.path, "--msl", "--msl-version", "20400",
                                                        "--msl-decoration-binding", "--output", mslFile.path])
        guard cStatus == 0, let msl = try? String(contentsOf: mslFile, encoding: .utf8) else {
            return fail(.spirvCross, cOut + cErr)
        }
        result.msl = msl
        return .success(result)
    }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    static func firstError(_ text: String) -> String {
        let lines = text.split(separator: "\n").map(String.init)
        let error = lines.first { $0.contains("ERROR") || $0.contains("error") } ?? lines.first ?? "unknown"
        // Drop the temporary path glslang prefixes.
        if let r = error.range(of: #"[^ ]*/lp\.(vert|frag):"#, options: .regularExpression) {
            return error.replacingCharacters(in: r, with: "line ").trimmingCharacters(in: .whitespaces)
        }
        return error.trimmingCharacters(in: .whitespaces)
    }

    func run(_ tool: String, _ args: [String]) -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}
