import Foundation
import Metal
import SceneImport
import SceneItemFormat
import SceneItemRenderer
import SceneShaderTranslation

/// Every shader program the scenes use, with the combos each scene sets, through import (preprocess →
/// glslang → SPIRV-Cross) and load (Metal compile → pipeline link). Prints a Markdown table.
enum TranslateTable {
    struct Row {
        var shader: String
        var origin: String
        var defines: String
        var scenes: [String]
        var result: String
        var failure: String
    }

    static func check(_ request: ProgramRequest, doc: SceneDocument, translator: ShaderTranslator,
                      device: any MTLDevice, manifest: inout ProgramManifest) -> (result: String, failure: String) {
        if let failure = SceneImporter.add(request, doc: doc, translator: translator, to: &manifest) {
            return (failure.hasPrefix("no source") ? "– | – | –" : "**no** | – | –", failure)
        }
        guard let entry = manifest.entry(for: request) else { return ("?", "") }
        switch ProgramCheck.run(entry, device: device) {
        case .ok: return ("yes | yes | yes", "")
        case .compileFailed(let e): return ("yes | **no** | –", "Metal compile: \(e)")
        case .linkFailed(let e): return ("yes | yes | **no**", "pipeline: \(e)")
        }
    }

    static func run(root: URL, translator: ShaderTranslator, device: any MTLDevice) {
        var rows: [String: Row] = [:]
        var order: [String] = []
        for folder in sceneFolders(root) {
            guard let doc = try? SceneDocument(folder: folder) else { continue }
            let scene = title(folder)
            var manifest = ProgramManifest()
            for request in ProgramRequest.all(in: doc) {
                let src = SceneImporter.sources(for: request.shader, in: doc)
                let ann = src.map { ShaderAnnotations(sources: [$0.vertex, $0.fragment]) } ?? ShaderAnnotations()
                let defines = ann.defines(explicit: request.combos, boundSlots: request.boundSlots)
                let shown = defines.filter { $0.1 != 0 }.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
                let key = "\(request.shader)|\(src?.origin ?? "")|\((src?.vertex ?? "") + (src?.fragment ?? ""))|\(shown)"
                if var r = rows[key] {
                    if !r.scenes.contains(scene) { r.scenes.append(scene) }
                    rows[key] = r
                    continue
                }
                let (result, failure) = check(request, doc: doc, translator: translator, device: device, manifest: &manifest)
                rows[key] = Row(shader: request.shader, origin: src?.origin ?? "missing", defines: shown.isEmpty ? "–" : shown,
                                scenes: [scene], result: result, failure: failure.replacingOccurrences(of: "|", with: "\\|"))
                order.append(key)
            }
        }
        print("| Shader | Source | Combos set | SPIR-V + MSL | Metal compiles | Pipeline links | Scenes | Why it failed |")
        print("|---|---|---|---|---|---|---|---|")
        for key in order {
            let r = rows[key]!
            print("| \(r.shader) | \(r.origin) | \(r.defines) | \(r.result) | \(r.scenes.joined(separator: ", ")) | \(r.failure) |")
        }
        let ok = order.filter { rows[$0]!.result == "yes | yes | yes" }.count
        print("\n\(ok) of \(order.count) programs translate, compile and link.")
    }

    /// Every item shader, every value of every combo it declares (others at default), with its
    /// texture-switched combos on and off: the variants the scenes did not happen to use.
    static func sweep(root: URL, translator: ShaderTranslator, device: any MTLDevice) {
        var seen = Set<String>()
        var total = 0, ok = 0
        var failures: [String] = []
        for folder in sceneFolders(root) {
            guard let doc = try? SceneDocument(folder: folder), let pkg = doc.item.pkg else { continue }
            var manifest = ProgramManifest()
            for path in pkg.order where path.hasPrefix("shaders/") && path.hasSuffix(".frag") {
                let name = String(path.dropFirst("shaders/".count).dropLast(".frag".count))
                guard let src = SceneImporter.sources(for: name, in: doc),
                      seen.insert(src.vertex + src.fragment).inserted else { continue }
                let ann = ShaderAnnotations(sources: [src.vertex, src.fragment])
                var variants: [[String: Int]] = [[:]]
                for c in ann.combos {
                    let values: [Int]
                    if let opts = c.json["options"] as? [String: Any] {
                        values = opts.values.compactMap { ($0 as? NSNumber)?.intValue }.sorted()
                    } else if c.json["type"] as? String == "imageblending" {
                        values = Array(0...25)
                    } else {
                        values = [0, 1]
                    }
                    for v in values where v != c.defaultValue { variants.append([c.name: v]) }
                }
                let texSlots = Set(ann.textureCombos.map(\.slot))
                for combos in variants {
                    let slotSets: [Set<Int>] = texSlots.isEmpty ? [[0]] : (combos.isEmpty ? [[0], texSlots.union([0])] : [texSlots.union([0])])
                    for slots in slotSets {
                        total += 1
                        let (result, failure) = check(ProgramRequest(shader: name, combos: combos, boundSlots: slots),
                                                      doc: doc, translator: translator, device: device, manifest: &manifest)
                        if result == "yes | yes | yes" { ok += 1 } else { failures.append("\(name) \(combos) \(slots.sorted()): \(failure)") }
                    }
                }
            }
        }
        print("\(ok) of \(total) variants translate, compile and link.")
        for f in failures { print("  - \(f)") }
    }
}
