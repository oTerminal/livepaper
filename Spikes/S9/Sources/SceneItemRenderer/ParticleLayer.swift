import Foundation
import Metal
import SceneImport
import SceneItemFormat
import simd

/// A particle object: its system, children that live beside it, and children spawned where its particles die.
final class ParticleLayer {
    struct Part {
        let system: ParticleSystem
        let material: MaterialPass
        /// Spawned in bursts where the parent's particles die.
        let onDeathOf: Int?
        let offset: SIMD3<Float>
    }

    private(set) var parts: [Part] = []

    /// The file and its children, recursively.
    static func definitions(_ file: String, item: ItemFiles) -> [ParticleDefinition] {
        var out: [ParticleDefinition] = []
        var queue = [file]
        var seen = Set<String>()
        while let f = queue.popLast() {
            guard seen.insert(f).inserted, let def = try? ParticleDefinition(item: item, file: f) else { continue }
            out.append(def)
            queue += def.children.map(\.file)
        }
        return out
    }

    static func material(_ def: ParticleDefinition, item: ItemFiles) -> MaterialPass? {
        guard let json = try? item.json(def.materialPath), let pass = (json["passes"] as? [[String: Any]])?.first else { return nil }
        return MaterialPass(json: pass)
    }

    init(_ object: ParticleObject, item: ItemFiles) throws {
        let root = try ParticleDefinition(item: item, file: object.file)
        guard let material = Self.material(root, item: item) else { throw ReadError("no material for \(object.file)") }
        let seed = UInt64(truncatingIfNeeded: object.id &* 7919 &+ 17)
        parts.append(Part(system: ParticleSystem(root, overrides: object.overrides, seed: seed), material: material,
                          onDeathOf: nil, offset: .zero))
        for (i, child) in root.children.enumerated() {
            guard let def = try? ParticleDefinition(item: item, file: child.file), let m = Self.material(def, item: item) else { continue }
            let event = child.type == "eventspawn"
            let system = ParticleSystem(def, overrides: event ? [:] : object.overrides, scale: child.scale.x,
                                        maxCount: child.maxCount, emits: !event, seed: seed &+ UInt64(i + 1))
            parts.append(Part(system: system, material: m, onDeathOf: event ? 0 : nil, offset: child.origin))
        }
    }

    var unsupported: [String] { parts.flatMap(\.system.unsupported) }

    func advance(to time: Float) {
        let bursts = parts.enumerated().filter { $0.element.onDeathOf == 0 }.map(\.element)
        parts[0].system.advance(to: time) { parent in
            for part in bursts {
                for position in parent.deaths {
                    for _ in 0..<min(5, part.system.def.maxCount) { part.system.spawn(at: position) }
                }
            }
        }
        for part in parts.dropFirst() { part.system.advance(to: time) }
    }
}

extension SceneRenderer {
    func drawParticles(_ cb: any MTLCommandBuffer, _ object: ParticleObject, index: Int, time: Float, into scene: any MTLTexture) {
        guard let layer = particleLayers[index] else { return }
        layer.advance(to: time)
        for part in layer.parts {
            let verts = part.system.vertices()
            guard !verts.isEmpty, let buffer = device.makeBuffer(bytes: verts, length: verts.count * 4) else { continue }
            let texture = (part.material.textures.first ?? nil).flatMap { textures.texture(named: $0) } ?? textures.white
            let request = ProgramRequest(material: part.material, boundSlots: [0])
            guard let program = programs.program(for: request) else {
                note("no program for \(request.signature)")
                continue
            }
            var t = object.transform
            t.origin += part.offset
            let mvp = modelViewProjection(t, halfSize: SIMD2(1, 1))
            drawMaterial(cb, program, material: part.material, blending: Blending(part.material.blending), into: scene,
                         clear: false, mvp: mvp, slots: [0: bound(texture, time: time)], extra: [:], time: time,
                         mesh: Mesh(vertices: buffer, vertexCount: verts.count / 9, indices: nil))
        }
    }
}
