import Foundation
import LivepaperCore

// A command's import (M7) is answered source by source, in the words the
// import list's toasts use: each row once it is done, each source discovery
// skipped, and each URL it could not search.

extension ImportList.Row {
    /// What the row came to; nil while it waits or runs.
    public var importedSource: ImportedSource? {
        switch state {
        case .finished(let wallpaper, _): .imported(wallpaper.id, name: wallpaper.name)
        case .duplicate(let wallpaper, _): .alreadyThere(wallpaper.id, name: wallpaper.name)
        case .failed(let reason, _, _): .notImported(name: candidate.name, reason: reason)
        case .waiting, .running: nil
        }
    }
}

extension ImportedSource {
    /// A source discovery passed over, named as it was handed over.
    public static func skipped(_ skipped: SkippedSource) -> ImportedSource {
        .notImported(name: skipped.url.lastPathComponent, reason: skipWords(skipped.reason))
    }

    /// A URL that could not be searched, or an import that failed. `name` is the candidate's.
    public static func notImported(name: String, error: any Error) -> ImportedSource {
        .notImported(name: name, reason: importFailureWords(error).reason)
    }

    /// A row cancelled from the list, or by Quit, before it was done.
    public static func cancelled(name: String) -> ImportedSource {
        .notImported(name: name, reason: "Its import was cancelled")
    }
}
