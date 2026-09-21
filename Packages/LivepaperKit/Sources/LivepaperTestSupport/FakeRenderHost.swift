import LivepaperCore

/// A render host that draws nothing and remembers what it was asked to do.
@MainActor
public final class FakeRenderHost: RenderHost {
    public var capabilities: HostCapabilities
    /// Set to make `activate()` throw.
    public var activationError: (any Error)?

    public private(set) var isActive = false
    public private(set) var appliedStates: [RenderState] = []
    public private(set) var recoveries: [RecoveryLevel] = []

    public let status: AsyncStream<RenderHostStatus>
    private let statusContinuation: AsyncStream<RenderHostStatus>.Continuation

    public init(capabilities: HostCapabilities = HostCapabilities(showsLockScreen: true)) {
        self.capabilities = capabilities
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
