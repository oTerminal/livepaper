import Foundation
import Metal
import SceneImport
import SceneItemFormat
import simd

extension SceneRenderer {
    /// A layer's effect chain. Each effect's passes ping-pong between two layer-sized targets unless a pass
    /// names a target (`fbos`, sized by a divisor); `bind` puts "previous" or a named target in a slot;
    /// `copy` blits one target to another. Targets persist across frames, so effects with history
    /// (motion blur) keep it. Returns the last output.
    func runEffects(_ cb: any MTLCommandBuffer, _ effects: [EffectInstance], layerKey: String, input: any MTLTexture,
                    scene: any MTLTexture, time: Float) -> any MTLTexture {
        let w = input.width, h = input.height
        let a = input
        let b = target("\(layerKey).b", w, h)
        var current = input
        for (ei, effect) in effects.enumerated() {
            var named: [String: any MTLTexture] = [:]
            for t in effect.renderTargets {
                let s = max(1, t.scale)
                named[t.name] = target("\(layerKey).e\(ei).\(t.name)", w / s, h / s)
            }
            func resolve(_ name: String) -> (any MTLTexture)? {
                if let t = named[name] { return t }
                // Scene passes name a unique target with a suffix: _rt_FullCompoBuffer1_61_69.
                if let t = named.first(where: { name.hasPrefix($0.key + "_") })?.value { return t }
                // The whole frame so far.
                if name == "_rt_FullFrameBuffer" { return scene }
                // _rt_imageLayerComposite_<object id>_a: that layer's own buffer.
                if name.hasPrefix("_rt_imageLayerComposite_") {
                    let parts = name.dropFirst("_rt_imageLayerComposite_".count).split(separator: "_")
                    if parts.count == 2 { return targets["layer\(parts[0]).\(parts[1])"] }
                }
                return nil
            }
            for pass in effect.passes {
                if pass.command == "copy" {
                    if let s = pass.source.flatMap(resolve), let t = pass.target.flatMap(resolve) { copy(cb, from: s, to: t) }
                    continue
                }
                guard let material = pass.material else { continue }
                // Slots: the material's textures, then binds, then the input in slot 0.
                var slots: [Int: Bound] = [:]
                for (i, name) in material.textures.enumerated() {
                    guard let name else { continue }
                    if name.hasPrefix("_rt_") {
                        if let t = resolve(name) { slots[i] = bound(target: t) } else { note("render target \(name) not found") }
                    } else if let g = textures.texture(named: name) {
                        slots[i] = bound(g, time: time)
                    }
                }
                for bind in pass.binds {
                    if bind.name == "previous" {
                        slots[bind.index] = bound(target: current)
                    } else if let t = resolve(bind.name) {
                        slots[bind.index] = bound(target: t)
                    }
                }
                if slots[0] == nil { slots[0] = bound(target: current) }
                let request = ProgramRequest(material: material,
                                             boundSlots: ProgramRequest.boundSlots(of: material, binds: pass.binds, item: document.item))
                guard let program = programs.program(for: request) else {
                    note("no program for \(request.signature)")
                    continue
                }
                // Samplers with a declared default ("util/white") get it when nothing else is bound.
                for (slotText, name) in program.entry.samplerDefaults {
                    guard let slot = Int(slotText), slots[slot] == nil else { continue }
                    if name.hasPrefix("_rt_") {
                        if let t = resolve(name) { slots[slot] = bound(target: t) }
                    } else if let g = textures.texture(named: name) {
                        slots[slot] = bound(g, time: time)
                    }
                }
                let out: any MTLTexture
                if let t = pass.target {
                    guard let r = resolve(t) else { note("render target \(t) not declared"); continue }
                    out = r
                } else {
                    out = current === a ? b : a
                }
                drawMaterial(cb, program, material: material, blending: Blending(material.blending), into: out, clear: true,
                             mvp: matrix_identity_float4x4, slots: slots, extra: [:], time: time)
                if pass.target == nil { current = out }
            }
        }
        return current
    }
}
