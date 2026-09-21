import Foundation

/// The recovery ladder, mildest first. The watchdog walks it after a stall and
/// the app walks it after launch when no heartbeat arrives (record 0001).
public enum RecoveryLevel: Int, CaseIterable, Comparable, Sendable {
    case flush
    case rebuildSurface
    case rebuildPipeline
    case restartAgent

    public static func < (lhs: RecoveryLevel, rhs: RecoveryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The level for the given number of levels already climbed, ending at `.restartAgent`.
    init(step: Int) {
        let last = Self.allCases.count - 1
        self = Self.allCases[min(max(step, 0), last)]
    }
}

public enum WatchdogVerdict: Equatable, Sendable {
    case healthy
    case recover(RecoveryLevel)

    public static let flush = WatchdogVerdict.recover(.flush)
    public static let rebuildSurface = WatchdogVerdict.recover(.rebuildSurface)
    public static let rebuildPipeline = WatchdogVerdict.recover(.rebuildPipeline)
    public static let restartAgent = WatchdogVerdict.recover(.restartAgent)
}

/// Judges whether a surface is showing new pictures.
///
/// `before` and `after` are displayed-picture counts taken at the two ends of a
/// window in which `expected` pictures should have been shown. A running
/// timebase proves nothing (record 0001), so pictures are what is counted.
/// Half the expected pictures or more is healthy. Otherwise the verdict is the
/// next recovery, where `attempt` is how many have already been tried for this stall.
///
/// Only ask about a surface that is on screen: the window server throttles a
/// hidden one, and it would look stalled.
public func judgeProgress(before: Int, after: Int, expected: Int, attempt: Int) -> WatchdogVerdict {
    let displayed = max(after - before, 0)
    if displayed * 2 >= expected { return .healthy }
    return .recover(RecoveryLevel(step: attempt))
}

/// Whether WallpaperAgent may be restarted now. Both the watchdog's and the
/// heartbeat's `.restartAgent` go through here, so the agent is never restarted
/// twice within `minimumGap`.
public func allowAgentRestart(last: Date?, now: Date, minimumGap: Duration = .seconds(600)) -> Bool {
    guard let last else { return true }
    return now.elapsed(since: last) >= minimumGap
}

/// How long the app waits for the extension's heartbeat before acting.
public struct HeartbeatTiming: Equatable, Sendable {
    /// After launch, how long the extension has to send its first heartbeat.
    public var grace: Duration
    /// How long a heartbeat counts for.
    public var lifetime: Duration
    /// How long each recovery level is given before the next is tried.
    public var step: Duration

    public init(grace: Duration, lifetime: Duration, step: Duration) {
        self.grace = grace
        self.lifetime = lifetime
        self.step = step
    }

    /// Provisional until M5 measures the production extension.
    public static let standard = HeartbeatTiming(grace: .seconds(20), lifetime: .seconds(15), step: .seconds(10))
}

/// Judges the extension's heartbeat: `nil` while all is well, otherwise the
/// recovery level that the silence has reached.
///
/// After an install or update the first extension instance is killed once by
/// the next app launch, and the agent does not start it again (record 0001).
/// The spike found no time window for that, so the rule is only "no heartbeat
/// after the grace period". The level depends on time alone: the caller acts
/// when it changes, and sends `.restartAgent` through `allowAgentRestart`.
public func judgeHeartbeat(last: Date?, now: Date, launchedAt: Date, timing: HeartbeatTiming = .standard) -> RecoveryLevel? {
    let sinceLaunch = now.elapsed(since: launchedAt)
    guard sinceLaunch >= timing.grace else { return nil }

    let overdue: Duration
    if let last, last >= launchedAt {
        overdue = now.elapsed(since: last) - timing.lifetime
        guard overdue > .zero else { return nil }
    } else {
        overdue = sinceLaunch - timing.grace
    }
    return RecoveryLevel(step: Int(overdue / timing.step))
}
