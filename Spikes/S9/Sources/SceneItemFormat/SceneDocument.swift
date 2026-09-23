import Foundation
import simd

/// One material pass (`materials/*.json` → passes[0]), with a scene's overrides merged in.
public struct MaterialPass {
    public var shader: String
    /// Texture names by slot (`masks/foo` means `materials/masks/foo.tex`; `_rt_*` names a render target).
    public var textures: [String?]
    /// Combo values, upper-cased.
    public var combos: [String: Int]
    /// "normal" (replace), "translucent", "additive".
    public var blending: String
    /// Shader constants keyed by the uniform annotation's "material" name.
    public var constants: [String: Any]

    public init(json: [String: Any]) {
        shader = json["shader"] as? String ?? "?"
        textures = (json["textures"] as? [Any])?.map { $0 as? String } ?? []
        combos = Self.intDict(json["combos"])
        blending = json["blending"] as? String ?? "normal"
        constants = json["constantshadervalues"] as? [String: Any] ?? [:]
    }

    static func intDict(_ any: Any?) -> [String: Int] {
        var out: [String: Int] = [:]
        for (k, v) in (any as? [String: Any]) ?? [:] {
            if let n = JSONValue.int(v) { out[k.uppercased()] = n }
        }
        return out
    }

    /// Scene-level overrides for this pass: textures (non-null entries win), combos, constants.
    public mutating func apply(sceneJSON: [String: Any]) {
        if let t = sceneJSON["textures"] as? [Any] {
            for (i, v) in t.enumerated() {
                guard let name = v as? String else { continue }
                while textures.count <= i { textures.append(nil) }
                textures[i] = name
            }
        }
        for (k, v) in Self.intDict(sceneJSON["combos"]) { combos[k] = v }
        for (k, v) in (sceneJSON["constantshadervalues"] as? [String: Any]) ?? [:] { constants[k] = v }
    }
}

/// One pass of an effect: a material drawn into a target, or a command (`copy`).
public struct EffectPass {
    public var material: MaterialPass?
    public var command: String?
    /// Named render target to draw into; nil means the effect's next ping-pong buffer.
    public var target: String?
    public var source: String?
    /// Slot → "previous" (the effect's input) or a named render target.
    public var binds: [(name: String, index: Int)] = []
}

public struct EffectRenderTarget {
    public let name: String
    /// Divisor of the layer's size.
    public let scale: Int
    public let format: String
}

public struct EffectInstance {
    public let file: String
    public let name: String
    public let visible: Bool
    public let passes: [EffectPass]
    public let renderTargets: [EffectRenderTarget]
}

public struct Transform2D {
    public var origin = SIMD3<Float>.zero
    public var scale = SIMD3<Float>.one
    /// Radians; only z is used by 2D scenes.
    public var angles = SIMD3<Float>.zero

    init(_ object: [String: Any]) {
        origin = JSONValue.vec3(object["origin"], .zero)
        scale = JSONValue.vec3(object["scale"], .one)
        angles = JSONValue.vec3(object["angles"], .zero)
    }
}

public struct ImageLayer {
    public enum Kind: String {
        /// A texture (`models/*.json` → material).
        case image
        /// `models/util/fullscreenlayer.json`: effects over everything drawn so far.
        case fullscreen
        /// `models/util/composelayer.json`: effects over what is behind the layer's rectangle.
        case compose
        /// `models/util/solidlayer.json`: a flat colour.
        case solid
    }

    public let id: Int
    public let name: String
    public let kind: Kind
    public let visible: Bool
    public let transform: Transform2D
    public let size: SIMD2<Float>
    public let alpha: Float
    public let color: SIMD3<Float>
    public let brightness: Float
    public let material: MaterialPass?
    public let puppetPath: String?
    public let effects: [EffectInstance]
}

public struct ParticleObject {
    public let id: Int
    public let name: String
    public let file: String
    public let visible: Bool
    public let transform: Transform2D
    /// `instanceoverride`: count, rate, size, alpha, lifetime, speed, colorn.
    public let overrides: [String: Any]
}

public struct SoundObject {
    public let id: Int
    public let name: String
    public let files: [String]
}

public enum SceneObject {
    case image(ImageLayer)
    case particles(ParticleObject)
    case sound(SoundObject)
    case unknown(id: Int, name: String, keys: [String])
}

/// A scene item as far as S9 reads it: `project.json` → the scene JSON → objects, models, materials, effects.
public struct SceneDocument {
    public let item: ItemFiles
    public let sceneFile: String
    public let width: Float
    public let height: Float
    public let clearColor: SIMD3<Float>
    public let cameraParallax: Bool
    public let general: [String: Any]
    /// Back to front.
    public private(set) var objects: [SceneObject] = []
    /// Everything that failed to read, with the path.
    public private(set) var problems: [String] = []

    public var layers: [ImageLayer] {
        objects.compactMap { if case .image(let l) = $0 { l } else { nil } }
    }

