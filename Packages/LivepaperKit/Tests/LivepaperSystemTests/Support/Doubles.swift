import Foundation
import LivepaperCore
import LivepaperSystem

/// A wall clock that moves only when told to, and makes the calls that fall due on the way.
@MainActor
final class ManualWallClock: WallClock {
    private struct Call {
        let number: Int
        let at: Date
        let action: @MainActor () -> Void
    }

    private(set) var now: Date
    private var calls: [Call] = []
    private var made = 0

    init(now: Date = Moment.launch) {
        self.now = now
    }

    func schedule(at date: Date, _ action: @escaping @MainActor () -> Void) -> ScheduledCall {
        made += 1
        let number = made
        calls.append(Call(number: number, at: date, action: action))
        return ScheduledCall { [weak self] in self?.calls.removeAll { $0.number == number } }
    }

    /// The calls waiting to be made.
    var scheduled: [Date] { calls.map(\.at).sorted() }

    /// Moves to `date`, making each call that falls due on the way at its own time, earliest first.
    func advance(to date: Date) {
        while let due = calls.filter({ $0.at <= date }).min(by: { $0.at < $1.at }) {
            calls.removeAll { $0.number == due.number }
            now = max(now, due.at)
            due.action()
        }
        now = max(now, date)
    }

    func advance(toSecond seconds: TimeInterval) {
        advance(to: Moment.after(seconds))
    }
}

/// Remembers what was posted, and delivers what the extension would post.
@MainActor
final class RecordingNotifier: DarwinNotifying {
    struct Post: Equatable, CustomStringConvertible {
        var name: String
        var state: UInt64?

        var description: String { state.map { "\(name) \($0)" } ?? name }
    }

    private(set) var posts: [Post] = []
    private var handlers: [DarwinNotification: @MainActor (UInt64) -> Void] = [:]
    var refusesToObserve = false

    func post(_ notification: DarwinNotification, state: UInt64?) {
        posts.append(Post(name: notification.name, state: state))
    }

    func observe(_ notification: DarwinNotification, _ handler: @escaping @MainActor (UInt64) -> Void) -> Bool {
        guard !refusesToObserve else { return false }
        handlers[notification] = handler
        return true
    }

    func stopObserving(_ notification: DarwinNotification) {
        handlers[notification] = nil
    }

    func isObserving(_ notification: DarwinNotification) -> Bool {
        handlers[notification] != nil
    }

    /// The extension posting a heartbeat.
    func deliver(_ heartbeat: Heartbeat) {
        handlers[HostNotification.heartbeat]?(heartbeat.packed)
    }

    func posts(of notification: DarwinNotification) -> [Post] {
        posts.filter { $0.name == notification.name }
    }
}

/// Restarts nothing, and says when it was asked to.
@MainActor
final class FakeAgentRestarter: AgentRestarting {
    private(set) var restarts = 0
    /// Yields the number of each restart as it is asked for.
    let asked: AsyncStream<Int>
    private let continuation: AsyncStream<Int>.Continuation

    init() {
        (asked, continuation) = AsyncStream.makeStream()
    }

    func restartAgent() async -> AgentRestartOutcome {
        restarts += 1
        continuation.yield(restarts)
        return .restarted(previous: 100, current: 101)
    }
}

extension Moment {
    /// Milliseconds since launch, so that times made by adding durations compare exactly.
    static func millisecond(of date: Date) -> Int {
        Int((date.timeIntervalSince(launch) * 1000).rounded())
    }
}

/// A folder of the test's own under the temporary directory, removed when the test lets go of it.
final class TemporaryFolder: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LivepaperSystemTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
