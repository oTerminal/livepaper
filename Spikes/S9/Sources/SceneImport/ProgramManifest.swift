import Foundation
import SceneShaderTranslation

/// What import leaves for load: every program a scene draws with, already translated to MSL, with what
/// the renderer needs to fill its uniforms. Load never runs the translator.
public struct ProgramManifest: Codable, Sendable {
    /// Where a uniform's value comes from when the engine does not supply it.
    public struct UniformSource: Codable, Sendable {
        /// Key into the material's (and scene's) `constantshadervalues`.
        public let materialKey: String?
        /// The annotation's "default", as floats.
        public let defaultValue: [Float]?
    }

    public struct Entry: Codable, Sendable {
        public let shader: String
        public let defines: [String: Int]
        /// "item" (the Workshop item's own source) or "builtin" (ours, written from scratch).
        public let origin: String
        public let program: TranslatedProgram
        public let uniforms: [String: UniformSource]
        /// Slot → the texture a sampler asks for when nothing is bound ("util/white", "_rt_FullFrameBuffer").
        public let samplerDefaults: [String: String]
    }

    public static let fileName = "scene-programs.json"
    public static let formatVersion = 1

    public var version = ProgramManifest.formatVersion
    /// Program key (shader + defines) → program.
    public var programs: [String: Entry] = [:]
    /// Request signature → program key.
    public var requests: [String: String] = [:]
    /// Request signature → why it could not be translated.
    public var failures: [String: String] = [:]

    public init() {}

    public func entry(for request: ProgramRequest) -> Entry? {
        requests[request.signature].flatMap { programs[$0] }
    }

    public static func read(from url: URL) throws -> ProgramManifest {
        try JSONDecoder().decode(ProgramManifest.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
