import Foundation
import os
import Testing
import LivepaperCore
import LivepaperPlayback
import LivepaperTestSupport

/// The supervisor as the extension owns it: on one actor, with fake surfaces and a clock the test moves.
@MainActor
final class SupervisorBench {
    static let geometry = SurfaceGeometry(size: Size(width: 1800, height: 1169), scale: 2)

    let clock: ManualClock
    let tornDown = Journal<SurfaceID>()
    let supervisor: PlaybackSupervisor
    private(set) var surfaces: [Int: FakeSurface] = [:]
    private(set) var made = 0

    init() {
        let clock = ManualClock(start: Moment.launch)
        let tornDown = tornDown
        self.clock = clock
        supervisor = PlaybackSupervisor(
            location: testLibrary,
            clock: clock,
            now: { clock.date },
            logger: Logger(subsystem: "app.livepaper.tests", category: "supervisor"),
            tearDown: { tornDown.append($0) }
        )
    }

    /// The agent acquires surface `number` for `display`. A layer tree is made only when the supervisor asks for one.
    @discardableResult
    func acquire(_ number: Int, display: Int, preview: Bool = false) async -> SurfaceStoreEffect {
        await supervisor.acquire(.numbered(number), display: .numbered(display), isPreview: preview, geometry: Self.geometry) {
            let surface = FakeSurface()
            self.surfaces[number] = surface
            self.made += 1
            return surface
        }
    }

    func surface(_ number: Int) -> FakeSurface {
        guard let surface = surfaces[number] else { preconditionFailure("surface \(number) was never made") }
        return surface
    }

    func apply(_ state: RenderState) async {
        await supervisor.apply(.read(state)).value
    }

    /// Lets the supervisor's own timers reach their sleep, so that moving the clock wakes them.
    func settle(sleepers: Int) async {
        while clock.sleeperCount < sleepers { await Task.yield() }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PlaybackSupervisorTests {
    static func state(
        _ displays: RenderState.Display...,
        generation: UInt64 = 1,
        stopped: Bool = false,
        rules: PauseRules = PauseRules(),
        conditions: SensedConditions? = nil
    ) -> RenderState {
        RenderState(generation: generation, isStopped: stopped, displays: displays, pauseRules: rules, conditions: conditions)
    }

    static let stalled = PictureCount(displayed: 0, expected: 60)

    /// Conditions the app sensed at launch: `display` is covered.
    static func covering(_ display: Int) -> SensedConditions {
        SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(display)])
    }

    // MARK: What surfaces show

