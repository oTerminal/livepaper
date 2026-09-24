import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// What the app hands the diagnostics report, and the name "Save…" gives it.
struct DiagnosticsInputsTests {
    static let shapes: [Row<WallpaperStoreShape, StoreShape>] = [
        Row(
            "a store read gives its counts",
            WallpaperStoreShape(store: .read(desktopEntries: 24, namingLivepaper: 24), keptCopyExists: true),
            StoreShape(desktopEntries: 24, namingLivepaper: 24, keptCopyExists: true)
        ),
        Row(
            "an unreadable store gives none",
            WallpaperStoreShape(store: .unreadable, keptCopyExists: false),
            StoreShape(desktopEntries: nil, namingLivepaper: nil, keptCopyExists: false)
        ),
        Row(
            "a store of an unknown shape gives none, and the kept copy still counts",
            WallpaperStoreShape(store: .unknownShape, keptCopyExists: true),
            StoreShape(desktopEntries: nil, namingLivepaper: nil, keptCopyExists: true)
        ),
    ]

    @Test(arguments: shapes)
    func `the report's store shape is the store's counts`(row: Row<WallpaperStoreShape, StoreShape>) {
        #expect(StoreShape(row.input) == row.expected)
    }

    @Test func `a saved report is plain text named by when it was made, in the user's time zone`() throws {
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 2026-09-24 13:05:09 UTC.
        let made = Date(timeIntervalSince1970: 1_790_255_109)

        #expect(DiagnosticsReport.fileName(madeAt: made, timeZone: london) == "Livepaper Diagnostics 2026-09-24 at 14.05.09.txt")
        #expect(DiagnosticsReport.fileName(madeAt: made, timeZone: tokyo) == "Livepaper Diagnostics 2026-09-24 at 22.05.09.txt")
    }
}
