import Foundation
import Testing
import LivepaperCore

struct EntryPointTests {
    static let movie = URL(filePath: "/Users/sam/Movies/Ocean.mov")
    static let item = URL(filePath: "/Users/sam/Downloads/431960/", directoryHint: .isDirectory)
    static let clip = URL(filePath: "/Users/sam/Movies/Forest.mp4")
    static let ocean = WallpaperID.numbered(1)
    static let forest = WallpaperID.numbered(2)

    struct Handed: Sendable {
        var door: EntryPoint
        var files: [URL]
    }

    static let handed: [Row<Handed, Command?>] = [
        Row("Services on a video imports and sets", Handed(door: .services, files: [movie]), .import([movie], setEverywhere: true)),
        Row(
            "Services on a Wallpaper Engine folder imports and sets",
            Handed(door: .services, files: [item]),
            .import([item], setEverywhere: true)
        ),
        Row(
            "a drop on the menu-bar item imports and sets",
            Handed(door: .menuBarDrop, files: [movie, clip]),
            .import([movie, clip], setEverywhere: true)
        ),
        Row("Open With imports alone", Handed(door: .openWith, files: [clip]), .import([clip], setEverywhere: false)),
        Row(
            "the Dock imports alone",
            Handed(door: .dock, files: [movie, item, clip]),
            .import([movie, item, clip], setEverywhere: false)
        ),
        Row("nothing handed over is no command", Handed(door: .services, files: []), nil),
        Row(
            "what is not a file is left out",
            Handed(door: .menuBarDrop, files: [URL(string: "https://example.com/a.mov")!, movie]),
            .import([movie], setEverywhere: true)
        ),
        Row("only what is not a file is no command", Handed(door: .dock, files: [URL(string: "https://example.com/a.mov")!]), nil),
        Row("the scheme hands over commands, not files", Handed(door: .urlScheme, files: [movie]), nil),
        Row("the socket hands over commands, not files", Handed(door: .commandSocket, files: [movie]), nil),
    ]

    @Test(arguments: handed)
    func `files handed to a door become an import`(row: Row<Handed, Command?>) {
        #expect(row.input.door.command(importing: row.input.files) == row.expected)
    }

    // MARK: Setting what resulted

    struct Imported: Sendable {
        var command: Command
        var resulting: [WallpaperID]
    }

    static let setting: [Row<Imported, WallpaperID?>] = [
        Row("one new wallpaper goes everywhere", Imported(command: .import([movie], setEverywhere: true), resulting: [ocean]), ocean),
        Row(
            "one wallpaper from two files, the second a duplicate of the first",
            Imported(command: .import([movie, clip], setEverywhere: true), resulting: [ocean, ocean]),
            ocean
        ),
        Row(
            "one wallpaper from a folder, the rest failing",
            Imported(command: .import([item], setEverywhere: true), resulting: [forest]),
            forest
        ),
        Row(
            "several wallpapers never set",
            Imported(command: .import([movie, clip], setEverywhere: true), resulting: [ocean, forest]),
            nil
        ),
        Row("nothing resulting sets nothing", Imported(command: .import([movie], setEverywhere: true), resulting: []), nil),
        Row("an import alone never sets", Imported(command: .import([movie], setEverywhere: false), resulting: [ocean]), nil),
        Row("another command never sets", Imported(command: .next(.all), resulting: [ocean]), nil),
    ]

    @Test(arguments: setting)
    func `sets everywhere only the one wallpaper that resulted`(row: Row<Imported, WallpaperID?>) {
        #expect(row.input.command.wallpaperToSetEverywhere(resulting: row.input.resulting) == row.expected)
    }

    // MARK: What each door takes

    @Test func `the scheme takes every verb but status`() throws {
        for verb in Command.Verb.allCases where verb != .status {
            let keys = verb == .import ? "?file=/a.mov" : verb == .set ? "?wallpaper=\(Self.ocean)" : ""
            let command = try Command(string: "livepaper://\(verb.rawValue)\(keys)")
            #expect(EntryPoint.urlScheme.accepts(command))
            #expect(try EntryPoint.urlScheme.command(from: command.url) == command)
        }
        #expect(!EntryPoint.urlScheme.accepts(.status))
        #expect(throws: CommandRejection.notThroughThisDoor(.status)) {
            try EntryPoint.urlScheme.command(from: Command.status.url)
        }
    }

    @Test func `the socket takes every verb`() throws {
        #expect(EntryPoint.commandSocket.accepts(.status))
        #expect(try EntryPoint.commandSocket.command(from: "livepaper://status") == .status)
        #expect(
            try EntryPoint.commandSocket.command(from: "livepaper://import?file=/a.mov&set=all")
                == .import([URL(filePath: "/a.mov")], setEverywhere: true)
        )
    }

    @Test func `a door still rejects what is not a command`() {
        #expect(throws: CommandRejection.notAUUID(key: "wallpaper", value: "../x")) {
            try EntryPoint.urlScheme.command(from: URL(string: "livepaper://set?wallpaper=../x")!)
        }
        #expect(throws: CommandRejection.notLivepaper) { try EntryPoint.commandSocket.command(from: "hello") }
    }

    @Test(arguments: [EntryPoint.services, .menuBarDrop, .openWith, .dock])
    func `a door for files takes imports only`(door: EntryPoint) {
        #expect(door.accepts(.import([Self.movie], setEverywhere: false)))
        #expect(!door.accepts(.pause(.all)))
        #expect(!door.accepts(.status))
    }

    // MARK: Confirming

    struct Arriving: Sendable {
        var door: EntryPoint
        var command: Command
    }

    static let confirming: [Row<Arriving, Bool>] = [
        Row(
            "an import through the scheme is confirmed first",
            Arriving(door: .urlScheme, command: .import([movie], setEverywhere: false)),
            true
        ),
        Row(
            "and one that would set everywhere",
            Arriving(door: .urlScheme, command: .import([movie], setEverywhere: true)),
            true
        ),
        Row(
            "an assignment through the scheme names only what the library has",
            Arriving(door: .urlScheme, command: .set(.wallpaper(ocean), on: .all)),
            false
        ),
        Row("a transport action through the scheme", Arriving(door: .urlScheme, command: .pause(.all)), false),
        Row("an import from the tool", Arriving(door: .commandSocket, command: .import([movie], setEverywhere: true)), false),
        Row(
            "Services, which the user chose in a menu",
            Arriving(door: .services, command: .import([movie], setEverywhere: true)),
            false
        ),
        Row("a drop, which the user made", Arriving(door: .menuBarDrop, command: .import([movie], setEverywhere: true)), false),
        Row("Open With", Arriving(door: .openWith, command: .import([movie], setEverywhere: false)), false),
        Row("the Dock", Arriving(door: .dock, command: .import([movie], setEverywhere: false)), false),
    ]

    @Test(arguments: confirming)
    func `only an import through the scheme is confirmed in the window first`(row: Row<Arriving, Bool>) {
        #expect(row.input.door.needsConfirmation(row.input.command) == row.expected)
    }
}
