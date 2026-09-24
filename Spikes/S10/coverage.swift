// Prints the fraction of the main display that on-screen normal-level windows cover (0 to 1),
// sampled on a 160x100 grid. Window bounds, levels and owners need no permission; names are not read.
import CoreGraphics
import Foundation

let display = CGDisplayBounds(CGMainDisplayID())
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let rects: [CGRect] = list.compactMap { window in
    guard (window[kCGWindowLayer as String] as? Int) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.5 else { return nil }
    return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
}
var covered = 0
let columns = 160, rows = 100
for row in 0 ..< rows {
    for column in 0 ..< columns {
        let point = CGPoint(
            x: display.minX + (Double(column) + 0.5) * display.width / Double(columns),
            y: display.minY + (Double(row) + 0.5) * display.height / Double(rows)
        )
        if rects.contains(where: { $0.contains(point) }) { covered += 1 }
    }
}
print(String(format: "%.2f", Double(covered) / Double(columns * rows)))
