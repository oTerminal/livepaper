import CoreGraphics
import Foundation

// Prints "id x y w h" of the largest on-screen window owned by the app named in argv[1] (or, when
// argv[1] is a number, by that process ID: two copies of an app can run at once), at the
// window layer in argv[2] (default 0, a normal window). Livepaper's menu-bar popover is a panel at
// the pop-up menu level, layer 101: `winid Livepaper 101`. Above layer 0 a window that is off
// screen counts when none is on screen: the popover's panel keeps its id while it is closed, so
// a recording can start before it opens.
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
guard let layer = arguments.count > 1 ? Int(arguments[1]) : 0 else { fail("the layer is a number, such as 0 or 101") }
let list = CGWindowListCopyWindowInfo([layer == 0 ? .optionOnScreenOnly : .optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, CGRect, Bool)?
let pid = Int(name)
func isOwned(_ window: [String: Any]) -> Bool {
    if let pid { return (window[kCGWindowOwnerPID as String] as? Int) == pid }
    return (window[kCGWindowOwnerName as String] as? String) == name
}
for window in list where isOwned(window) {
    guard (window[kCGWindowLayer as String] as? Int) == layer,
          let frame = rect(of: window),
          let id = window[kCGWindowNumber as String] as? Int else { continue }
    let isOnScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
    let isBetter = best.map { best in
        isOnScreen != best.2 ? isOnScreen : frame.width * frame.height > best.1.width * best.1.height
    } ?? true
    if isBetter { best = (id, frame, isOnScreen) }
}
guard let (id, frame, _) = best else { fail("no window for \(name) at layer \(layer)") }
print(id, Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height))