    public init(folder: URL) throws {
        item = try ItemFiles(folder: folder)
        let project = try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("project.json"))) as? [String: Any]
        sceneFile = project?["file"] as? String ?? "scene.json"
        let scene = try item.json(sceneFile)
        general = scene["general"] as? [String: Any] ?? [:]
        let ortho = general["orthogonalprojection"] as? [String: Any]
        width = JSONValue.float(ortho?["width"], 1920)
        height = JSONValue.float(ortho?["height"], 1080)
        clearColor = JSONValue.vec3(general["clearcolor"], .zero)
        cameraParallax = JSONValue.bool(general["cameraparallax"], false)

        for object in scene["objects"] as? [[String: Any]] ?? [] {
            let id = JSONValue.int(object["id"]) ?? -1
            let name = object["name"] as? String ?? ""
            if let image = object["image"] as? String {
                do {
                    objects.append(.image(try layer(object, id: id, name: name, modelPath: image)))
                } catch {
                    problems.append("object \(id) \(name): \(error)")
                }
            } else if let file = object["particle"] as? String {
                objects.append(.particles(ParticleObject(
                    id: id, name: name, file: file, visible: JSONValue.bool(object["visible"], true),
                    transform: Transform2D(object), overrides: object["instanceoverride"] as? [String: Any] ?? [:])))
            } else if let files = object["sound"] as? [String] {
                objects.append(.sound(SoundObject(id: id, name: name, files: files)))
            } else {
                objects.append(.unknown(id: id, name: name, keys: object.keys.sorted()))
            }
        }
    }

    mutating func layer(_ object: [String: Any], id: Int, name: String, modelPath: String) throws -> ImageLayer {
        var kind = ImageLayer.Kind.image
        var material: MaterialPass?
        var puppet: String?
        switch modelPath {
        case "models/util/fullscreenlayer.json": kind = .fullscreen
        case "models/util/composelayer.json": kind = .compose
        case "models/util/solidlayer.json": kind = .solid
        default:
            let model = try item.json(modelPath)
            puppet = model["puppet"] as? String
            guard let path = model["material"] as? String else { throw ReadError("\(modelPath) has no material") }
            material = try firstPass(path)
        }
        let size = JSONValue.floats(object["size"]) ?? []
        var effects: [EffectInstance] = []
        for e in object["effects"] as? [[String: Any]] ?? [] {
            guard let file = e["file"] as? String else { continue }
            do {
                effects.append(try effect(e, file: file))
            } catch {
                problems.append("effect \(file) on \(name): \(error)")
            }
        }
        return ImageLayer(
            id: id, name: name, kind: kind,
            visible: JSONValue.bool(object["visible"], true),
            transform: Transform2D(object),
            size: SIMD2(size.first ?? 0, size.count > 1 ? size[1] : 0),
            alpha: JSONValue.float(object["alpha"], 1),
            color: JSONValue.vec3(object["color"], .one),
            brightness: JSONValue.float(object["brightness"], 1),
            material: material, puppetPath: puppet, effects: effects)
    }

    func firstPass(_ path: String) throws -> MaterialPass {
        let json = try item.json(path)
        guard let pass = (json["passes"] as? [[String: Any]])?.first else { throw ReadError("\(path) has no passes") }
        return MaterialPass(json: pass)
    }

    func effect(_ e: [String: Any], file: String) throws -> EffectInstance {
        let definition = try item.json(file)
        // The scene's passes line up with the effect's material passes; commands have none.
        let scenePasses = e["passes"] as? [[String: Any]] ?? []
        var passes: [EffectPass] = []
        var materialIndex = 0
        for p in definition["passes"] as? [[String: Any]] ?? [] {
            var pass = EffectPass()
            pass.command = p["command"] as? String
            pass.target = p["target"] as? String
            pass.source = p["source"] as? String
            pass.binds = (p["bind"] as? [[String: Any]] ?? []).compactMap { b in
                guard let n = b["name"] as? String, let i = JSONValue.int(b["index"]) else { return nil }
                return (n, i)
            }
            if let path = p["material"] as? String {
                var material = try firstPass(path)
                if materialIndex < scenePasses.count { material.apply(sceneJSON: scenePasses[materialIndex]) }
                materialIndex += 1
                pass.material = material
            }
            passes.append(pass)
        }
        let targets = (definition["fbos"] as? [[String: Any]] ?? []).map {
            EffectRenderTarget(name: $0["name"] as? String ?? "?", scale: JSONValue.int($0["scale"]) ?? 1,
                               format: $0["format"] as? String ?? "rgba8888")
        }
        let name = (file as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? file
        return EffectInstance(file: file, name: name, visible: JSONValue.bool(e["visible"], true), passes: passes,
                              renderTargets: targets)
    }

    /// `masks/foo` → `materials/masks/foo.tex`.
    public static func texturePath(_ name: String) -> String { "materials/\(name).tex" }

    /// The item's own copy of a shader stage (`shaders/<name>.vert|.frag`), if it carries one.
    public func itemShader(_ name: String, stage: String) -> String? {
        item.text("shaders/\(name).\(stage)")
    }
}
