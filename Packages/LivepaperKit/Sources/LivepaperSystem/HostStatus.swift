import Foundation
import LivepaperCore

/// Why WallpaperAgent is to be restarted.
nonisolated public enum AgentRestartReason: Hashable, Sendable {
    /// The extension stayed silent until `judgeHeartbeat` reached `.restartAgent`.
    case silence
    /// The extension's spiral detector saw the agent reconnect in a loop.
    case spiral
    /// The extension's watchdog climbed its ladder to the top.
    case watchdog
    /// Someone called `recover(.restartAgent)`: the status line's button, or the developer menu.
    case user
}

/// Why a restart that was asked for is not made now.
nonisolated public enum AgentRestartRefusal: Equatable, Sendable {
    /// The last restart was less than `agentRestartGap` ago.
    case tooSoon(allowedFrom: Date)
    /// The last restart has not been followed by a heartbeat. When Livepaper is
    /// not selected the agent never launches the extension, so restarting it
    /// again would only redraw the desktop every ten minutes, forever.
    case awaitingHeartbeat
}

/// What the host's status is reduced over.
nonisolated public enum HostEvent: Equatable, Sendable {
    case activated(at: Date)
    case heartbeat(Heartbeat, at: Date)
    /// The clock, at the reducer's `nextCheck`.
    case tick(at: Date)
    case systemWillSleep
    case systemDidWake(at: Date)
    /// `recover(.restartAgent)` was called.
    case restartRequested(at: Date)
    case deactivated

    /// When the event happened; the two that carry no time change nothing that depends on it.
    public var time: Date? {
        switch self {
        case .activated(let at), .heartbeat(_, let at), .tick(let at), .systemDidWake(let at), .restartRequested(let at): at
        case .systemWillSleep, .deactivated: nil
        }
    }
}

/// What the reducer asks its owner to do.
nonisolated public enum HostAction: Equatable, Sendable {
    /// Post `HostNotification.recover` with this level: the extension tries it inside its process.
    case postRecover(RecoveryLevel)
    case restartAgent(AgentRestartReason)
    /// Said once per reason until something changes, so that the log shows it without repeating it.
    case restartRefused(AgentRestartReason, AgentRestartRefusal)
}

