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

    public private(set) var isActive = false
    public private(set) var appliedStates: [RenderState] = []
    public private(set) var recoveries: [RecoveryLevel] = []

    public let status: AsyncStream<RenderHostStatus>
    private let statusContinuation: AsyncStream<RenderHostStatus>.Continuation
    private let clock: any Clock<Duration>

    public init(capabilities: HostCapabilities = HostCapabilities(showsLockScreen: true), clock: any Clock<Duration> = ContinuousClock()) {
        self.capabilities = capabilities
        self.clock = clock
        (status, statusContinuation) = AsyncStream.makeStream()
    }

    /// Reports a status, as the real host does when a heartbeat arrives or stops.
    public func report(_ status: RenderHostStatus) {
        statusContinuation.yield(status)
    }

    public func activate() async throws {
        if let activationError { throw activationError }
        isActive = true
        report(.connecting)
    }

    public func apply(_ state: RenderState) async {
        if let applyDelay {
            try? await clock.sleep(for: applyDelay)
        }
        appliedStates.append(state)
    }

    public func recover(_ level: RecoveryLevel) async {
        recoveries.append(level)
        report(.recovering(level))
    }

    public func deactivate() async {
        isActive = false
        report(.stopped)
    }
}
