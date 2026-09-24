import Foundation
import LivepaperCore
import Testing

struct CommandOutcomeTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let unplugged = DisplayIdentity.numbered(3)
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: [.numbered(1), .numbered(2)], interval: .seconds(600), shuffle: false
    )

    // MARK: The displays a command names

    static let targets: [Row<DisplayTarget, Result<[DisplayIdentity], CommandRefusal>>] = [
        Row("all is every connected display, in their order", .all, .success([first, second])),
        Row("a connected display is itself", .display(second), .success([second])),
        Row("a display that is not connected is refused", .display(unplugged), .failure(.notConnected(unplugged))),
    ]

    @Test(arguments: targets)
    func `a command acts on connected displays only`(row: Row<DisplayTarget, Result<[DisplayIdentity], CommandRefusal>>) {
        #expect(Result { () throws(CommandRefusal) in try row.input.displays(connected: [Self.first, Self.second]) } == row.expected)
    }

    // MARK: What set names

    static let assignments: [Row<Assignment, CommandRefusal?>] = [
        Row("a wallpaper the library holds", .wallpaper(.numbered(1)), nil),
        Row("a wallpaper the library does not hold is refused", .wallpaper(.numbered(9)), .noSuchWallpaper(.numbered(9))),
        Row("a playlist there is", .playlist(evening.id), nil),
        Row("a playlist there is not is refused", .playlist(.numbered(9)), .noSuchPlaylist(.numbered(9))),
    ]

    @Test(arguments: assignments)
    func `set names only what the library holds`(row: Row<Assignment, CommandRefusal?>) throws {
        var state = AppState()
        state.playlists = [Self.evening]
        let library = try Library.of(.numbered(1), .numbered(2))

        let refusal: CommandRefusal?
        do throws(CommandRefusal) {
            try state.checking(row.input, in: library)
            refusal = nil
        } catch {
            refusal = error
        }

        #expect(refusal == row.expected)
    }

    // MARK: What next moves on

    struct Showing: Sendable {
        var own: [DisplayIdentity: Assignment] = [:]
        var applyToAll: Assignment?
        var target: DisplayTarget
    }

    static let movingOn: [Row<Showing, Result<[DisplayIdentity], CommandRefusal>>] = [
        Row(
            "all moves on each display showing a playlist, and leaves the rest",
            Showing(own: [second: .playlist(evening.id), first: .wallpaper(.numbered(1))], target: .all),
            .success([second])
        ),
        Row(
            "a playlist on All Displays moves every display on",
            Showing(applyToAll: .playlist(evening.id), target: .all),
            .success([first, second])
        ),
        Row(
            "all with no playlist showing is refused",
            Showing(own: [first: .wallpaper(.numbered(1))], target: .all),
            .failure(.noPlaylistShown(.all))
        ),
        Row("one display on a playlist", Showing(own: [first: .playlist(evening.id)], target: .display(first)), .success([first])),
        Row(
            "one display showing a wallpaper is refused",
            Showing(own: [first: .wallpaper(.numbered(1)), second: .playlist(evening.id)], target: .display(first)),
            .failure(.noPlaylistShown(.display(first)))
        ),
        Row(
            "a display that is not connected is refused",
            Showing(own: [unplugged: .playlist(evening.id)], target: .display(unplugged)),
            .failure(.notConnected(unplugged))
        ),
        Row(
            "a playlist that is gone moves nothing",
            Showing(own: [first: .playlist(.numbered(9))], target: .all),
            .failure(.noPlaylistShown(.all))
        ),
    ]

    @Test(arguments: movingOn)
    func `next moves on the displays that show a playlist`(row: Row<Showing, Result<[DisplayIdentity], CommandRefusal>>) {
        var state = AppState()
        state.playlists = [Self.evening]
        state.assignments = row.input.own
        state.applyToAll = row.input.applyToAll

        let connected = [Self.first, Self.second]

        let moving = Result { () throws(CommandRefusal) in try state.displaysMovingOn(row.input.target, connected: connected) }

        #expect(moving == row.expected)
    }

    static let reasons: [Row<CommandRefusal, String>] = [
        Row("a wallpaper", .noSuchWallpaper(.numbered(9)), "The library has no wallpaper AAAAAAAA-0000-0000-0000-000000000009"),
        Row("a playlist", .noSuchPlaylist(.numbered(9)), "There is no playlist BBBBBBBB-0000-0000-0000-000000000009"),
        Row("a display", .notConnected(unplugged), "Display DDDDDDDD-0000-0000-0000-000000000003 is not connected"),
        Row("no playlist anywhere", .noPlaylistShown(.all), "No display shows a playlist"),
        Row(
            "no playlist there",
            .noPlaylistShown(.display(first)),
            "Display DDDDDDDD-0000-0000-0000-000000000001 does not show a playlist"
        ),
        Row("an unreadable library", .libraryUnreadable, "The library could not be read, so Livepaper changes nothing"),
        Row("quitting", .quitting, "Livepaper is quitting"),
        Row("still starting, after the wait", .stillStarting, "Livepaper is still starting; try again in a moment"),
    ]

    @Test(arguments: reasons)
    func `a refusal says why in a sentence`(row: Row<CommandRefusal, String>) {
        #expect(row.input.reason == row.expected)
        #expect(CommandReply.refused(row.input) == .refused(reason: row.expected))
    }

    // MARK: An import's reply

    static let movie = URL(filePath: "/Users/sam/Movies/Ocean.mov")

    struct Imported: Sendable {
        var setEverywhere = false
        var sources: [ImportedSource]
    }

    static let ocean = ImportedSource.imported(.numbered(1), name: "Ocean")
    static let forest = ImportedSource.imported(.numbered(2), name: "Forest")
    static let oceanAgain = ImportedSource.alreadyThere(.numbered(1), name: "Ocean")
    static let broken = ImportedSource.notImported(name: "Broken", reason: "It has no picture to play")

    static let imports: [Row<Imported, CommandReply>] = [
        Row("one imported", Imported(sources: [ocean]), .done(message: "Imported “Ocean”.")),
        Row("one already there", Imported(sources: [oceanAgain]), .done(message: "“Ocean” is already in the library.")),
        Row(
            "each source a line, in order",
            Imported(sources: [ocean, broken, oceanAgain]),
            .done(message: "Imported “Ocean”.\n“Broken” was not imported. It has no picture to play.\n“Ocean” is already in the library.")
        ),
        Row(
            "one imported and set",
            Imported(setEverywhere: true, sources: [ocean]),
            .done(message: "Imported “Ocean”.\nSet “Ocean” on every display.")
        ),
        Row(
            "one already there and set",
            Imported(setEverywhere: true, sources: [oceanAgain]),
            .done(message: "“Ocean” is already in the library.\nSet “Ocean” on every display.")
        ),
        Row(
            "the same wallpaper twice is one, and set",
            Imported(setEverywhere: true, sources: [ocean, oceanAgain]),
            .done(message: "Imported “Ocean”.\n“Ocean” is already in the library.\nSet “Ocean” on every display.")
        ),
        Row(
            "a failure beside one wallpaper still sets it",
            Imported(setEverywhere: true, sources: [broken, ocean]),
            .done(message: "“Broken” was not imported. It has no picture to play.\nImported “Ocean”.\nSet “Ocean” on every display.")
        ),
        Row(
            "several wallpapers set none",
            Imported(setEverywhere: true, sources: [ocean, forest]),
            .done(message: "Imported “Ocean”.\nImported “Forest”.\nNothing was set on every display: the import made 2 wallpapers.")
        ),
        Row(
            "nothing imported is refused",
            Imported(setEverywhere: true, sources: [broken]),
            .refused(reason: "“Broken” was not imported. It has no picture to play.")
        ),
        Row("nothing found is refused", Imported(sources: []), .refused(reason: "Nothing to import was found")),
    ]

    @Test(arguments: imports)
    func `an import answers what each source came to, and what was set`(row: Row<Imported, CommandReply>) {
        let command = Command.import([Self.movie], setEverywhere: row.input.setEverywhere)

        #expect(command.importReply(row.input.sources) == row.expected)
    }

    @Test func `a source's wallpaper is the one it made or already was`() {
        #expect(Self.ocean.wallpaper == .numbered(1))
        #expect(Self.oceanAgain.wallpaper == .numbered(1))
        #expect(Self.broken.wallpaper == nil)
    }

    @Test func `a source not imported is said in the one sentence the reply and onboarding's card share`() {
        #expect(Self.broken.line == "“Broken” was not imported. It has no picture to play.")
    }

    static let summaries: [Row<[ImportedSource], String>] = [
        Row("nothing found", [], "nothing found"),
        Row("each outcome counted", [ocean, broken, oceanAgain, forest], "2 imported, 1 already in the library, 1 not imported"),
        Row("an outcome that did not happen is left out", [broken, broken], "2 not imported"),
    ]

    @Test(arguments: summaries)
    func `an import is logged by counts, never by its files' names`(row: Row<[ImportedSource], String>) {
        let summary = ImportedSource.summary(of: row.input)

        #expect(summary == row.expected)
        for name in ["Ocean", "Forest", "Broken"] {
            #expect(!summary.contains(name))
        }
    }

    // MARK: Next's reply

    @Test func `next answers what each display it moved on shows now`() {
        let reply = CommandReply.movedOn([("Built-in Retina Display", "Northern Lights"), ("Studio Display", nil)])

        #expect(reply == .done(message: "Built-in Retina Display now shows “Northern Lights”.\nStudio Display moved on."))
    }
}
