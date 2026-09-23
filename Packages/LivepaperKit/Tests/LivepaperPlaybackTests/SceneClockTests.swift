import Foundation
import Testing
@testable import LivepaperPlayback

/// Scene time runs only while a scene is drawn, and a scene resumes where it stopped (record 0007).
struct SceneClockTests {
    enum Step: Sendable {
        case start
        case frame(at: Double)
        case stop
        case reset
    }

    static let rows: [Row<[Step], [Double]>] = [
        Row("the first frame is the scene's first moment", [.start, .frame(at: 100)], [0]),
        Row("frames are timed by when they are shown", [.start, .frame(at: 100), .frame(at: 100.5), .frame(at: 102)], [0, 0.5, 2]),
        Row(
            "a pause stops the time, and the next run carries on from it",
            [.start, .frame(at: 100), .frame(at: 101), .stop, .start, .frame(at: 500), .frame(at: 500.25)],
            [0, 1, 1, 1.25]
        ),
        Row(
            "a frame while stopped shows the time it stopped at",
            [.start, .frame(at: 10), .frame(at: 12), .stop, .frame(at: 90)],
            [0, 2, 2]
        ),
        Row("it never runs backwards", [.start, .frame(at: 10), .frame(at: 11), .frame(at: 10.5)], [0, 1, 1]),
        Row("a reset starts the scene again", [.start, .frame(at: 10), .frame(at: 13), .stop, .reset, .start, .frame(at: 40)], [0, 3, 0]),
    ]

    @Test(arguments: rows)
    func `scene time`(row: Row<[Step], [Double]>) {
        var clock = SceneClock()
        var times: [Double] = []
        for step in row.input {
            switch step {
            case .start: clock.start()
            case .frame(let moment): times.append(clock.time(forFrameAt: moment))
            case .stop: clock.stop()
            case .reset: clock.reset()
            }
        }

        #expect(times == row.expected)
    }

    @Test func `the watchdog's count is what was presented and committed over the window, against the scene's rate`() {
        let before = SceneTally(committed: 10, presented: 9)
        let after = SceneTally(committed: 70, presented: 12)

        let count = SceneTally.count(from: before, to: after, over: .seconds(2), framesPerSecond: 30)

        // Fed but not shown: a covered display, which the watchdog calls not composited rather than stalled.
        #expect(count == PictureCount(displayed: 3, expected: 60, fed: 60))
    }
}
