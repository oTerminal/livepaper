import AppKit
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import LivepaperTestSupport

/// What the model runs on: the real render host, stores, importer and sensors,
/// or the fakes (`Fakes`). Nothing else differs between the two runs.
struct AppServices {
    var isFakes: Bool
    var host: any RenderHost
    var libraryStore: any LibraryStore
    var appStateStore: any AppStateStore
    var art: WallpaperArt.Source
    /// The login item, the hotkeys and leaving: `FakeSystemServices` until M7.
    var systemServices: any SystemServices
    /// Clears what an import that was killed left behind; runs at launch, before any import.
    var sweep: () throws -> [URL]
    /// The render state the last run wrote, so that the generation carries on.
    /// Nil when there is none; throws when it cannot be read or trusted, which
    /// the model logs before starting from none.
    var lastRenderState: () throws -> RenderState?
    /// Made once, at launch, on the model: the one writer of the library.
    var makeImporter: (any ImportLibrary) -> any ImportRunning
    /// Prepares again, one at a time and off the main actor, the scenes whose
    /// programs are missing or were written by an older translator
    /// (`ScenePreparation.refresh`); `log` hears each outcome. Runs at launch,
    /// after the sweep. Nothing in the fakes run.
    var prepareScenes: (
        _ wallpapers: [Wallpaper], _ log: @escaping @Sendable (Wallpaper, ScenePreparation.Outcome) async -> Void
    ) async -> Void
    /// The sensors behind the pause rules and the connected displays.
    var makeSensing: (_ rules: PauseRules, _ onChange: @escaping @MainActor (SensedConditions) -> Void) -> ConditionsSensing
    var displayName: (ConnectedDisplay) -> String
    /// Moves a deleted wallpaper's folder to the Trash, once its undo is gone.
    var trash: (WallpaperID) throws -> Void
    /// "Log Playback Metrics", the extension's probe: never kept, so every launch starts with it off.
    var isPlaybackMetricsOn: () -> Bool
    var setPlaybackMetrics: (Bool) -> Void
}

extension AppServices {
    /// The real thing: the library in Application Support (record 0002), the
    /// wallpaper extension (record 0001), the system's sensors.
    static func wired() -> AppServices {
        let location = LibraryLocation(home: .homeDirectory)
        let host = ExtensionHostClient(location: location)
        // The LGPL's relinking route: a replacement helper the user points at, else the bundled one (record 0006).
        let replacement = UserDefaults.standard.string(forKey: "FFmpegReplacement").map {
            URL(filePath: ($0 as NSString).expandingTildeInPath)
        }
        // glslang and SPIRV-Cross, next to the executable as ffmpeg is (record 0008). Without them scenes hold their posters.
        let shaderTools = ShaderTools.locate(
            bundled: Bundle.main.url(forAuxiliaryExecutable: "glslang"), Bundle.main.url(forAuxiliaryExecutable: "spirv-cross")
        )
        return AppServices(
            isFakes: false,
            host: host,
            libraryStore: FileLibraryStore(manifest: location.manifest),
            appStateStore: FileAppStateStore(file: location.appState),
            art: .library(location),
            systemServices: FakeSystemServices(),
            sweep: { try sweepInterruptedImports(in: location) },
            lastRenderState: {
                let data: Data
                do {
                    data = try Data(contentsOf: location.renderState)
                } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
                    return nil
                }
                return try RenderState.decode(data)
            },
            makeImporter: { library in
                Importer(
                    location: location,
                    library: library,
                    ffmpeg: FFmpegTool.locate(replacement: replacement, bundled: Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")),
                    shaderTools: shaderTools
                )
            },
            prepareScenes: { wallpapers, log in
                _ = await ScenePreparation.refresh(wallpapers, in: location, tools: shaderTools, log: log)
            },
            makeSensing: { rules, onChange in
                ConditionsSensing(rules: rules, host: host.capabilities, onChange: onChange)
            },
            displayName: { display in
                let screen = NSScreen.screens.first { $0.displayID == display.displayID }
                return screen?.localizedName ?? "Display \(display.displayID)"
            },
            trash: { id in
                let folder = location.wallpapers.appending(path: id.description, directoryHint: .isDirectory)
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            },
            isPlaybackMetricsOn: { host.isPlaybackMetricsOn },
            setPlaybackMetrics: { host.setPlaybackMetrics($0) }
        )
    }
}

extension NSScreen {
    /// CoreGraphics' number for this `NSScreen`'s display.
    fileprivate var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
