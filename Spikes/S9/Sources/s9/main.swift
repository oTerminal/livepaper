// s9: the S9 spike's command line.
//
//   s9 inventory <samples>                       read every scene: pkg, JSON, textures, puppets
//   s9 translate <samples>                       every program the scenes use: translate, Metal compile, link
//   s9 sweep <samples>                           every combo value of every item shader
//   s9 import <item> <manifest.json>             import step: translate the item's programs into a manifest
//   s9 render <item> <outdir> [WxH] [seconds] [noparticles] [noeffects]
//                                                import, load, then PNGs at 0, 1, 2 s and an MP4
import Foundation
import Metal
import SceneImport
import SceneItemFormat
import SceneShaderTranslation

let scratch = URL(fileURLWithPath: ProcessInfo.processInfo.environment["S9_WORK"] ?? NSTemporaryDirectory())
    .appendingPathComponent("s9-work")
let translator = ShaderTranslator(workDirectory: scratch.appendingPathComponent("translate"))
let device = MTLCreateSystemDefaultDevice()!

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: s9 inventory|translate|sweep|import|render …")
    exit(2)
}

func sceneFolders(_ root: URL) -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.sorted().map { root.appendingPathComponent($0) }.filter {
        guard let data = try? Data(contentsOf: $0.appendingPathComponent("project.json")),
              let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        // Botanical is a scene made from Wallpaper Engine's GIF template; its project has no "type".
        return (p["type"] as? String)?.lowercased() == "scene" || (p["file"] as? String)?.hasSuffix(".json") == true
    }
}

func title(_ folder: URL) -> String {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
          let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return folder.lastPathComponent }
    return (p["title"] as? String ?? "?").components(separatedBy: " |").first!
}

func parseSize(_ s: String) -> (Int, Int)? {
    let p = s.split(separator: "x").compactMap { Int($0) }
    return p.count == 2 ? (p[0], p[1]) : nil
}

do {
    switch args[1] {
    case "inventory":
        Inventory.run(root: URL(fileURLWithPath: args[2]))
    case "translate":
        TranslateTable.run(root: URL(fileURLWithPath: args[2]), translator: translator, device: device)
    case "sweep":
        TranslateTable.sweep(root: URL(fileURLWithPath: args[2]), translator: translator, device: device)
    case "import":
        let doc = try SceneDocument(folder: URL(fileURLWithPath: args[2]))
        let start = Date()
        let manifest = SceneImporter.translateShaders(of: doc, translator: translator)
        try manifest.write(to: URL(fileURLWithPath: args[3]))
        print(String(format: "%d programs for %d requests in %.1f s; %d failures", manifest.programs.count,
                     manifest.requests.count, Date().timeIntervalSince(start), manifest.failures.count))
        for (s, f) in manifest.failures.sorted(by: { $0.key < $1.key }) { print("  \(s): \(f)") }
    case "render":
        let folder = URL(fileURLWithPath: args[2])
        let out = URL(fileURLWithPath: args[3])
        let doc = try SceneDocument(folder: folder)
        let size = args.count > 4 ? parseSize(args[4]) : nil
        let seconds = args.count > 5 ? Double(args[5]) ?? 5 : 5
        let options = Set(args.dropFirst(6))
        // As the product would: the item's files in a library folder (APFS clones, no real copy), import
        // prepares it (writes the manifest there), load reads the folder.
        let library = out.appendingPathComponent("library").appendingPathComponent(folder.lastPathComponent)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
        where name == "project.json" || name.hasSuffix(".pkg") || name.hasPrefix("preview.") {
            let to = library.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: to.path) {
                try FileManager.default.copyItem(at: folder.appendingPathComponent(name), to: to)
            }
        }
        try SceneImporter.prepare(library, translator: translator)
        try Offscreen.render(folder: library, device: device,
                             width: size?.0 ?? Int(doc.width), height: size?.1 ?? Int(doc.height),
                             out: out, id: folder.lastPathComponent, videoSeconds: seconds,
                             particles: !options.contains("noparticles"), effects: !options.contains("noeffects"))
    default:
        print("unknown command \(args[1])")
        exit(2)
    }
} catch {
    print("error: \(error)")
    exit(1)
}
