import CoreGraphics
import Foundation

// Prints "id x y w h" of the largest on-screen window owned by the app named in argv[1].
let name = CommandLine.arguments.dropFirst().first ?? "Livepaper Gallery"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, CGRect)?
for window in list where (window[kCGWindowOwnerName as String] as? String) == name {
    guard (window[kCGWindowLayer as String] as? Int) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          let id = window[kCGWindowNumber as String] as? Int else { continue }
    let rect = CGRect(x: bounds["X"]!, y: bounds["Y"]!, width: bounds["Width"]!, height: bounds["Height"]!)
    if best == nil || rect.width * rect.height > best!.1.width * best!.1.height { best = (id, rect) }
}
guard let (id, rect) = best else { FileHandle.standardError.write("no window for \(name)\n".data(using: .utf8)!); exit(1) }
print(id, Int(rect.minX), Int(rect.minY), Int(rect.width), Int(rect.height))
