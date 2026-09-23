import AppKit
import LivepaperCore
import LivepaperPlayback
import LivepaperSystem
import os

/// A plain window with one `PreviewPlayer`, for the S2p check: the engine's
/// loop in a window, with the playback-metrics probe on so that the log gets
/// the metrics line every 20 loops. It floats, because the window server
/// throttles a covered window and the check needs one that stays visible.
final class PreviewWindow {
    private var window: NSWindow?
    private let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: "preview")

    func open(_ wallpaper: Wallpaper, in location: LibraryLocation) {
        window?.close()
        let player = PreviewPlayer(logger: logger, presentation: wallpaper.presentation)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = wallpaper.name
        window.contentView = player
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        self.window = window

        player.setMetricsProbe(true)
        player.play(location.url(for: wallpaper.optimisedCopy))
        logger.notice("preview: \(wallpaper.id.description, privacy: .public) opened in a window")
    }
}
