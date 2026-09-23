import Foundation

/// Scene time: the seconds a scene has been drawn for, which run only while it
/// plays (record 0007). A pause, a suspend or a recovery stops it where it is,
/// and the next start carries on from there, so a scene resumes where it
/// stopped, as a video does. It is read in the display link's own times, the
/// moments frames are to be shown at, and never runs backwards.
struct SceneClock: Equatable, Sendable {
    /// Scene time when the run under way began.
    private(set) var carried: Double = 0
    /// The scene time of the latest frame.
    private(set) var latest: Double = 0
    private var isRunning = false
    /// The moment the run's first frame is shown at; nil before it.
    private var runStart: Double?

    mutating func start() {
        isRunning = true
        runStart = nil
    }

    /// The scene time of a frame to be shown at `moment`, in the link's seconds.
    /// The first frame of a run shows the time the last run stopped at.
    mutating func time(forFrameAt moment: Double) -> Double {
        guard isRunning else { return latest }
        let start = runStart ?? moment
        runStart = start
        latest = max(latest, carried + max(0, moment - start))
        return latest
    }

    mutating func stop() {
        carried = latest
        isRunning = false
        runStart = nil
    }

    /// Back to the scene's first moment, for another scene or the same one started afresh.
    mutating func reset() {
        self = SceneClock()
    }
}

/// What the scene engine has done since it was made, for the watchdog's counts.
struct SceneTally: Equatable, Sendable {
    /// Frames encoded and handed to the GPU: what the engine fed.
    var committed = 0
    /// Frames the window server showed, by their presented time: what was displayed.
    var presented = 0

    /// The watchdog's count over a window between two tallies (`PictureCount`), at the scene's rate.
    static func count(from before: SceneTally, to after: SceneTally, over window: Duration, framesPerSecond: Double) -> PictureCount {
        PictureCount(
            displayed: after.presented - before.presented,
            expected: Int((window / .seconds(1) * framesPerSecond).rounded()),
            fed: after.committed - before.committed
        )
    }
}
