import Foundation
import Testing
import LivepaperCore

struct RenderStateMakeTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let unplugged = DisplayIdentity.numbered(3)

    /// Wallpapers 1 to 4; 1 is framed and has sound. Wallpaper 9 is not in it.
    static func library() throws -> Library {
        var framed = Wallpaper.numbered(1)
        framed.presentation = Presentation(fit: .fit, focalPoint: Point(x: 0.25, y: 0.5), zoom: 1.5, pan: Point(x: 0.1, y: 0))
        framed.volume = 0.6
        return try Library.of(framed, .numbered(2), .numbered(3), .numbered(4))
    }

    /// Wallpapers 9, 2 and 3, in order: wallpaper 9 is one the library has lost.
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: [.numbered(9), .numbered(2), .numbered(3)], interval: .seconds(600), shuffle: false
    )
    static let empty = Playlist(id: .numbered(2), name: "Empty", wallpapers: [], interval: .seconds(600), shuffle: false)

    static func state(_ change: (inout AppState) -> Void) -> AppState {
        var state = AppState()
        state.playlists = [evening, empty]
        change(&state)
        return state
    }

    static func make(
        _ state: AppState, connected: [DisplayIdentity] = [first], conditions: SensedConditions? = nil, previous: RenderState? = nil
    ) throws -> RenderState? {
        RenderState.make(library: try library(), state: state, connected: connected, conditions: conditions, previous: previous)
    }

    static func display(_ identity: DisplayIdentity, _ wallpaper: Wallpaper) -> RenderState.Display {
        RenderState.Display(
            identity: identity,
            wallpaper: wallpaper.id,
            optimisedCopy: wallpaper.optimisedCopy,
            poster: wallpaper.poster,
            presentation: wallpaper.presentation,
            volume: wallpaper.volume,
            userPaused: false
        )
    }

    // MARK: What a display shows

    static let shown: [Row<AppState, WallpaperID?>] = [
        Row("a wallpaper assignment", state { $0.assignments[first] = .wallpaper(.numbered(2)) }, .numbered(2)),
        Row(
            "a playlist shows its rotation's current wallpaper",
            state {
                $0.assignments[first] = .playlist(.numbered(1))
                $0.rotation[first] = RotationState(current: .numbered(3), position: 2)
            },
            .numbered(3)
        ),
        Row(
            "a playlist with no rotation yet shows its first wallpaper the library still has",
            state { $0.assignments[first] = .playlist(.numbered(1)) },
            .numbered(2)
        ),
        Row(
            "a playlist whose current wallpaper was deleted shows the one that followed it",
            state {
                $0.assignments[first] = .playlist(.numbered(1))
                $0.rotation[first] = RotationState(current: nil, position: 2)
            },
            .numbered(3)
        ),
        Row(
            "a playlist whose current wallpaper the library has lost shows the next it has",
            state {
                $0.assignments[first] = .playlist(.numbered(1))
                $0.rotation[first] = RotationState(current: .numbered(9), position: 0)
            },
            .numbered(2)
        ),
        Row("apply to all, on a display with none of its own", state { $0.applyToAll = .wallpaper(.numbered(4)) }, .numbered(4)),
        Row(
            "its own assignment before apply to all",
            state {
                $0.applyToAll = .wallpaper(.numbered(4))
                $0.assignments[first] = .wallpaper(.numbered(2))
            },
            .numbered(2)
        ),
        Row("an unassigned display is left out", state { _ in }, nil),
        Row("a wallpaper the library has lost counts as unassigned", state { $0.assignments[first] = .wallpaper(.numbered(9)) }, nil),
        Row("an empty playlist shows nothing", state { $0.assignments[first] = .playlist(.numbered(2)) }, nil),
        Row("a playlist that is not there shows nothing", state { $0.assignments[first] = .playlist(.numbered(7)) }, nil),
    ]

    @Test(arguments: shown)
    func `each display shows its assignment's wallpaper`(row: Row<AppState, WallpaperID?>) throws {
        let state = try #require(try Self.make(row.input))

        #expect(state.displays.map(\.wallpaper) == [row.expected].compactMap(\.self))
    }

    @Test func `a display gets the library's files, presentation and volume`() throws {
        let state = try #require(try Self.make(Self.state { $0.assignments[Self.first] = .wallpaper(.numbered(1)) }))

        #expect(state.displays == [Self.display(Self.first, try #require(try Self.library()[.numbered(1)]))])
    }

    @Test func `a paused display is paused by the user, and the others are not`() throws {
        let state = try #require(try Self.make(
            Self.state {
                $0.applyToAll = .wallpaper(.numbered(2))
                $0.pausedDisplays = [Self.second]
            },
            connected: [Self.first, Self.second]
        ))

        #expect(state.displays.map(\.userPaused) == [false, true])
    }

    @Test func `muted, every display's volume is 0`() throws {
        let state = try #require(try Self.make(
            Self.state {
                $0.assignments = [Self.first: .wallpaper(.numbered(1)), Self.second: .wallpaper(.numbered(1))]
                $0.isMuted = true
            },
            connected: [Self.first, Self.second]
        ))

        #expect(state.displays.map(\.volume) == [0, 0])
    }

    @Test func `only connected displays are shown, in a fixed order`() throws {
        let state = try #require(try Self.make(
            Self.state {
                $0.assignments = [Self.unplugged: .wallpaper(.numbered(3)), Self.second: .wallpaper(.numbered(2))]
                $0.applyToAll = .wallpaper(.numbered(4))
            },
            connected: [Self.second, Self.first]
        ))

        #expect(state.displays.map(\.identity) == [Self.first, Self.second])
        #expect(state.displays.map(\.wallpaper) == [.numbered(4), .numbered(2)])
    }

    @Test func `carries the pause rules and what was sensed`() throws {
        let conditions = SensedConditions(sensedAt: Moment.launch, coveredDisplays: [Self.first], onBattery: true)
        let rules = PauseRules(whenDesktopCovered: false, whenDisplayAsleepOrLocked: true, inLowPowerMode: false, onBattery: true)

        let state = try #require(try Self.make(Self.state { $0.pauseRules = rules }, conditions: conditions))

        #expect(state.pauseRules == rules)
        #expect(state.conditions == conditions)
        #expect(!state.isStopped)
    }

    // MARK: Generation

    static let showingTwo = state { $0.assignments[first] = .wallpaper(.numbered(2)) }

    @Test func `the first state is generation 1, even when it shows nothing, so the extension learns to show nothing`() throws {
        let state = try #require(try Self.make(Self.state { _ in }))

        #expect(state.generation == 1)
        #expect(state.displays.isEmpty)
    }

    @Test func `a change gives the next generation`() throws {
        let previous = try #require(try Self.make(Self.showingTwo))
        let paused = Self.showingTwo.settingPaused(true, for: Self.first)

        let next = try #require(try Self.make(paused, previous: previous))

        #expect(next.generation == previous.generation + 1)
        #expect(next.displays.map(\.userPaused) == [true])
    }

    @Test func `nothing new gives nothing, so the extension is not told twice`() throws {
        let previous = try #require(try Self.make(Self.showingTwo))

        #expect(try Self.make(Self.showingTwo, previous: previous) == nil)
    }

    @Test func `newly sensed conditions give a new state`() throws {
        let previous = try #require(try Self.make(Self.showingTwo))

        let next = try Self.make(Self.showingTwo, conditions: SensedConditions(sensedAt: Moment.launch), previous: previous)

        #expect(next?.generation == 2)
    }

    @Test func `a stopped state is followed by a live one, whatever else changed`() throws {
        let live = try #require(try Self.make(Self.showingTwo))
        let stopped = live.next { $0.isStopped = true }

        let resumed = try #require(try Self.make(Self.showingTwo, previous: stopped))

        #expect(!resumed.isStopped)
        #expect(resumed.generation == stopped.generation + 1)
        #expect(resumed.displays == live.displays)
    }
}
