import Foundation
import LivepaperCore

// What the import list and its toasts say, in English only for v1.0. The
// toast names the file, so a reason speaks of it as "it".

/// What the import list says while an import is at this stage.
public func stageWords(_ stage: ImportStage) -> String {
    switch stage {
    case .fingerprint: "Checking"
    case .probe: "Reading"
    case .convert: "Converting"
    case .normalise: "Optimising"
    case .validate: "Checking the loop"
    case .artefacts: "Making the poster"
    case .commit: "Finishing"
    }
}

/// Why an import failed, for its row and its toast, and whether Retry can
/// help: it can when the cause lies outside the file (a drive that went, a
/// full disk), and cannot when the same file would fail the same way again.
public func importFailureWords(_ error: any Error) -> (reason: String, canRetry: Bool) {
    switch error {
    case let error as ImportError: words(for: error)
    case let error as MediaError: words(for: error)
    case let error as FFmpegError: words(for: error)
    case ArtefactError.noPicture: ("It has no picture to make a poster from", false)
    case ArtefactError.posterNotWritten: ("Its poster could not be written", true)
    case DiscoverError.notFound: ("It could not be found", true)
    case let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code): ("It could not be found", true)
    case let error as CocoaError where error.code == .fileWriteOutOfSpace: ("There is not enough disk space", true)
    default: ("It could not be imported", true)
    }
}

/// Why a discovered source was skipped, for its toast. What a project says is
/// repeated back only when it helps the user find the file: an unknown type or
/// a path out of the folder is untrusted text, and says nothing useful.
public func skipWords(_ reason: SkipReason) -> String {
    switch reason {
    case .wallpaperEngine(.unsupportedType(let type)):
        let kind = ["scene": "scene", "web": "web page", "application": "application"][type]
        return kind.map { "It is a Wallpaper Engine \($0); only video items can be imported" }
            ?? "Only Wallpaper Engine video items can be imported"
    case .wallpaperEngine(.malformed): return "Its Wallpaper Engine project cannot be read"
    case .wallpaperEngine(.noFile): return "Its Wallpaper Engine project names no file"
    case .wallpaperEngine(.escapesFolder): return "Its Wallpaper Engine project names a file outside its folder"
    case .missingFile(let file): return "Its Wallpaper Engine project names “\(file)”, which is not in its folder"
    }
}

/// The toast for a source file the library already has: nothing was imported.
public func duplicateToastWords(of wallpaper: Wallpaper) -> String {
    "Already in the library as “\(wallpaper.name)”"
}

/// The toast for a source that discovery passed over, named as the user dropped it.
public func skippedToastWords(_ skipped: SkippedSource) -> String {
    "“\(skipped.url.lastPathComponent)” was not imported. \(skipWords(skipped.reason))."
}

/// The toast for an import that failed. `name` is the candidate's.
public func failedToastWords(name: String, error: any Error) -> String {
    "“\(name)” was not imported. \(importFailureWords(error).reason)."
}

private func words(for error: ImportError) -> (reason: String, canRetry: Bool) {
    switch error {
    case .rejected(.unrecognised): ("It is not a kind of file Livepaper can read", false)
    case .rejected(.noVideo): ("It has no picture to play", false)
    case .rejected(.noFrames): ("It has no frames to play", false)
    case .rejected(.protected): ("It is copy-protected", false)
    // The helper is looked for once, when the importer is made: Retry would meet the same importer.
    case .helperMissing: ("Its format needs the ffmpeg helper, which is missing", false)
    case .helperOutputUnreadable: ("The ffmpeg helper converted it, but Livepaper cannot read the result", false)
    case .loopSeam: ("It would not loop without a gap", false)
    }
}

private func words(for error: MediaError) -> (reason: String, canRetry: Bool) {
    switch error {
    case .noVideoTrack: ("It has no picture to play", false)
    case .readFailed: ("It could not be read", true)
    case .writeFailed: ("Its optimised copy could not be written", true)
    }
}

private func words(for error: FFmpegError) -> (reason: String, canRetry: Bool) {
    switch error {
    case .launchFailed: ("The ffmpeg helper could not be started", true)
    case .failed: ("The ffmpeg helper could not convert it", false)
    case .timeLimitExceeded: ("Converting it took too long", false)
    case .sizeLimitExceeded: ("It would be too large once converted", false)
    }
}
