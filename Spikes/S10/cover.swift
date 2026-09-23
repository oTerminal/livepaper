// S10's covering window: a borderless, opaque window at the normal level with the main display's
// frame, which the app's covered-display sensor counts as covering the desktop.
//
//     cover <seconds> [back|front]
//
// `back` (the default) orders it behind every other normal window, so it hides the desktop and
// nothing the user has open. It closes itself after <seconds>, or at once on a click (exit 2).
// Prints the wall-clock times it was shown and closed.
import AppKit

let arguments = CommandLine.arguments
let seconds = arguments.count > 1 ? Double(arguments[1]) ?? 30 : 30
let behind = arguments.count > 2 ? arguments[2] != "front" : true

func stamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: Date())
}

final class ClickToClose: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        print("clicked \(stamp())")
        fflush(stdout)
        exit(2)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.main else { exit(1) }
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .normal
window.isOpaque = true
window.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1)
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.isReleasedWhenClosed = false
let content = ClickToClose(frame: NSRect(origin: .zero, size: screen.frame.size))
let until = Date().addingTimeInterval(seconds)
let label = NSTextField(labelWithString: "Livepaper S10 energy check: this window covers the desktop until "
    + DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .medium) + ". Click to close it.")
label.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
label.font = NSFont.systemFont(ofSize: 15)
label.sizeToFit()
label.frame.origin = NSPoint(x: (screen.frame.width - label.frame.width) / 2, y: screen.frame.height / 2)
content.addSubview(label)
window.contentView = content
window.setFrame(screen.frame, display: true)
if behind { window.orderBack(nil) } else { window.orderFrontRegardless() }
print("shown \(stamp()) frame=\(screen.frame) behind=\(behind)")
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    window.orderOut(nil)
    print("closed \(stamp())")
    fflush(stdout)
    exit(0)
}
app.run()
