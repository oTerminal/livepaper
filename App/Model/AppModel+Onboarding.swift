import Foundation
import LivepaperCore
import LivepaperImport
import Observation

// Onboarding's part of the model (M7): the first wallpaper, imported through
// the import list as any import is and set on every display, and leaving
// recorded, so that the next launch offers to make Livepaper the wallpaper again.

extension AppModel {
    /// How the first card's import ended.
    enum FirstWallpaperOutcome: Equatable {
        /// On every display now.
        case set(Wallpaper)
        /// Why nothing came of it, in a sentence.
        case failed(String)
    }

    /// Imports what was dropped on the first card, chosen, or picked from the
    /// samples, and sets the first wallpaper that comes of it on every display:
    /// a new one, or the one a file already is in the library. `progress` hears
    /// the import's stage as it runs. The rest of several files go on importing.
    func importFirstWallpaper(from urls: [URL], progress: @escaping (ImportBatch) -> Void) async -> FirstWallpaperOutcome {
        guard canImport else {
            return .failed(libraryProblem == nil ? "Livepaper is still starting. Try again in a moment." : Self.unwritable)
        }
        let enqueued = await enqueueImport(urls)
        guard canImport else { return .failed(Self.unwritable) }
        guard let first = enqueued.rows.first else { return .failed(Self.nothingToImport(enqueued.notListed)) }
        let rows = enqueued.rows.map(\.id)
        for await batch in Observations({ self.importList.batch(rows) }) {
            switch batch {
            case .importing:
                progress(batch)
            case .wallpaper(let wallpaper):
                setOnAllDisplays(.wallpaper(wallpaper.id))
                return .set(wallpaper)
            case .failed(let reason):
                return .failed(Self.notImported(first.name, reason))
            }
        }
        return .failed(Self.notImported(first.name, nil))
    }

    /// Leaving Livepaper as the wallpaper, recorded before the app quits: the
    /// next launch shows onboarding's last card alone.
    func recordLeaving() {
        let record = services.onboarding.record
        record.record = record.record.leaving()
    }

    private static let unwritable = "The library could not be read, so nothing can be imported."

    /// Nothing to import where the user pointed: why, as the library's toast says it.
    private static func nothingToImport(_ notListed: [ImportedSource]) -> String {
        guard case .notImported(let name, let reason) = notListed.first else { return "There is nothing there that Livepaper can import." }
        return notImported(name, reason)
    }

    private static func notImported(_ name: String, _ reason: String?) -> String {
        "“\(name)” was not imported." + (reason.map { " \($0)." } ?? "")
    }
}
