import CoreGraphics
import Foundation

// Prints "id x y w h" of the largest on-screen window owned by the app named in argv[1].
//
// With "--desktop [n]" it prints the desktop's wallpaper window instead, on the nth display
// from the left (default 1). That window belongs to WindowManager one level below the desktop
// level (macOS 27), so it is found by owner and level, which need no permission; capturing it
// needs Screen Recording, which is allowed for capture tooling on the developer's Mac and never
// for product code.
let arguments = Array(CommandLine.arguments.dropFirst())

func rect(of window: [String: Any]) -> CGRect? {
    guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
    return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if arguments.first == "--desktop" {
    let index = arguments.dropFirst().first.flatMap(Int.init) ?? 1
    let desktop = Int(CGWindowLevelForKey(.desktopWindow))
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let windows = list.compactMap { window -> (Int, CGRect)? in
        guard (window[kCGWindowOwnerName as String] as? String) == "WindowManager",
              let layer = window[kCGWindowLayer as String] as? Int, layer <= desktop,
              let id = window[kCGWindowNumber as String] as? Int,
              let frame = rect(of: window), frame.width > 0 else { return nil }
        return (id, frame)
    }
    // One wallpaper window per display: the largest at each origin.
    let perDisplay = Dictionary(grouping: windows) { "\($0.1.minX),\($0.1.minY)" }
        .compactMap { $0.value.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height } }
        .sorted { $0.1.minX < $1.1.minX }
    guard perDisplay.indices.contains(index - 1) else { fail("no wallpaper window for display \(index)") }
    let (id, frame) = perDisplay[index - 1]
    print(id, Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height))
    exit(0)
}

let name = arguments.first ?? "Livepaper Gallery"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, CGRect)?
for window in list where (window[kCGWindowOwnerName as String] as? String) == name {
    guard (window[kCGWindowLayer as String] as? Int) == 0,
          let frame = rect(of: window),
          let id = window[kCGWindowNumber as String] as? Int else { continue }
    if best == nil || frame.width * frame.height > best!.1.width * best!.1.height { best = (id, frame) }
}
guard let (id, frame) = best else { fail("no window for \(name)") }
print(id, Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height))
