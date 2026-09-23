import Foundation
import SceneItemFormat

/// Reads every file of every scene and reports what parsed, what did not, and what the scene refers to
/// that the item does not carry.
enum Inventory {
    static func run(root: URL) {
        for folder in sceneFolders(root) {
            print("## \(folder.lastPathComponent) \(title(folder))")
            let doc: SceneDocument
            do { doc = try SceneDocument(folder: folder) } catch {
                print("  FAILED to read scene: \(error)")
                continue
            }
            guard let pkg = doc.item.pkg else { print("  no pkg"); continue }
            var kinds: [String: Int] = [:]
            var failures: [String] = doc.problems
            var payloads: [String: Int] = [:]
            var jsonCount = 0
            var textureNames = Set<String>()
            var shaderNames = Set<String>()
            let start = Date()
            for path in pkg.order {
                let ext = (path as NSString).pathExtension
                kinds[ext, default: 0] += 1
                let data = pkg.file(path)!
                switch ext {
                case "json":
                    do {
                        collect(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                                textures: &textureNames, shaders: &shaderNames)
                        jsonCount += 1
                        if path.hasPrefix("particles/") { _ = try ParticleDefinition(item: doc.item, file: path) }
                    } catch { failures.append("\(path): \(error)") }
                case "tex":
                    do {
                        let tex = try TexFile(data: data)
                        var label = tex.payloadKind == "raw" ? "raw \(tex.format.map { "\($0)" } ?? "format \(tex.formatCode)")" : tex.payloadKind
                        label += " (\(tex.containerVersion))"
                        if tex.isAnimated { label += " animated, \(tex.frames.count) frames" }
                        if tex.images.count > 1 { label += " over \(tex.images.count) images" }
                        payloads[label, default: 0] += 1
                        if !tex.isVideo {
                            for i in 0..<tex.images.count { _ = try tex.pixels(image: i, mip: 0) }
                        }
                    } catch { failures.append("\(path): \(error)") }
                case "mdl":
                    do {
                        let m = try PuppetModel(data: data)
                        let a = m.animations.map { "\($0.name) (\($0.mode), \($0.length) frames at \($0.fps) fps)" }
                        print("  puppet \(path): \(m.vertices.count) vertices, \(m.indices.count / 3) triangles in \(m.parts.count) parts, " +
                              "\(m.bones.count) bones, animations: \(a.joined(separator: ", "))")
                    } catch { failures.append("\(path): \(error)") }
                default: break
                }
            }
            let decode = Date().timeIntervalSince(start)
            print("  pkg \(pkg.version), \(pkg.order.count) files: " + kinds.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
            print("  JSON parsed: \(jsonCount); every texture decoded (\(String(format: "%.1f", decode)) s)")
            print("  texture payloads: " + payloads.sorted { $0.key < $1.key }.map { "\($0.value)× \($0.key)" }.joined(separator: ", "))
            var counts: [String: Int] = [:]
            for o in doc.objects {
                switch o {
                case .image(let l): counts["\(l.kind.rawValue) layer\(l.visible ? "" : " (hidden)")", default: 0] += 1
                case .particles: counts["particle system", default: 0] += 1
                case .sound: counts["sound", default: 0] += 1
                case .unknown: counts["unknown", default: 0] += 1
                }
            }
            print("  scene \(doc.sceneFile) \(Int(doc.width))x\(Int(doc.height)): " + counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
            print("  effects: \(Set(doc.layers.flatMap { $0.effects.map(\.name) }).sorted().joined(separator: ", "))")
            let missing = textureNames.filter { !$0.hasPrefix("_rt_") && !doc.item.contains(SceneDocument.texturePath($0)) }.sorted()
            print("  textures not in the item: \(missing.isEmpty ? "none" : missing.joined(separator: ", "))")
            let missingShaders = shaderNames.filter { doc.itemShader($0, stage: "frag") == nil }.sorted()
            print("  shaders not in the item: \(missingShaders.joined(separator: ", "))")
            print("  failures: \(failures.isEmpty ? "none" : "")")
            for f in failures { print("    - \(f)") }
        }
    }

    static func collect(_ obj: Any, textures: inout Set<String>, shaders: inout Set<String>) {
        if let d = obj as? [String: Any] {
            if let t = d["textures"] as? [Any] { for case let s as String in t { textures.insert(s) } }
            if let s = d["shader"] as? String { shaders.insert(s) }
            for (_, v) in d { collect(v, textures: &textures, shaders: &shaders) }
        } else if let a = obj as? [Any] {
            for v in a { collect(v, textures: &textures, shaders: &shaders) }
        }
    }
}
