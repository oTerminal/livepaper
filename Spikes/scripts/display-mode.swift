// Throwaway spike tool (S3): change one display's mode for this login session, to see what the wallpaper does.
//   swiftc scripts/display-mode.swift -o build/s3/display-mode && build/s3/display-mode <displayID> list | <width> <height> [hz]
import CoreGraphics
import Foundation
let id = CGDirectDisplayID(CommandLine.arguments[1])!
let modes = (CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode]) ?? []
if CommandLine.arguments[2] == "list" {
    let cur = CGDisplayCopyDisplayMode(id)
    print("current \(cur?.width ?? 0)x\(cur?.height ?? 0)@\(cur?.refreshRate ?? 0) px \(cur?.pixelWidth ?? 0)")
    for m in modes { print("\(m.width)x\(m.height)@\(m.refreshRate) px \(m.pixelWidth)x\(m.pixelHeight)") }
    exit(0)
}
let w = Int(CommandLine.arguments[2])!, h = Int(CommandLine.arguments[3])!
let hz = CommandLine.arguments.count > 4 ? Double(CommandLine.arguments[4])! : 60
guard let m = modes.filter({ $0.width == w && $0.height == h }).min(by: { abs($0.refreshRate - hz) < abs($1.refreshRate - hz) }) else { print("no such mode"); exit(1) }
var cfg: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&cfg)
CGConfigureDisplayWithDisplayMode(cfg, id, m, nil)
let r = CGCompleteDisplayConfiguration(cfg, .forSession)
print("set \(w)x\(h)@\(m.refreshRate): \(r == .success ? "ok" : "error \(r.rawValue)")")
