import Foundation
import LivepaperCore

/// The imports under the library's grid, one row per candidate. The app feeds
/// it what happens and carries out the effects it answers: one import runs at
/// a time, the rest wait their turn.
public struct ImportList: Equatable, Sendable {
    /// How long a finished row stays to be seen: a toast's lifetime.
    public static let finishedLifetime: Duration = .seconds(5)

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// The name and, for a Wallpaper Engine item, the preview the row shows.
        public let candidate: ImportCandidate
        public var state: RowState
    }

    public enum RowState: Equatable, Sendable {
        case waiting
        /// The stage in words and how far through it the import is, nil when the stage cannot tell.
        case running(stage: ImportStage, words: String, fraction: Double?)
        case finished(Wallpaper, at: Date)
        /// Nothing was imported: it is already in the library as this wallpaper.
        case duplicate(of: Wallpaper, at: Date)
        /// Why, in words, and whether Retry can help.
        case failed(reason: String, canRetry: Bool)
    }

    public enum Effect: Equatable, Sendable {
        /// Start this row's import.
        case start(UUID, ImportCandidate)
        /// Drop this row's stream: that cancels the import.
        case cancel(UUID)
    }

    public private(set) var rows: [Row] = []

    /// The imports that finished or failed since the list was last quiet. Their rows
    /// leave after a while, and the count on the status line must not shrink with them.
    private var done = 0

    public init() {}

    /// Whether an import is running: the status line says so.
    public var isRunning: Bool {
        rows.contains(where: \.isRunning)
    }

    /// The running import's place and how many there are, done or to do, since the
    /// list was last quiet: "Importing 2 of 5". Nil when nothing is running.
    public var progress: (position: Int, count: Int)? {
        guard isRunning else { return nil }
        let toDo = rows.count { $0.isRunning || $0.state == .waiting }
        return (done + 1, done + toDo)
    }

    /// New rows go to the end. `ids` are the rows' identities, one per candidate.
    public mutating func enqueue(_ candidates: [ImportCandidate], ids: [UUID]) -> [Effect] {
        precondition(candidates.count == ids.count, "one id per candidate")
        rows += zip(ids, candidates).map { Row(id: $0, candidate: $1, state: .waiting) }
        return startNext()
    }

    /// What the running row's stream said. Anything for a row that is not running is late, and changes nothing.
    public mutating func received(_ event: ImportEvent, for id: UUID, at date: Date) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].isRunning else { return [] }
        switch event {
        case .progress(let progress):
            rows[index].state = .running(stage: progress.stage, words: stageWords(progress.stage), fraction: progress.fraction)
            return []
        case .finished(.imported(let wallpaper, _)):
            rows[index].state = .finished(wallpaper, at: date)
        case .finished(.duplicate(let wallpaper)):
            rows[index].state = .duplicate(of: wallpaper, at: date)
        }
        done += 1
        return startNext()
    }

    /// The running row's stream threw. A cancel is not a failure: the row goes. A failed
    /// row stays until Retry or `cancel`, so the time it failed is not kept.
    public mutating func failed(_ id: UUID, error: any Error, at _: Date) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].isRunning else { return [] }
        if error is CancellationError {
            rows.remove(at: index)
        } else {
            let words = importFailureWords(error)
            rows[index].state = .failed(reason: words.reason, canRetry: words.canRetry)
            done += 1
        }
        return startNext()
    }

    /// Takes the row away, whatever its state: a waiting or failed row is simply dismissed.
    public mutating func cancel(_ id: UUID) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = rows.remove(at: index)
        return removed.isRunning ? [.cancel(id)] + startNext() : []
    }

    /// A failed row waits again where it is. The list runs top to bottom, so it goes before the rows below it.
    public mutating func retry(_ id: UUID) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }), case .failed = rows[index].state else { return [] }
        rows[index].state = .waiting
        return startNext()
    }

    /// Finished and duplicate rows leave `finishedLifetime` after they finished. A failed row stays for its Retry.
    public mutating func tick(at date: Date) -> [Effect] {
        rows.removeAll { $0.leavesAt.map { $0 <= date } ?? false }
        return []
    }

    /// When a tick next has something to do, for the caller to schedule one.
    public var nextTick: Date? {
        rows.compactMap(\.leavesAt).min()
    }

    /// Starts the first waiting row, unless one is running. With none left, the list is quiet and the count starts again.
    private mutating func startNext() -> [Effect] {
        guard !isRunning else { return [] }
        guard let next = rows.firstIndex(where: { $0.state == .waiting }) else {
            done = 0
            return []
        }
        rows[next].state = .running(stage: .fingerprint, words: stageWords(.fingerprint), fraction: nil)
        return [.start(rows[next].id, rows[next].candidate)]
    }
}

extension ImportList.Row {
    fileprivate var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    fileprivate var leavesAt: Date? {
        switch state {
        case .finished(_, let date), .duplicate(_, let date): date.addingTimeInterval(ImportList.finishedLifetime / .seconds(1))
        case .waiting, .running, .failed: nil
        }
    }
}
