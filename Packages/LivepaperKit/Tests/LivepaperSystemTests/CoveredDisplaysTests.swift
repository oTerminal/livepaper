import CoreGraphics
import LivepaperCore
import LivepaperSystem
import Testing

struct CoveredDisplaysTests {
    // The built-in display, with a camera housing, an external one to its right,
    // and one above it: global display space, points, y growing downwards, as
    // the window list gives it. The built-in's numbers are a MacBook's, macOS 27:
    // a 38 pt safe-area inset at the top, and a menu bar 39 pt tall.
    static let builtIn = ConnectedDisplay(
        identity: .numbered(1),
        displayID: 1,
        pixelSize: Size(width: 3600, height: 2338),
        frame: rect(0, 0, 1800, 1169),
        topSafeAreaInset: 38
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
    static let windowServerPID: Int32 = 400
    static let loginwindowPID: Int32 = 500
    static let shieldLevel = Int(CGShieldingWindowLevel())

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Rect {
        Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    static func window(_ bounds: Rect, layer: Int = 0, owner: Int32 = otherPID) -> WindowListEntry {
        WindowListEntry(bounds: bounds, layer: layer, ownerPID: owner)
    }

    // The built-in's menu bar and the Dock's window, as the window list gives them.
    static let menuBar = window(rect(0, 0, 1800, 39), layer: 24, owner: windowServerPID)
    static let dock = window(builtIn.frame, layer: 20, owner: dockPID)

    static let rows: [Row<[WindowListEntry], Set<DisplayIdentity>>] = [
        Row("nothing on screen covers nothing", [], []),
        Row("a fullscreen app covers its display", [window(builtIn.frame)], [builtIn.identity]),
        Row(
            "a fullscreen app below a camera housing covers its display, the strip beside the housing black",
            [menuBar, window(rect(0, 39, 1800, 1130))],
            [builtIn.identity]
        ),
        Row(
            "the same window on a display without a camera housing leaves wallpaper above it",
            [window(rect(1800, 39, 1920, 1041))],
            []
        ),
        Row(
            "a window that starts below the menu bar leaves wallpaper above it",
            [menuBar, window(rect(0, 40, 1800, 1129))],
            []
        ),
        Row("a fullscreen app on the external display covers only that one", [window(external.frame)], [external.identity]),
        Row("a fullscreen app on a display above the main one", [window(above.frame)], [above.identity]),
        Row(
            "a zoomed window stops at the Dock and leaves the menu bar showing the wallpaper",
            [menuBar, dock, window(rect(0, 39, 1800, 1050))],
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
        Row("the app's own fullscreen window below a camera housing does not count", [window(rect(0, 39, 1800, 1130), owner: ownPID)], []),
        Row(
            "the desktop's own windows are below the normal level",
            [window(builtIn.frame, layer: -2_147_483_624), window(builtIn.frame, layer: -2_147_483_603)],
            []
        ),
        Row("a floating panel as large as the display covers it", [window(builtIn.frame, layer: 3)], [builtIn.identity]),
        Row("the Dock's display-sized window does not cover it", [menuBar, dock], []),
        Row("the Dock's windows never count, whatever their level", [window(builtIn.frame, layer: 27, owner: dockPID)], []),
        Row("someone else's window at the Dock's level covers it", [window(builtIn.frame, layer: 20)], [builtIn.identity]),
        Row("a display-sized window above the Dock's level covers it", [window(builtIn.frame, layer: 25)], [builtIn.identity]),
        Row("a screen saver covers its display", [window(builtIn.frame, layer: 1000)], [builtIn.identity]),
        Row(
            "the lock screen's shield, still listed a second after unlocking, covers nothing",
            [
                window(builtIn.frame, layer: shieldLevel, owner: loginwindowPID),
                window(external.frame, layer: shieldLevel, owner: loginwindowPID),
            ],
            []
        ),
        Row("loginwindow's windows never count, whatever their level", [window(builtIn.frame, owner: loginwindowPID)], []),
        Row("someone else's window at the shield's level covers it", [window(builtIn.frame, layer: shieldLevel)], [builtIn.identity]),
        Row(
            "two windows that tile do not cover it, v1's known gap",
            [window(rect(0, 0, 900, 1169)), window(rect(900, 0, 900, 1169))],
            []
        ),
        Row(
            "two windows that tile below a camera housing do not cover it either",
            [menuBar, window(rect(0, 39, 900, 1130)), window(rect(900, 39, 900, 1130))],
            []
        ),
    ]

    @Test(arguments: rows)
    func `a display is covered by one window that contains it`(row: Row<[WindowListEntry], Set<DisplayIdentity>>) {
        let covered = coveredDisplays(
            windows: row.input, displays: Self.displays, ignoringOwners: [Self.ownPID, Self.dockPID, Self.loginwindowPID]
        )

        #expect(covered == row.expected)
    }
}
