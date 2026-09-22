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

    /// The levels at which a window covers the desktop: the normal level and
    /// everything above it, the screen saver and the shielding window included.
    /// The desktop's own windows sit below.
    public static let coveringLevels = Int(CGWindowLevelForKey(.normalWindow))...
}

/// The displays whose desktop is fully covered: one window on screen at a
/// covering level, not owned by one of `ignoredOwners`, contains the display's
/// whole frame.
///
/// The owners to ignore are the app itself and the Dock: the Dock keeps a
/// display-sized window on every display, above the normal level, that covers
/// nothing. Several windows that cover a display between them do not count;
/// that is v1's known gap. A maximised window leaves the menu bar, where the
/// wallpaper shows through, so it does not count either.
nonisolated public func coveredDisplays(
    windows: [WindowListEntry],
    displays: [ConnectedDisplay],
    ignoringOwners ignoredOwners: Set<Int32>
) -> Set<DisplayIdentity> {
    let covering = windows.filter { !ignoredOwners.contains($0.ownerPID) && WindowListEntry.coveringLevels.contains($0.layer) }
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
