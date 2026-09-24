import Foundation
import LivepaperCore

/// A render host that draws nothing and remembers what it was asked to do.
@MainActor
public final class FakeRenderHost: RenderHost {
    public var capabilities: HostCapabilities
    /// Set to make `activate()` throw.
    public var activationError: (any Error)?
    /// How long `apply` takes, on the host's clock: long enough, in a fakes run,
    /// to see Set on Display working. Nil applies at once.
    public var applyDelay: Duration?
    /// How long after `activate()` or `recover(_:)` the host reports `.live`, on
    /// its clock, as the real host does when a heartbeat arrives. Nil never does:
    /// a test reports it. Any other report, or a deactivate, comes first.
    public var liveAfter: Duration?
    /// How long `recover(.restartAgent)` takes, on the host's clock, as the real
    /// host waits for WallpaperAgent to come back. Nil restarts at once.
    public var agentRestartTime: Duration?
    /// The time of day, for the gap between two restarts of the agent.
    public var now: () -> Date = Date.init

    public private(set) var isActive = false
    public private(set) var appliedStates: [RenderState] = []
    public private(set) var recoveries: [RecoveryLevel] = []
    /// As the real host keeps it: a restart is made only `agentRestartGap` after the last one.
    public private(set) var lastAgentRestart: Date?

    public let status: AsyncStream<RenderHostStatus>
    private let statusContinuation: AsyncStream<RenderHostStatus>.Continuation
    private let clock: any Clock<Duration>
    private var goingLive: Task<Void, Never>?

    public init(capabilities: HostCapabilities = HostCapabilities(showsLockScreen: true), clock: any Clock<Duration> = ContinuousClock()) {
        self.capabilities = capabilities
        self.clock = clock
        (status, statusContinuation) = AsyncStream.makeStream()
    }

    /// Reports a status, as the real host does when a heartbeat arrives or stops.
    public func report(_ status: RenderHostStatus) {
        goingLive?.cancel()
        goingLive = nil
        statusContinuation.yield(status)
    }

    public func activate() async throws {
        if let activationError { throw activationError }
        isActive = true
        report(.connecting)
        goLiveLater()
    }

    public func apply(_ state: RenderState) async {
        if let applyDelay {
            try? await clock.sleep(for: applyDelay)
        }
        appliedStates.append(state)
    }

    /// `.restartAgent` goes through `allowAgentRestart`, as the real host's does:
    /// refused, it reports nothing.
    public func recover(_ level: RecoveryLevel) async {
        if level == .restartAgent, let agentRestartTime {
            try? await clock.sleep(for: agentRestartTime)
        }
        recoveries.append(level)
        if level == .restartAgent {
            guard allowAgentRestart(last: lastAgentRestart, now: now()) else { return }
            lastAgentRestart = now()
        }
        report(.recovering(level))
        goLiveLater()
    }

    public func deactivate() async {
        isActive = false
        report(.stopped)
    }

    private func goLiveLater() {
        guard let liveAfter else { return }
        goingLive = Task { [clock] in
            do {
                try await clock.sleep(for: liveAfter)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            report(.live)
        }
    }
}
