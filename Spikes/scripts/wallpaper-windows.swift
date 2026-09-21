// Throwaway spike tool (S3). Window names need the Screen Recording permission.
// Prints "<windowID> <x> <y> <w> <h> <onscreen>" for every WindowManager "Wallpaper" window.
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowName as String] as? String) == "Wallpaper" {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print(w[kCGWindowNumber as String] ?? 0, b["X"] ?? 0, b["Y"] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0, w[kCGWindowIsOnscreen as String] ?? 0)
}
