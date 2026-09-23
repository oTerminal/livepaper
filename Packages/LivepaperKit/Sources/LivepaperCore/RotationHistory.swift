/// What one display's playlist showed this session, for Previous. Held in
/// memory and never persisted: a relaunch starts without one.
public struct RotationHistory: Equatable, Sendable {
    /// Oldest first.
    private var left: [WallpaperID] = []

    public init() {}

    /// Called before Next, or a rotation, moves the display away from `wallpaper`.
    /// Previous does not call it, so that pressing Previous again steps further back.
    public mutating func leaving(_ wallpaper: WallpaperID) {
        left.append(wallpaper)
    }

    /// The wallpaper to step back to: the last one left that the playlist still
    /// has and that is not showing, else the one before `current` in the
    /// playlist's order, wrapping. Nil for a playlist of fewer than two.
    public mutating func previous(in playlist: Playlist, current: WallpaperID?) -> WallpaperID? {
        let wallpapers = playlist.wallpapers
        guard wallpapers.count >= 2 else { return nil }
        while let last = left.popLast() {
            if last != current, wallpapers.contains(last) { return last }
        }
        guard let current, let index = wallpapers.firstIndex(of: current) else { return wallpapers.last }
        return wallpapers[(index + wallpapers.count - 1) % wallpapers.count]
    }
}
