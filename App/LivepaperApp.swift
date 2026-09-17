import DesignSystem
import LivepaperCore
import SwiftUI

@main
struct LivepaperApp: App {
    var body: some Scene {
        // Placeholder menu until the glass popover lands in M6 (docs/roadmap.md).
        MenuBarExtra("Livepaper", systemImage: "play.rectangle.on.rectangle") {
            Button("Quit Livepaper") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
