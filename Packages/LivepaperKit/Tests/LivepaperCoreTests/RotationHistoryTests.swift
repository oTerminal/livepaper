import Foundation
import Testing
import LivepaperCore

struct RotationHistoryTests {
    static func playlist(_ numbers: [Int]) -> Playlist {
        Playlist(id: .numbered(1), name: "Evening", wallpapers: numbers.map(WallpaperID.numbered), interval: .seconds(600), shuffle: true)
    }

    struct Walk: Sendable {
        /// The wallpapers left, in the order Next left them.
        var left: [Int]
        var playlist: [Int]
        var current: Int?
    }

    static let rows: [Row<Walk, Int?>] = [
        Row("the wallpaper shown before this one", Walk(left: [3, 1], playlist: [1, 2, 3], current: 2), 1),
        Row("one that has left the playlist is passed over", Walk(left: [3, 1], playlist: [2, 3], current: 2), 3),
        Row("the one showing is passed over", Walk(left: [1, 2], playlist: [1, 2, 3], current: 2), 1),
        Row("with no history, the one before in the playlist's order", Walk(left: [], playlist: [1, 2, 3], current: 2), 1),
        Row("with no history, before the first is the last", Walk(left: [], playlist: [1, 2, 3], current: 1), 3),
        Row("with no history and nothing showing, the last", Walk(left: [], playlist: [1, 2, 3], current: nil), 3),
        Row("a playlist of one has no previous", Walk(left: [2], playlist: [1], current: 1), nil),
        Row("an empty playlist has no previous", Walk(left: [2], playlist: [], current: nil), nil),
    ]

    @Test(arguments: rows)
    func `stepping back goes through what this session showed`(row: Row<Walk, Int?>) {
        var history = RotationHistory()
        for number in row.input.left {
            history.leaving(.numbered(number))
        }

        let previous = history.previous(in: Self.playlist(row.input.playlist), current: row.input.current.map(WallpaperID.numbered))

        #expect(previous == row.expected.map(WallpaperID.numbered))
    }

    @Test func `pressing Previous again steps further back`() {
        var history = RotationHistory()
        let playlist = Self.playlist([1, 2, 3, 4])
        for number in [4, 1, 3] {
            history.leaving(.numbered(number))
        }

        let steps = [
            history.previous(in: playlist, current: .numbered(2)),
            history.previous(in: playlist, current: .numbered(3)),
            history.previous(in: playlist, current: .numbered(1)),
            history.previous(in: playlist, current: .numbered(4)),
        ]

        #expect(steps == [3, 1, 4, 3].map(WallpaperID.numbered))
    }
}
