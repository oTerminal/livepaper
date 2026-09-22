import LivepaperCore
import LivepaperSystem
import Testing

struct CoveredDisplaysTests {
    // The built-in display, an external one to its right, and one above it:
    // global display space, points, y growing downwards, as the window list gives it.
    static let builtIn = ConnectedDisplay(
        identity: .numbered(1), displayID: 1, pixelSize: Size(width: 3600, height: 2338), frame: rect(0, 0, 1800, 1169)
    )
    static let external = ConnectedDisplay(
        identity: .numbered(2), displayID: 3, pixelSize: Size(width: 1920, height: 1080), frame: rect(1800, 0, 1920, 1080)
    )
    static let above = ConnectedDisplay(
        identity: .numbered(3), displayID: 4, pixelSize: Size(width: 1920, height: 1080), frame: rect(0, -1080, 1920, 1080)
    )
    static let displays = [builtIn, external, above]

    static let ownPID: Int32 = 100
    static let otherPID: Int32 = 200
    static let dockPID: Int32 = 300

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Rect {
        Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    static func window(_ bounds: Rect, layer: Int = 0, owner: Int32 = otherPID) -> WindowListEntry {
        WindowListEntry(bounds: bounds, layer: layer, ownerPID: owner)
    }

    static let rows: [Row<[WindowListEntry], Set<DisplayIdentity>>] = [
        Row("nothing on screen covers nothing", [], []),
        Row("a fullscreen app covers its display", [window(builtIn.frame)], [builtIn.identity]),
        Row("a fullscreen app on the external display covers only that one", [window(external.frame)], [external.identity]),
        Row("a fullscreen app on a display above the main one", [window(above.frame)], [above.identity]),
        Row(
            "a maximised window leaves the menu bar showing the wallpaper",
            [window(rect(0, 39, 1800, 1050))],
            []
        ),
        Row("a window larger than the display covers it", [window(rect(-10, -10, 1900, 1300))], [builtIn.identity]),
        Row("a window one point short of the display does not", [window(rect(0, 0, 1800, 1168))], []),
        Row("a window on another display does not cover this one", [window(rect(1900, 100, 800, 600))], []),
        Row(
            "one window across two displays covers both",
            [window(rect(0, 0, 3720, 1169))],
            [builtIn.identity, external.identity]
        ),
        Row("the app's own window does not count", [window(builtIn.frame, owner: ownPID)], []),
        Row(
            "the desktop's own windows are below the normal level",
            [window(builtIn.frame, layer: -2_147_483_624), window(builtIn.frame, layer: -2_147_483_603)],
            []
        ),
        Row("a floating panel as large as the display covers it", [window(builtIn.frame, layer: 3)], [builtIn.identity]),
        Row("the Dock's display-sized window does not cover it", [window(builtIn.frame, layer: 20, owner: dockPID)], []),
        Row("the Dock's windows never count, whatever their level", [window(builtIn.frame, layer: 27, owner: dockPID)], []),
        Row("someone else's window at the Dock's level covers it", [window(builtIn.frame, layer: 20)], [builtIn.identity]),
        Row("a display-sized window above the Dock's level covers it", [window(builtIn.frame, layer: 25)], [builtIn.identity]),
        Row("a screen saver covers its display", [window(builtIn.frame, layer: 1000)], [builtIn.identity]),
        Row(
            "two windows that tile do not cover it, v1's known gap",
            [window(rect(0, 0, 900, 1169)), window(rect(900, 0, 900, 1169))],
            []
        ),
    ]

    @Test(arguments: rows)
    func `a display is covered by one window that contains it`(row: Row<[WindowListEntry], Set<DisplayIdentity>>) {
        let covered = coveredDisplays(windows: row.input, displays: Self.displays, ignoringOwners: [Self.ownPID, Self.dockPID])

        #expect(covered == row.expected)
    }
}
