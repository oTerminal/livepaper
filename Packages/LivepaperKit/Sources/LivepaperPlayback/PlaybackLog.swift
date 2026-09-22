import Foundation

/// The wording of the engine's and the layer tree's own log lines, in one place. The metrics
/// line, which other milestones read, is `PlaybackMetrics.logLine(for:)`.
enum PlaybackLog {
    /// A library video as the log names it: its folder, which is the wallpaper's ID, and its file.
    static func name(of url: URL?) -> String {
        guard let url else { return "nothing" }
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }

    static func cannotRead(_ url: URL, _ error: any Error) -> String {
        "engine: cannot read \(name(of: url)): \(describe(error))"
    }

    static func rendererFailed(_ url: URL?, _ error: (any Error)?) -> String {
        "engine: renderer failed on \(name(of: url)), starting again from a fresh reader: \(describe(error))"
    }

    static func rendererAskedForFlush(_ url: URL?) -> String {
        "engine: renderer asked for a flush on \(name(of: url)), starting again from a fresh reader"
    }

    static func readerFailed(_ url: URL?, _ error: (any Error)?) -> String {
        "engine: reader failed on \(name(of: url)), starting again from a fresh reader: \(describe(error))"
    }

    static func passWithoutFrames(_ url: URL?) -> String {
        "engine: a pass of \(name(of: url)) had no frames"
    }

    static func audioFailed(_ url: URL?, _ error: (any Error)?) -> String {
        "engine: audio failed on \(name(of: url)), going on without it: \(describe(error))"
    }

    static func gaveUp(_ url: URL?, restarts: Int) -> String {
        "engine: gave up on \(name(of: url)) after \(restarts) restarts without a loop"
    }

    static func cannotPlay(_ surface: SurfaceID, _ url: URL) -> String {
        "layers: surface \(surface) cannot play \(name(of: url)), holding its poster"
    }

    static func posterUnreadable(_ surface: SurfaceID, _ url: URL) -> String {
        "layers: surface \(surface) cannot read the poster \(name(of: url)), showing the neutral colour"
    }

    static func notReadyForDisplay(_ surface: SurfaceID, _ url: URL?) -> String {
        "layers: surface \(surface) had no picture of \(name(of: url)) after 1 s, going ahead"
    }

    private static func describe(_ error: (any Error)?) -> String {
        guard let error = error as NSError? else { return "no error given" }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
