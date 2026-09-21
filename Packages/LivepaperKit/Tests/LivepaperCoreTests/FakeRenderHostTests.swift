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

    @Test func `can refuse to activate`() async {
        let host = FakeRenderHost()
        host.activationError = Refused()

        await #expect(throws: Refused.self) { try await host.activate() }
        #expect(!host.isActive)
    }
}
