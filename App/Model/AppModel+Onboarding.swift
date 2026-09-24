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
        let found = await Discovering.run(urls)
        guard canImport else { return .failed(Self.unwritable) }
        guard !found.candidates.isEmpty else { return .failed(Self.nothingToImport(found)) }
        let rows = enqueueImports(found.candidates)
        for await batch in Observations({ self.importList.batch(rows) }) {
            switch batch {
            case .importing:
                progress(batch)
            case .wallpaper(let wallpaper):
                setOnAllDisplays(.wallpaper(wallpaper.id))
                return .set(wallpaper)
            case .failed(let reason):
                let name = found.candidates.first?.name ?? ""
                return .failed(reason.map { "“\(name)” was not imported. \($0)." } ?? "“\(name)” was not imported.")
            }
        }
        return .failed("“\(found.candidates.first?.name ?? "")” was not imported.")
    }

    /// Leaving Livepaper as the wallpaper, recorded before the app quits: the
    /// next launch shows onboarding's last card alone.
    func recordLeaving() {
        let record = services.onboarding.record
        record.record = record.record.leaving()
    }

    private static let unwritable = "The library could not be read, so nothing can be imported."

    /// Nothing to import where the user pointed: why, as the library's toast says it.
    private static func nothingToImport(_ found: Discovering.Found) -> String {
        if let skipped = found.skipped.first { return ImportToast.skipped(skipped).words }
        if let failure = found.failures.first { return ImportToast.failed(name: failure.name, error: failure.error).words }
        return "There is nothing there that Livepaper can import."
    }
}
