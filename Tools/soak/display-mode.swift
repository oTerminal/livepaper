import ColorSync
import CoreGraphics
import Foundation

// usage: swift Tools/soak/display-mode.swift list
//        swift Tools/soak/display-mode.swift set <display ID or UUID> <width> <height> [hz]
//
// Changes a display's mode for the hot-plug loop's row "1920x1080 to 1280x1024 and back"
// (docs/specs/M8-hardening.md). `list` prints every online display: its CGDirectDisplayID, the UUID
// Livepaper knows it by (the one `livepaper status` lists), its current mode and the modes it
// offers for the desktop. `set` takes the mode of that size whose refresh rate is nearest the one
// given, by default the current mode's, and applies it for this login session only (`.forSession`):
// logging out puts the display back as System Settings has it, and so does `set` with the old size.
// Sizes are in points, as System Settings shows them; a Retina mode lists its pixels beside them.
// It prints "ok" and the mode, or the CGError.
let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
    usage: swift Tools/soak/display-mode.swift list
           swift Tools/soak/display-mode.swift set <display ID or UUID> <width> <height> [hz]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Every display that is drawing now, mirrored ones included.
func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
    return Array(displays.prefix(Int(count)))
}

/// The display's UUID, read as the app's display sensor reads it (`DisplaySensor.swift`).
func uuid(of display: CGDirectDisplayID) -> String? {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}

/// The modes a desktop can use on the display, Retina ones included: without the option, CoreGraphics
/// leaves them out, the built-in display's current mode among them.
func modes(of display: CGDirectDisplayID) -> [CGDisplayMode] {
    let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    let all = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
    return all.filter { $0.isUsableForDesktopGUI() }
}

/// "1920x1080", or for a Retina mode "1280x800 (2560x1600 px)".
func size(of mode: CGDisplayMode) -> String {
    let pixels = mode.pixelWidth == mode.width ? "" : " (\(mode.pixelWidth)x\(mode.pixelHeight) px)"
    return "\(mode.width)x\(mode.height)\(pixels)"
}

/// Some built-in displays give no rate.
func rate(of mode: CGDisplayMode) -> String {
    mode.refreshRate > 0 ? String(format: "%g", mode.refreshRate) : "?"
}

func describe(_ mode: CGDisplayMode) -> String {
    "\(size(of: mode)) @ \(rate(of: mode)) Hz"
}

/// The pixels per point of a mode: 2 for a Retina mode, 1 for most external displays.
func scale(of mode: CGDisplayMode) -> Double {
    Double(mode.pixelWidth) / Double(max(mode.width, 1))
}

func listDisplays() {
    let displays = onlineDisplays()
    guard !displays.isEmpty else { fail("no online display") }
    for display in displays {
        let kind = CGDisplayIsBuiltin(display) != 0 ? "built-in" : "external"
        let main = CGDisplayIsMain(display) != 0 ? ", main" : ""
        print("display \(display)  \(uuid(of: display) ?? "no UUID")  \(kind)\(main)")
        if let current = CGDisplayCopyDisplayMode(display) {
            print("  current  \(describe(current))")
        }
        // One line per size, largest first, with its rates; a size and rate can be offered more
        // than once, in other pixel encodings.
        var sizes: [String] = []
        var rates: [String: [String]] = [:]
        let sorted = modes(of: display).sorted {
            ($0.width, $0.height, scale(of: $0), $0.refreshRate) > ($1.width, $1.height, scale(of: $1), $1.refreshRate)
        }
        for mode in sorted {
            let key = size(of: mode)
            if rates[key] == nil { sizes.append(key) }
            if !rates[key, default: []].contains(rate(of: mode)) { rates[key, default: []].append(rate(of: mode)) }
        }
        for key in sizes {
            print("           \(key) @ \(rates[key, default: []].joined(separator: ", ")) Hz")
        }
    }
}

/// A display named by its CGDirectDisplayID or its UUID, among the online ones.
func display(named name: String) -> CGDirectDisplayID {
    let displays = onlineDisplays()
    if let id = CGDirectDisplayID(name), displays.contains(id) { return id }
    if let match = displays.first(where: { uuid(of: $0)?.caseInsensitiveCompare(name) == .orderedSame }) { return match }
    fail("no online display \(name): `list` shows them")
}

/// Applies the mode of that size nearest the rate, and at a tie the current mode's pixels per point.
func setMode(on name: String, width: Int, height: Int, rate: Double?) {
    let display = display(named: name)
    let current = CGDisplayCopyDisplayMode(display)
    let wantedRate = rate ?? current?.refreshRate ?? 0
    let wantedScale = current.map(scale) ?? 1
    func distance(_ mode: CGDisplayMode) -> (Double, Double) {
        (abs(mode.refreshRate - wantedRate), abs(scale(of: mode) - wantedScale))
    }
    let sized = modes(of: display).filter { $0.width == width && $0.height == height }
    guard let mode = sized.min(by: { distance($0) < distance($1) }) else {
        fail("display \(display) has no \(width)x\(height) mode: `list` shows its modes")
    }
    var config: CGDisplayConfigRef?
    var result = CGBeginDisplayConfiguration(&config)
    if result == .success {
        result = CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        if result == .success {
            result = CGCompleteDisplayConfiguration(config, .forSession)
        } else {
            CGCancelDisplayConfiguration(config)
        }
    }
    guard result == .success else { fail("CGError \(result.rawValue) setting display \(display) to \(describe(mode))") }
    print("ok: display \(display) is \(describe(mode))")
}

switch arguments.first {
case "list" where arguments.count == 1:
    listDisplays()
case "set" where (4...5).contains(arguments.count):
    guard let width = Int(arguments[2]), let height = Int(arguments[3]) else { fail(usage) }
    var rate: Double?
    if arguments.count == 5 {
        guard let hz = Double(arguments[4]) else { fail(usage) }
        rate = hz
    }
    setMode(on: arguments[1], width: width, height: height, rate: rate)
default:
    fail(usage)
}
