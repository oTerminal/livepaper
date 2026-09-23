import LivepaperCore
import LivepaperTestSupport
import Testing

@MainActor
struct FakeRenderHostTests {
    struct Refused: Error {}

    @Test func `remembers what it was asked to do, and reports as a host would`() async throws {
        let host = FakeRenderHost()
        let state = RenderState(displays: [], pauseRules: PauseRules(), conditions: nil)

        try await host.activate()
        await host.apply(state)
        host.report(.live)
        await host.recover(.flush)
        await host.deactivate()

        #expect(host.appliedStates == [state])
        #expect(host.recoveries == [.flush])
        #expect(!host.isActive)
        var reported: [RenderHostStatus] = []
        for await status in host.status.prefix(4) {
            reported.append(status)
        }
        #expect(reported == [.connecting, .live, .recovering(.flush), .stopped])
    }

    @Test func `can take a while to apply, so a fakes run shows the working phase`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.applyDelay = .seconds(1)
        let state = RenderState(displays: [], pauseRules: PauseRules(), conditions: nil)

        let applying = Task { await host.apply(state) }
        while clock.sleeperCount == 0 { await Task.yield() }
        let beforeTheDelay = host.appliedStates
        clock.advance(by: .seconds(1))
        await applying.value

        #expect(beforeTheDelay.isEmpty)
        #expect(host.appliedStates == [state])
    }

    @Test func `can go live a while after activating or recovering, as a heartbeat would arrive`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.liveAfter = .seconds(1)
        var statuses = host.status.makeAsyncIterator()

        try await host.activate()
        let connecting = await statuses.next()
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(1))
        let live = await statuses.next()
        await host.recover(.restartAgent)
        let recovering = await statuses.next()
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(1))
        let liveAgain = await statuses.next()

        #expect([connecting, live, recovering, liveAgain] == [.connecting, .live, .recovering(.restartAgent), .live])
    }

    @Test func `stopped before it goes live, it stays stopped`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.liveAfter = .seconds(1)
        var statuses = host.status.makeAsyncIterator()

        try await host.activate()
        while clock.sleeperCount == 0 { await Task.yield() }
        await host.deactivate()
        clock.advance(by: .seconds(1))
        for _ in 0..<10 { await Task.yield() }
        host.report(.notSelected)

        var reported: [RenderHostStatus?] = []
        for _ in 0..<3 { reported.append(await statuses.next()) }
        #expect(reported == [.connecting, .stopped, .notSelected])
    }

    @Test func `can refuse to activate`() async {
        let host = FakeRenderHost()
        host.activationError = Refused()

        await #expect(throws: Refused.self) { try await host.activate() }
        #expect(!host.isActive)
    }
}
