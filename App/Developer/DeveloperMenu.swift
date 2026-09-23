import LivepaperCore
import SwiftUI

/// The menu bar item's menu until M6's popover replaces it. "Log Playback
/// Metrics" stays after that; M8's soak and M10's checklist switch it on.
struct DeveloperMenu: View {
    let session: DeveloperSession

    var body: some View {
        Text("Wallpaper service: \(session.status.words)")
        Divider()
        Button("Import Video…") { session.importVideos() }
            .disabled(!session.canImport)
        setWallpaper
        presentation
        volume
        Button("Pause All") { session.pauseAll() }
        Button("Resume") { session.resume() }
        Divider()
        Button("Restart Wallpaper Service") { session.restartWallpaperService() }
        Button("Run Watchdog Check") { session.runWatchdogCheck() }
        Toggle("Log Playback Metrics", isOn: playbackMetrics)
        Menu("Checks") {
            Button("Crossfade Back and Forth ×6") { session.run(.crossfades) }
            Button("50 Switches in 10 s") { session.run(.switches) }
        }
        .disabled(!session.canRunCheck)
        Divider()
        Button("Quit Livepaper") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var setWallpaper: some View {
        Menu("Set Wallpaper") {
            if !session.isLibraryReadable {
                Text("The library could not be read")
            } else if session.library.wallpapers.isEmpty {
                Text("No wallpapers in the library")
            }
            ForEach(session.library.wallpapers) { wallpaper in
                Menu(wallpaper.name) {
                    Button("On All Displays") { session.setOnAllDisplays(wallpaper) }
                    ForEach(session.displays) { display in
                        Button("On \(display.name)") { session.set(wallpaper, on: [display.identity]) }
                    }
                    Divider()
                    Button("In a Preview Window") { session.preview.open(wallpaper, in: session.location) }
                }
            }
        }
    }

    private var presentation: some View {
        Menu("Presentation") {
            Button("Fill") { session.setFit(.fill) }
            Button("Fit") { session.setFit(.fit) }
            Button("Stretch") { session.setFit(.stretch) }
            Divider()
            Button("Focal Point: Centre") { session.setFocalPoint(Point(x: 0.5, y: 0.5)) }
            Button("Focal Point: Off Centre") { session.setFocalPoint(Point(x: 0.2, y: 0.3)) }
        }
    }

    private var volume: some View {
        Menu("Volume") {
            Button("0 (Default)") { session.setVolume(0) }
            Button("0.5") { session.setVolume(0.5) }
        }
    }

    private var playbackMetrics: Binding<Bool> {
        Binding(get: { session.isPlaybackMetricsOn }, set: { session.setPlaybackMetrics($0) })
    }
}

extension RenderHostStatus {
    /// The status in words, for the menu's status line.
    fileprivate var words: String {
        switch self {
        case .stopped: "Stopped"
        case .connecting: "Connecting…"
        case .notSelected: "Not selected in System Settings"
        case .live: "Live"
        case .recovering(let level): "Recovering (\(level.words))"
        case .unavailable: "Unavailable on this macOS"
        }
    }
}

extension RecoveryLevel {
    fileprivate var words: String {
        switch self {
        case .flush: "flush"
        case .rebuildSurface: "rebuild surface"
        case .rebuildPipeline: "rebuild pipeline"
        case .restartAgent: "restart WallpaperAgent"
        }
    }
}
