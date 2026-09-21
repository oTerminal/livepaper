/// The choice of which wallpaper, or which playlist, a display shows.
public enum Assignment: Hashable, Sendable {
    case wallpaper(WallpaperID)
    case playlist(PlaylistID)
}

/// What each connected display shows.
///
/// A display keeps its saved assignment while it is unplugged, because `saved`
/// is never pruned here: an absent display is only left out of the result. A
/// display seen for the first time takes "apply to all", or nothing.
public func resolveAssignments(
    _ saved: [DisplayIdentity: Assignment], connected: [DisplayIdentity], applyToAll: Assignment?
) -> [DisplayIdentity: Assignment] {
    var shown: [DisplayIdentity: Assignment] = [:]
    for display in connected {
        shown[display] = saved[display] ?? applyToAll
    }
    return shown
}
