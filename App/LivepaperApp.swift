import AppKit
import DesignSystem
import LivepaperCore
import SwiftUI

@main
struct LivepaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The developer menu, until the glass popover lands in M6 (docs/specs/M5-engine.md, "Developer menu").
        MenuBarExtra("Livepaper", systemImage: "play.rectangle.on.rectangle") {
            DeveloperMenu(session: delegate.session)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Starts the session at launch, and holds Quit until the stopped render state
/// is written, so that each display is left holding its poster (record 0003).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = DeveloperSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.launch()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await session.quit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
