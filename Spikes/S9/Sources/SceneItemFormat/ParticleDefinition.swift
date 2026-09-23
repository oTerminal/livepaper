import Foundation

/// A particle system file (`particles/**/*.json`): one emitter list, initializers, operators, renderers,
/// a material and child systems. Parameters stay as JSON; the simulation reads what it understands.
public struct ParticleDefinition {
    public struct Component {
        public let name: String
        public let params: [String: Any]

        public func float(_ key: String, _ fallback: Float) -> Float { JSONValue.float(params[key], fallback) }
        public func vec3(_ key: String, _ fallback: SIMD3<Float>) -> SIMD3<Float> { JSONValue.vec3(params[key], fallback) }
        public func has(_ key: String) -> Bool { params[key] != nil && !(params[key] is NSNull) }
    }

    public struct Child {
        public let file: String
        /// nil: a second system that lives beside the parent. "eventspawn": a burst where a parent particle dies.
        public let type: String?
        public let maxCount: Int?
        public let origin: SIMD3<Float>
        public let scale: SIMD3<Float>
        public let probability: Float
    }

    public struct ControlPoint {
        public let id: Int
        public let flags: Int
        public let offset: SIMD3<Float>
    }

    public let file: String
    public let materialPath: String
    public let maxCount: Int
    /// Seconds simulated before the first frame.
    public let startTime: Float
    public let emitters: [Component]
    public let initializers: [Component]
    public let operators: [Component]
    public let renderers: [Component]
    public let children: [Child]
    public let controlPoints: [ControlPoint]
    /// "sequence", "randomframe" or nil: the texture is a sprite sheet.
    public let animationMode: String?

    public init(item: ItemFiles, file: String) throws {
        let json = try item.json(file)
        self.file = file
        guard let material = json["material"] as? String else { throw ReadError("\(file) has no material") }
        materialPath = material
        maxCount = JSONValue.int(json["maxcount"]) ?? 100
        startTime = JSONValue.float(json["starttime"], 0)
        func list(_ key: String) -> [Component] {
            (json[key] as? [[String: Any]] ?? []).map { Component(name: $0["name"] as? String ?? "?", params: $0) }
        }
        emitters = list("emitter")
        initializers = list("initializer")
        operators = list("operator")
        renderers = list("renderer")
        children = (json["children"] as? [[String: Any]] ?? []).compactMap { c in
            guard let name = c["name"] as? String else { return nil }
            return Child(file: name, type: c["type"] as? String, maxCount: JSONValue.int(c["maxcount"]),
                         origin: JSONValue.vec3(c["origin"], .zero), scale: JSONValue.vec3(c["scale"], .one),
                         probability: JSONValue.float(c["probability"], 1))
        }
        controlPoints = (json["controlpoint"] as? [[String: Any]] ?? []).map {
            ControlPoint(id: JSONValue.int($0["id"]) ?? 0, flags: JSONValue.int($0["flags"]) ?? 0,
                         offset: JSONValue.vec3($0["offset"], .zero))
        }
        animationMode = json["animationmode"] as? String
    }

    public func initializer(_ name: String) -> Component? { initializers.first { $0.name == name } }
    public func op(_ name: String) -> Component? { operators.first { $0.name == name } }
}
