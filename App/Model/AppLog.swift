import Foundation
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import os

/// The app model's log lines, under `LivepaperSystem.logSubsystem`, category
/// `app`. The checks on screen and the manual script are read against them.
enum AppLog {
    static let category = "app"

    static let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: category)

    static func launched(fakes: Bool) -> String {
        "app: launched \(fakes ? "on fakes" : "wired")"
    }

    static func swept(_ count: Int) -> String {
        "app: swept \(count) interrupted imports"
    }

    static func sweepFailed(_ error: any Error) -> String {
        "app: sweeping interrupted imports failed: \(error)"
    }

    static func libraryUnreadable(_ error: any Error) -> String {
        "app: library not read, so nothing will be written: \(error)"
    }

    static func stateKeptAside(at url: URL, version: SchemaVersion?) -> String {
        "app: app state kept aside at \(url.path) (version \(version?.description ?? "unreadable")), starting on defaults"
    }

    static func renderStateUnreadable(_ error: any Error) -> String {
        "app: render state on disk not read: \(error)"
    }

    static func activationFailed(_ error: any Error) -> String {
        "app: host not activated: \(error)"
    }

    static func applied(_ state: RenderState) -> String {
        "app: render state \(state.generation) made, \(state.displays.count) displays showing"
    }

    static func librarySaveFailed(_ error: any Error) -> String {
        "app: library not saved, so the change was not made: \(error)"
    }

    static func stateSaveFailed(_ error: any Error) -> String {
        "app: app state not saved; it holds until quit: \(error)"
    }

    static func pausedAll(generation: UInt64?) -> String {
        "app: pause all, render state \(generation.map(String.init) ?? "none") stopped"
    }

    static let resumedAll = "app: resume all"

    static func importFinished(_ wallpaper: Wallpaper) -> String {
        "app: import finished, wallpaper \(wallpaper.id) \"\(wallpaper.name)\""
    }

    static func importDuplicate(of wallpaper: Wallpaper) -> String {
        "app: import finished, duplicate of wallpaper \(wallpaper.id) \"\(wallpaper.name)\""
    }

    static func importFailed(_ name: String, _ error: any Error) -> String {
        "app: import failed for \"\(name)\": \(error)"
    }

    static func deleted(_ wallpaper: Wallpaper) -> String {
        "app: deleted wallpaper \(wallpaper.id) \"\(wallpaper.name)\", undo offered"
    }

    static func undone(_ wallpaper: Wallpaper) -> String {
        "app: delete of wallpaper \(wallpaper.id) undone"
    }

    static func trashed(_ id: WallpaperID) -> String {
        "app: wallpaper \(id)'s folder moved to the Trash"
    }

    static func trashFailed(_ id: WallpaperID, _ error: any Error) -> String {
        "app: wallpaper \(id)'s folder not moved to the Trash; the next launch's sweep takes it: \(error)"
    }

    static func quit(lastGeneration: UInt64?) -> String {
        "app: quit, stopped after render state \(lastGeneration.map(String.init) ?? "none")"
    }

    static func scenePrepared(_ id: WallpaperID, programs: Int, failures: Int) -> String {
        "scene: prepared \(id), \(programs) programs, \(failures) failed"
    }

    static func sceneNotPrepared(_ id: WallpaperID, reason: String) -> String {
        "scene: \(id) not prepared: \(reason)"
    }

    /// A scene's preparation, at import or at launch: a notice when its programs
    /// were written, an error when they were not and it holds its poster.
    static func log(_ preparation: ScenePreparation.Outcome, of id: WallpaperID) {
        switch preparation {
        case .prepared(let programs, let failures):
            logger.notice("\(scenePrepared(id, programs: programs, failures: failures), privacy: .public)")
        case .notPrepared(let reason):
            logger.error("\(sceneNotPrepared(id, reason: reason), privacy: .public)")
        }
    }

    static func choosingFiles(asSheet: Bool) -> String {
        "app: choosing files to import, \(asSheet ? "in a sheet on the library window" : "in a panel of its own")"
    }
}
