import CoreGraphics
import LivepaperCore

/// One on-screen window as the window list gives it without Screen Recording:
/// where it is, its level and its owner, never its name.
nonisolated public struct WindowListEntry: Equatable, Sendable {
    /// Global display space, in points, y growing downwards.
    public var bounds: Rect
    public var layer: Int
    public var ownerPID: Int32

    public init(bounds: Rect, layer: Int, ownerPID: Int32) {
        self.bounds = bounds
        self.layer = layer
        self.ownerPID = ownerPID
    }

    /// The levels at which a window covers the desktop: from the normal level
    /// up to the Dock's. The Dock keeps a display-sized window at its own level
    /// on every display, and the menu bar, status items and overlays sit above
    /// it, so counting those would call every display covered.
    public static let coveringLevels = Int(CGWindowLevelForKey(.normalWindow))..<Int(CGWindowLevelForKey(.dockWindow))
}

/// The displays whose desktop is fully covered: one window of someone else's,
/// on screen at a covering level, contains the display's whole frame.
///
/// Several windows that cover a display between them do not count; that is
/// v1's known gap. A maximised window leaves the menu bar, where the wallpaper
/// shows through, so it does not count either.
nonisolated public func coveredDisplays(
    windows: [WindowListEntry],
    displays: [ConnectedDisplay],
    ignoringOwner ownPID: Int32
) -> Set<DisplayIdentity> {
    let covering = windows.filter { $0.ownerPID != ownPID && WindowListEntry.coveringLevels.contains($0.layer) }
    return Set(
        displays
            .filter { display in covering.contains { $0.bounds.contains(display.frame) } }
            .map(\.identity)
    )
}

extension Rect {
    nonisolated func contains(_ other: Rect) -> Bool {
        origin.x <= other.origin.x && origin.y <= other.origin.y && maxX >= other.maxX && maxY >= other.maxY
    }
}