    @Test func `an acquired surface shows its display's wallpaper`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2), generation: 42))

        let effect = await bench.acquire(1, display: 2)

        #expect(effect == .create(.numbered(1)))
        #expect(bench.surface(1).playbackCalls == [.show(.numbered(2), crossfade: false)])
        #expect(bench.supervisor.heartbeat == Heartbeat(generation: 42, flags: [.desktopSurfaceAcquired]))
    }

    @Test func `with no render state a surface shows the neutral colour and the heartbeat says so`() async {
        let bench = SupervisorBench()

        await bench.acquire(1, display: 1)

        #expect(bench.surface(1).playbackCalls == [])
        #expect(bench.supervisor.heartbeat == Heartbeat(generation: 0, flags: [.desktopSurfaceAcquired, .holdingStill]))
    }

    @Test func `a new wallpaper crossfades on a surface that plays`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.apply(Self.state(.numbered(1, showing: 2), generation: 2))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .show(.numbered(2), crossfade: true)])
        #expect(bench.supervisor.heartbeat.generation == 2)
    }

    @Test func `the stopped state holds each display's poster`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2)))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)

        await bench.apply(Self.state(.numbered(1), .numbered(2), generation: 2, stopped: true))

        #expect(bench.surface(1).playbackCalls.last == .holdStill(.numbered(1)))
        #expect(bench.surface(2).playbackCalls.last == .holdStill(.numbered(2)))
        #expect(bench.supervisor.heartbeat == Heartbeat(generation: 2, flags: [.desktopSurfaceAcquired, .holdingStill]))
    }

    @Test func `an unreadable state keeps what is shown`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), generation: 5))
        await bench.acquire(1, display: 1)

        await bench.supervisor.apply(.unreadable("unknown schema version 2.0")).value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false)])
        #expect(bench.supervisor.heartbeat.generation == 5)
    }

    @Test func `a state that goes missing shows nothing`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.supervisor.apply(.missing).value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .showNothing])
        #expect(bench.supervisor.heartbeat.flags.contains(.holdingStill))
    }

    @Test func `the preview shows its display's wallpaper and is not the desktop`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1, showing: 3)))

        await bench.acquire(7, display: 1, preview: true)

        #expect(bench.surface(7).playbackCalls == [.show(.numbered(3), crossfade: false)])
        #expect(!bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))
        await bench.acquire(1, display: 1)
        #expect(bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))
    }

    // MARK: The agent's reconnects

    @Test func `a re-acquire within the grace reuses the surface and lays it out`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.clock.advance(by: .seconds(1))
        bench.supervisor.invalidate(.numbered(1))
        #expect(!bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))

        bench.clock.advance(by: .seconds(14))
        let effect = await bench.acquire(1, display: 1)

        #expect(effect == .reuse(.numbered(1)))
        #expect(bench.made == 1)
        #expect(bench.surface(1).calls.entries.last == .layout(SupervisorBench.geometry))
        #expect(bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))
        #expect(bench.clock.sleeperCount == 0, "its teardown is cancelled")
    }

    @Test func `an abandoned surface is torn down after the grace and a returning display gets its wallpaper`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1, showing: 4)))
        await bench.acquire(1, display: 1)
        bench.supervisor.invalidate(.numbered(1))
        await bench.settle(sleepers: 1)

        bench.clock.advance(by: .seconds(14.9))
        #expect(bench.clock.sleeperCount == 1, "still within its grace")
        bench.clock.advance(by: .milliseconds(100))
        await bench.tornDown.wait(for: 1)
        await bench.surface(1).calls.wait(for: 2)

        #expect(bench.tornDown.entries == [.numbered(1)])
        #expect(bench.surface(1).playbackCalls == [.show(.numbered(4), crossfade: false), .showNothing])
        let effect = await bench.acquire(2, display: 1)
        #expect(effect == .create(.numbered(2)))
        #expect(bench.surface(2).playbackCalls == [.show(.numbered(4), crossfade: false)])
    }

    @Test func `a surface within its grace follows a new state, so stopping releases its decoder too`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1, preview: true)
        bench.supervisor.invalidate(.numbered(1))

        await bench.apply(Self.state(.numbered(1), generation: 2, stopped: true))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .holdStill(.numbered(1))])
    }

    @Test func `an unknown surface cannot be invalidated`() {
        let bench = SupervisorBench()

        #expect(!bench.supervisor.invalidate(.numbered(9)))
    }

    @Test func `a new geometry lays out a display's desktop surfaces, not its preview`() async {
        let bench = SupervisorBench()
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 1, preview: true)
        await bench.acquire(3, display: 2)
        let geometry = SurfaceGeometry(size: Size(width: 1280, height: 1024), scale: 1)

        bench.supervisor.layout(display: .numbered(1), geometry: geometry)

        #expect(bench.surface(1).calls.entries == [.layout(geometry)])
        #expect(bench.surface(2).calls.entries.isEmpty)
        #expect(bench.surface(3).calls.entries.isEmpty)
    }

    // MARK: Decisions

    @Test func `a covered display pauses and plays again when its conditions expire`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.apply(Self.state(.numbered(1), generation: 2, conditions: Self.covering(1)))
        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause])
        await bench.settle(sleepers: 1)
        bench.clock.advance(by: .seconds(30))
        #expect(bench.clock.sleeperCount == 1, "conditions 30 s old still count")
        bench.clock.advance(by: .seconds(1))
        await bench.surface(1).calls.wait(for: 3)

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause, .resume])
    }

    @Test func `the user's pause does not expire`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.apply(Self.state(.numbered(1, userPaused: true), conditions: Self.covering(1)))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause])
        #expect(bench.clock.sleeperCount == 0)
    }

    @Test func `a sleeping display suspends and plays once its conditions go stale`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        await bench.apply(Self.state(.numbered(1), conditions: SensedConditions(sensedAt: Moment.launch, asleepDisplays: [.numbered(1)])))
        #expect(bench.surface(1).playbackCalls.last == .suspend)

        // The Mac sleeps for an hour and the app has not written since.
        bench.clock.advance(by: .seconds(3600))
        await bench.surface(1).calls.wait(for: 3)

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .suspend, .resume])
    }

    @Test func `a wake decides again and checks a second later`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).lose()

        let wake = bench.supervisor.wake()
        await bench.settle(sleepers: 1)
        bench.clock.advance(by: .milliseconds(900))
        #expect(bench.clock.sleeperCount == 1, "not yet")
        bench.clock.advance(by: .milliseconds(100))
        await wake.value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .show(.numbered(1), crossfade: false)])
        #expect(bench.surface(1).countsTaken == 1)
    }

    // MARK: The watchdog

    @Test func `a check judges the desktop surfaces that play on screen`() async {
        let bench = SupervisorBench()
        let covered = SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(2)])
        await bench.apply(Self.state(.numbered(1), .numbered(2), rules: PauseRules(whenDesktopCovered: false), conditions: covered))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)
        await bench.acquire(3, display: 1, preview: true)

        await bench.supervisor.check().value

        #expect(bench.surface(1).countsTaken == 1)
        #expect(bench.surface(2).countsTaken == 0, "covered: not composited")
        #expect(bench.surface(3).countsTaken == 0, "the preview")
    }

    @Test func `a covered display on the lock screen is judged`() async {
        let bench = SupervisorBench()
        let covered = SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(1)], locked: true)
        await bench.apply(Self.state(.numbered(1), conditions: covered))
        await bench.acquire(1, display: 1)

        await bench.supervisor.update(.numbered(1), mode: .locked).value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false)])
        #expect(bench.surface(1).countsTaken == 1)
    }

    @Test func `a stall climbs the ladder inside the process, then asks the app for the agent`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [Self.stalled, Self.stalled, Self.stalled, Self.stalled]

        await bench.supervisor.unlock().value

        #expect(bench.surface(1).recoveries == [.flush, .rebuildSurface, .rebuildPipeline])
        #expect(bench.surface(1).countsTaken == 4)
        #expect(bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))

        await bench.supervisor.check().value

        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested), "a later healthy check clears it")
    }

    @Test func `a recovery that works ends the ladder`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [Self.stalled]

        await bench.supervisor.check().value

        #expect(bench.surface(1).recoveries == [.flush])
        #expect(bench.surface(1).countsTaken == 2)
        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))
    }

    @Test func `the app's recovery runs at once on the stalled surfaces`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2)))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)
        bench.surface(1).counts = [Self.stalled, Self.stalled, Self.stalled, Self.stalled]
        await bench.supervisor.check().value

        await bench.supervisor.recover(.rebuildSurface).value

        #expect(bench.surface(1).recoveries == [.flush, .rebuildSurface, .rebuildPipeline, .rebuildSurface])
        #expect(bench.surface(2).recoveries == [])
        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested), "the check after it found pictures")
    }

    @Test func `a surface that goes takes its restart request with it`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [Self.stalled, Self.stalled, Self.stalled, Self.stalled]
        await bench.supervisor.check().value

        bench.supervisor.invalidate(.numbered(1))

        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))
    }

    @Test func `a paused surface is not judged`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1, userPaused: true)))
        await bench.acquire(1, display: 1)

        await bench.supervisor.check().value

        #expect(bench.surface(1).countsTaken == 0)
    }
}
