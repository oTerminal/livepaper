import Foundation
import SceneItemFormat

/// One shader program the renderer will ask for: a shader name, the combos the material and scene set, and
/// which texture slots have something bound (that switches combos such as MASK). The importer translates
/// every request of a scene; the renderer looks them up by `signature`, so both sides must build requests
/// with the rules here.
public struct ProgramRequest: Hashable, Sendable {
    public let shader: String
    public let combos: [String: Int]
    public let boundSlots: Set<Int>

    public init(shader: String, combos: [String: Int], boundSlots: Set<Int>) {
        self.shader = shader
        self.combos = combos
        self.boundSlots = boundSlots
    }

    public init(material: MaterialPass, boundSlots: Set<Int>) {
        self.init(shader: material.shader, combos: material.combos, boundSlots: boundSlots)
    }

    public var signature: String {
        let c = combos.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return "\(shader)|\(c)|\(boundSlots.sorted().map(String.init).joined(separator: ","))"
    }

    /// Slots of an effect pass that will have a texture: slot 0 (the input), textures the item carries,
    /// render targets (`_rt_*`) and `bind` entries.
    public static func boundSlots(of material: MaterialPass, binds: [(name: String, index: Int)], item: ItemFiles) -> Set<Int> {
        var slots: Set<Int> = [0]
        for (i, name) in material.textures.enumerated() {
            guard let name else { continue }
            if name.hasPrefix("_rt_") || item.contains(SceneDocument.texturePath(name)) { slots.insert(i) }
        }
        for b in binds { slots.insert(b.index) }
        return slots
    }

    /// Everything a scene will draw with.
    public static func all(in doc: SceneDocument) -> [ProgramRequest] {
        var out: [ProgramRequest] = []
        func add(_ r: ProgramRequest) { if !out.contains(r) { out.append(r) } }
        for object in doc.objects {
            switch object {
            case .image(let layer):
                if let m = layer.material {
                    var combos = m.combos
                    if layer.puppetPath != nil { combos["SKINNING"] = 1 }
                    add(ProgramRequest(shader: m.shader, combos: combos, boundSlots: [0]))
                }
                if layer.kind == .solid { add(ProgramRequest(shader: "genericimage2", combos: [:], boundSlots: [0])) }
                for e in layer.effects {
                    for pass in e.passes {
                        guard let m = pass.material else { continue }
                        add(ProgramRequest(material: m, boundSlots: boundSlots(of: m, binds: pass.binds, item: doc.item)))
                    }
                }
            case .particles(let p):
                var files = [p.file]
                var seen = Set<String>()
                while let file = files.popLast() {
                    guard seen.insert(file).inserted, let def = try? ParticleDefinition(item: doc.item, file: file),
                          let json = try? doc.item.json(def.materialPath),
                          let pass = (json["passes"] as? [[String: Any]])?.first else { continue }
                    add(ProgramRequest(material: MaterialPass(json: pass), boundSlots: [0]))
                    files += def.children.map(\.file)
                }
            case .sound, .unknown:
                break
            }
        }
        return out
    }
}