/// The render host's status, reduced over heartbeats, silence and the clock.
///
/// A heartbeat gives `.live`, `.notSelected` or `.unavailable` by its flags.
/// Silence gives `.recovering(level)` by `judgeHeartbeat`, and each level is
/// acted on once as it is reached. Every restart of the agent, whatever asked
/// for it, goes through `allowAgentRestart`. On top of that, an automatic
/// restart is not made while the last restart has had no heartbeat since:
/// when Livepaper is not selected, silence is all the app ever gets.
///
/// A wake starts a new grace period, because the extension's heartbeat from
/// before the sleep is old by then and says nothing about whether it is alive.
nonisolated public struct HostStatusReducer: Equatable, Sendable {
    /// How far past a change of `judgeHeartbeat`'s answer the next check lands,
    /// so that it lands on the far side of it.
    static let resolution: Duration = .milliseconds(1)

    private enum Phase: Equatable, Sendable {
        case stopped
        case awake(graceFrom: Date)
        case asleep
    }

    public let timing: HeartbeatTiming
    public private(set) var status: RenderHostStatus = .stopped
    public private(set) var lastHeartbeat: Heartbeat?
    public private(set) var lastHeartbeatAt: Date?
    public private(set) var lastAgentRestart: Date?
    /// The agent was restarted and no heartbeat has come since.
    public private(set) var restartUnanswered = false
    /// When the owner should send the next `.tick`: the moment `judgeHeartbeat`'s
    /// answer next changes, or the restart gap opens. `nil` when nothing can
    /// change until an event arrives, so the owner's timer stops.
    public private(set) var nextCheck: Date?

    private var phase = Phase.stopped
    private var activatedAt: Date?
    /// The highest level acted on in this silence.
    private var climbed: RecoveryLevel?
    private var refusalsSaid: Set<AgentRestartReason> = []

    public init(timing: HeartbeatTiming = .standard) {
        self.timing = timing
    }

    public mutating func reduce(_ event: HostEvent) -> [HostAction] {
        var actions: [HostAction] = []
        switch event {
        case .activated(let at): activate(at: at)
        case .heartbeat(let heartbeat, let at): actions = receive(heartbeat, at: at)
        case .tick(let at): actions = climb(at: at)
        case .systemWillSleep: if case .awake = phase { phase = .asleep }
        case .systemDidWake(let at): wake(at: at)
        case .restartRequested(let at): actions = requestRestart(.user, at: at)
        case .deactivated: deactivate()
        }
        status = derivedStatus(at: event.time)
        nextCheck = event.time.flatMap(nextCheck(after:))
        return actions
    }

    private mutating func activate(at now: Date) {
        phase = .awake(graceFrom: now)
        activatedAt = now
        climbed = nil
    }

    private mutating func wake(at now: Date) {
        guard phase != .stopped else { return }
        phase = .awake(graceFrom: now)
        climbed = nil
    }

    private mutating func deactivate() {
        phase = .stopped
        climbed = nil
    }

    private mutating func receive(_ heartbeat: Heartbeat, at now: Date) -> [HostAction] {
        guard phase != .stopped else { return [] }
        // A heartbeat proves the Mac is awake, even if the wake itself was not heard.
        if phase == .asleep { phase = .awake(graceFrom: now) }
        lastHeartbeat = heartbeat
        lastHeartbeatAt = now
        restartUnanswered = false
        climbed = nil
        refusalsSaid.remove(.silence)
        if !heartbeat.flags.contains(.spiralDetected) { refusalsSaid.remove(.spiral) }
        if !heartbeat.flags.contains(.restartAgentRequested) { refusalsSaid.remove(.watchdog) }

        if heartbeat.flags.contains(.spiralDetected) { return requestRestart(.spiral, at: now) }
        if heartbeat.flags.contains(.restartAgentRequested) { return requestRestart(.watchdog, at: now) }
        return []
    }

    private mutating func climb(at now: Date) -> [HostAction] {
        guard let level = judge(at: now) else { return [] }
        var actions: [HostAction] = []
        if climbed.map({ level > $0 }) ?? true {
            climbed = level
            if level < .restartAgent { actions.append(.postRecover(level)) }
        }
        if level == .restartAgent { actions += requestRestart(.silence, at: now) }
        return actions
    }

    private mutating func requestRestart(_ reason: AgentRestartReason, at now: Date) -> [HostAction] {
        if reason != .user, restartUnanswered {
            return refuse(reason, .awaitingHeartbeat)
        }
        if let last = lastAgentRestart, !allowAgentRestart(last: last, now: now) {
            return refuse(reason, .tooSoon(allowedFrom: last + agentRestartGap))
        }
        lastAgentRestart = now
        restartUnanswered = true
        refusalsSaid.removeAll()
        return [.restartAgent(reason)]
    }

    private mutating func refuse(_ reason: AgentRestartReason, _ refusal: AgentRestartRefusal) -> [HostAction] {
        // A click always gets its answer; the automatic reasons ask again on every heartbeat or tick.
        guard reason == .user || refusalsSaid.insert(reason).inserted else { return [] }
        return [.restartRefused(reason, refusal)]
    }

    private func judge(at now: Date) -> RecoveryLevel? {
        guard case .awake(let graceFrom) = phase else { return nil }
        return judgeHeartbeat(last: lastHeartbeatAt, now: now, launchedAt: graceFrom, timing: timing)
    }

    private func derivedStatus(at now: Date?) -> RenderHostStatus {
        switch phase {
        case .stopped:
            return .stopped
        case .asleep:
            return status
        case .awake:
            if restartUnanswered { return .recovering(.restartAgent) }
            if let now, let level = judge(at: now) { return .recovering(level) }
            guard let heartbeat = lastHeartbeat, let at = lastHeartbeatAt, let activatedAt, at >= activatedAt else {
                return .connecting
            }
            return Self.status(for: heartbeat.flags)
        }
    }

    private static func status(for flags: Heartbeat.Flags) -> RenderHostStatus {
        if flags.contains(.selfCheckFailed) { return .unavailable }
        return flags.contains(.desktopSurfaceAcquired) ? .live : .notSelected
    }

    /// Where `judgeHeartbeat` next changes its answer. It counts its steps from
    /// the moment the last heartbeat expires, or from the end of the grace
    /// period when there has been none since it began, and says nothing before
    /// the grace period ends.
    private func nextCheck(after now: Date) -> Date? {
        guard case .awake(let graceFrom) = phase else { return nil }
        if judge(at: now) == .restartAgent {
            guard !restartUnanswered, let last = lastAgentRestart else { return nil }
            let gapOpens = last + agentRestartGap
            return gapOpens > now ? gapOpens + Self.resolution : nil
        }
        let graceEnds = graceFrom + timing.grace
        let anchor: Date
        if let heard = lastHeartbeatAt, heard >= graceFrom {
            anchor = heard + timing.lifetime
        } else {
            anchor = graceEnds
        }
        let first = max(anchor, graceEnds)
        if now < first { return first + Self.resolution }
        let step = timing.step.timeInterval
        let stepsTaken = (now.timeIntervalSince(anchor) / step).rounded(.down)
        return anchor.addingTimeInterval((stepsTaken + 1) * step) + Self.resolution
    }
}
