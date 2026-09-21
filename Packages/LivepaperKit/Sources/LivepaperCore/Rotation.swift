import Foundation

/// An ordered set of wallpapers that a display rotates through.
public struct Playlist: Equatable, Identifiable, Sendable {
    public let id: PlaylistID
    public var name: String
    public var wallpapers: [WallpaperID]
    /// How long each wallpaper shows before a tick moves on.
    public var interval: Duration
    public var shuffle: Bool

    public init(id: PlaylistID, name: String, wallpapers: [WallpaperID], interval: Duration, shuffle: Bool) {
        self.id = id
        self.name = name
        self.wallpapers = wallpapers
        self.interval = interval
        self.shuffle = shuffle
    }
}

/// Where one display is in its playlist.
public struct RotationState: Equatable, Sendable {
    /// The wallpaper the playlist last chose.
    public var current: WallpaperID?
    /// Where `current` was in the playlist when it was chosen, so that rotation
    /// can carry on from the same place after `current` is deleted.
    public var position: Int?
    /// The rest of the shuffled pass.
    public var upcoming: [WallpaperID]
    public var lastRotation: Date?

    public init(current: WallpaperID? = nil, position: Int? = nil, upcoming: [WallpaperID] = [], lastRotation: Date? = nil) {
        self.current = current
        self.position = position
        self.upcoming = upcoming
        self.lastRotation = lastRotation
    }
}

/// What can move a playlist on. Each carries its time: Core never reads the clock.
public enum RotationEvent: Equatable, Sendable {
    /// The rotation timer fired. Rotates only once the playlist's interval has passed.
    case tick(at: Date)
    case wake(at: Date)
    case login(at: Date)

    var date: Date {
        switch self {
        case .tick(let date), .wake(let date), .login(let date): date
        }
    }
}

/// Moves a playlist on. Returns the new state and the wallpaper to switch to,
/// or `nil` when the display should keep what it shows.
public func nextRotation(
    _ playlist: Playlist, _ state: RotationState, _ event: RotationEvent, rng: inout some RandomNumberGenerator
) -> (RotationState, WallpaperID?) {
    // A tick waits for the interval, unless what is showing has been deleted.
    let currentIsGone = state.current.map { !playlist.wallpapers.contains($0) } ?? false
    if case .tick(let now) = event, let last = state.lastRotation, !currentIsGone,
       now.elapsed(since: last) < playlist.interval {
        return (state, nil)
    }

    var next = state
    next.lastRotation = event.date
    // Wallpapers deleted since the pass was shuffled are never shown.
    next.upcoming = state.upcoming.filter(playlist.wallpapers.contains)

    guard let chosen = playlist.shuffle ? next.drawShuffled(from: playlist, rng: &rng) : next.following(in: playlist) else {
        return (next, nil)
    }
    next.position = playlist.wallpapers.firstIndex(of: chosen)
    guard chosen != state.current else { return (next, nil) }
    next.current = chosen
    return (next, chosen)
}

extension RotationState {
    /// In order: the wallpaper after the current one, wrapping. When the current
    /// one has been deleted, its old position now holds the one that followed it.
    fileprivate func following(in playlist: Playlist) -> WallpaperID? {
        let wallpapers = playlist.wallpapers
        guard !wallpapers.isEmpty else { return nil }
        if let current, let index = wallpapers.firstIndex(of: current) {
            return wallpapers[(index + 1) % wallpapers.count]
        }
        guard let position else { return wallpapers[0] }
        return wallpapers[position % wallpapers.count]
    }

    /// Shuffled: the next wallpaper of the pass. A new pass is shuffled when the
    /// last one runs out, and never starts with the wallpaper that is showing.
    fileprivate mutating func drawShuffled(from playlist: Playlist, rng: inout some RandomNumberGenerator) -> WallpaperID? {
        if upcoming.isEmpty {
            upcoming = shuffled(playlist.wallpapers, rng: &rng)
            if upcoming.count > 1, upcoming[0] == current {
                upcoming.swapAt(0, 1 + index(below: upcoming.count - 1, rng: &rng))
            }
        }
        return upcoming.isEmpty ? nil : upcoming.removeFirst()
    }
}

// Fisher-Yates, written out rather than `shuffled(using:)` so that a seed gives
// the same order on every toolchain. The modulo bias is below 2^-50 for any
// playlist that fits in memory.
private func shuffled(_ wallpapers: [WallpaperID], rng: inout some RandomNumberGenerator) -> [WallpaperID] {
    var result = wallpapers
    for last in stride(from: result.count - 1, to: 0, by: -1) {
        result.swapAt(last, index(below: last + 1, rng: &rng))
    }
    return result
}

private func index(below bound: Int, rng: inout some RandomNumberGenerator) -> Int {
    Int(rng.next() % UInt64(bound))
}
