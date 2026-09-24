import Foundation
import Testing
import LivepaperCore

struct CommandTests {
    static let ocean = WallpaperID.numbered(1)
    static let evening = PlaylistID.numbered(1)
    static let studio = DisplayIdentity.numbered(2)

    static func file(_ path: String) -> URL {
        URL(filePath: path)
    }

    // MARK: Every verb, both ways

    static let verbs: [Row<String, Command>] = [
        Row(
            "import one file",
            "livepaper://import?file=/Users/sam/Movies/Ocean.mov",
            .import([file("/Users/sam/Movies/Ocean.mov")], setEverywhere: false)
        ),
        Row(
            "import several, and set everywhere",
            "livepaper://import?file=/Users/sam/Movies/Ocean.mov&file=/Users/sam/Downloads/431960&set=all",
            .import([file("/Users/sam/Movies/Ocean.mov"), file("/Users/sam/Downloads/431960")], setEverywhere: true)
        ),
        Row(
            "a path with a space, an ampersand, a hash and a plus",
            "livepaper://import?file=/Users/sam/My%20Movies/Sea%20%26%20Sky%20%231%2B2.mov",
            .import([file("/Users/sam/My Movies/Sea & Sky #1+2.mov")], setEverywhere: false)
        ),
        // A file URL keeps its path decomposed, as the file system does, so that is the form rendered.
        Row(
            "a path outside ASCII, and an equals sign",
            "livepaper://import?file=/Users/sam/Movies/Cafe%CC%81%3Dnight.mov",
            .import([file("/Users/sam/Movies/Caf\u{E9}=night.mov")], setEverywhere: false)
        ),
        Row(
            "a folder keeps its slash",
            "livepaper://import?file=/Users/sam/Movies/",
            .import([file("/Users/sam/Movies/")], setEverywhere: false)
        ),
        Row("set a wallpaper everywhere", "livepaper://set?wallpaper=\(ocean)", .set(.wallpaper(ocean), on: .all)),
        Row(
            "set a playlist on one display",
            "livepaper://set?playlist=\(evening)&display=\(studio)",
            .set(.playlist(evening), on: .display(studio))
        ),
        Row("pause all", "livepaper://pause", .pause(.all)),
        Row("pause one display", "livepaper://pause?display=\(studio)", .pause(.display(studio))),
        Row("resume all", "livepaper://resume", .resume(.all)),
        Row("resume one display", "livepaper://resume?display=\(studio)", .resume(.display(studio))),
        Row("next everywhere", "livepaper://next", .next(.all)),
        Row("next on one display", "livepaper://next?display=\(studio)", .next(.display(studio))),
        Row("mute", "livepaper://mute", .mute),
        Row("unmute", "livepaper://unmute", .unmute),
        Row("the library window", "livepaper://library", .library),
        Row("Settings", "livepaper://settings", .settings),
        Row("diagnostics", "livepaper://diagnostics", .diagnostics),
        Row("status", "livepaper://status", .status),
    ]

    @Test(arguments: verbs)
    func `every verb parses and renders back to the same URL`(row: Row<String, Command>) throws {
        let url = try #require(URL(string: row.input))

        #expect(try Command(url: url) == row.expected)
        #expect(try Command(string: row.input) == row.expected)
        #expect(row.expected.url.absoluteString == row.input)
    }

    @Test func `every verb has a row`() {
        #expect(Set(Self.verbs.map(\.expected.verb)) == Set(Command.Verb.allCases))
    }

    static let alsoAccepted: [Row<String, Command>] = [
        Row("display=all, which is the default", "livepaper://pause?display=all", .pause(.all)),
        Row("set with display=all", "livepaper://set?wallpaper=\(ocean)&display=all", .set(.wallpaper(ocean), on: .all)),
        Row("keys in another order", "livepaper://import?set=all&file=/a.mov", .import([file("/a.mov")], setEverywhere: true)),
        Row(
            "the display before the playlist",
            "livepaper://set?display=\(studio)&playlist=\(evening)",
            .set(.playlist(evening), on: .display(studio))
        ),
        Row("a UUID in lower case", "livepaper://set?wallpaper=\(ocean.description.lowercased())", .set(.wallpaper(ocean), on: .all)),
        Row("the scheme in capitals, which is the same scheme", "LIVEPAPER://mute", .mute),
        Row("an empty query", "livepaper://mute?", .mute),
        Row(
            "a space the sender left unescaped",
            "livepaper://import?file=/My Movies/a.mov",
            .import([file("/My Movies/a.mov")], setEverywhere: false)
        ),
        Row(
            "a path outside ASCII, precomposed",
            "livepaper://import?file=/Users/sam/Movies/Caf%C3%A9%3Dnight.mov",
            .import([file("/Users/sam/Movies/Caf\u{E9}=night.mov")], setEverywhere: false)
        ),
    ]

    @Test(arguments: alsoAccepted)
    func `accepts another spelling of the same command`(row: Row<String, Command>) throws {
        #expect(try Command(string: row.input) == row.expected)
    }

    // MARK: Rejections

    static let rejected: [Row<String, CommandRejection>] = [
        Row("another scheme", "https://pause", .notLivepaper),
        Row("not a URL at all", "hello", .notLivepaper),
        Row("an empty line", "", .notLivepaper),
        Row("no verb", "livepaper://", .noVerb),
        Row("an unknown verb", "livepaper://play", .unknownVerb("play")),
        Row("a verb in capitals", "livepaper://PAUSE", .unknownVerb("PAUSE")),
        Row("a verb that runs something", "livepaper://open?file=/Applications/Calculator.app", .unknownVerb("open")),
        Row("a path", "livepaper://pause/now", .path("/now")),
        Row("a trailing slash is a path", "livepaper://pause/", .path("/")),
        Row("a path climbing out", "livepaper://set/../x", .path("/../x")),
        Row("a verb written as a path", "livepaper:pause", .path("pause")),
        Row("a fragment", "livepaper://pause#now", .fragment),
        Row("an empty fragment", "livepaper://mute#", .fragment),
        Row("a port", "livepaper://pause:1", .port),
        Row("a user name", "livepaper://sam@pause", .credentials),
        Row("a user name and a password", "livepaper://sam:secret@pause", .credentials),
        Row("a key the verb does not take", "livepaper://pause?file=/a.mov", .unknownKey(verb: .pause, key: "file")),
        Row("a key on a verb that takes none", "livepaper://mute?display=all", .unknownKey(verb: .mute, key: "display")),
        Row("status takes no key", "livepaper://status?verbose=1", .unknownKey(verb: .status, key: "verbose")),
        Row("import takes no display", "livepaper://import?file=/a.mov&display=all", .unknownKey(verb: .import, key: "display")),
        Row("an empty key", "livepaper://pause?&", .unknownKey(verb: .pause, key: "")),
        Row("a key in capitals", "livepaper://pause?Display=all", .unknownKey(verb: .pause, key: "Display")),
        Row("a display given twice", "livepaper://pause?display=all&display=all", .repeatedKey("display")),
        Row("set=all given twice", "livepaper://import?file=/a.mov&set=all&set=all", .repeatedKey("set")),
        Row("a wallpaper given twice", "livepaper://set?wallpaper=\(ocean)&wallpaper=\(ocean)", .repeatedKey("wallpaper")),
        Row("import with no file", "livepaper://import", .missingKey(verb: .import, key: "file")),
        Row("import with only set", "livepaper://import?set=all", .missingKey(verb: .import, key: "file")),
        Row("a relative file", "livepaper://import?file=Movies/a.mov", .relativeFile("Movies/a.mov")),
        Row("a file from the home shorthand", "livepaper://import?file=~/a.mov", .relativeFile("~/a.mov")),
        Row("a file URL is not a path", "livepaper://import?file=file:///Users/sam/a.mov", .relativeFile("file:///Users/sam/a.mov")),
        Row("an empty file", "livepaper://import?file=", .emptyFile),
        Row("a file with no value", "livepaper://import?file", .emptyFile),
        Row("an empty file among good ones", "livepaper://import?file=/a.mov&file=", .emptyFile),
        Row(
            "a NUL that would cut the path short",
            "livepaper://import?file=/a%00/../../x",
            .invalidValue(key: "file", value: "/a\u{0}/../../x")
        ),
        Row("set other than all", "livepaper://import?file=/a.mov&set=everywhere", .invalidValue(key: "set", value: "everywhere")),
        Row("set with no value", "livepaper://import?file=/a.mov&set", .invalidValue(key: "set", value: "")),
        Row("set names nothing", "livepaper://set", .needsWallpaperOrPlaylist),
        Row("set names only a display", "livepaper://set?display=all", .needsWallpaperOrPlaylist),
        Row(
            "set names a wallpaper and a playlist",
            "livepaper://set?wallpaper=\(ocean)&playlist=\(evening)",
            .needsWallpaperOrPlaylist
        ),
        Row("a wallpaper named by path", "livepaper://set?wallpaper=../x", .notAUUID(key: "wallpaper", value: "../x")),
        Row("a playlist named by name", "livepaper://set?playlist=Evening", .notAUUID(key: "playlist", value: "Evening")),
        Row("a wallpaper cannot be all", "livepaper://set?wallpaper=all", .notAUUID(key: "wallpaper", value: "all")),
        Row("a display named by name", "livepaper://set?wallpaper=\(ocean)&display=Studio", .notAUUID(key: "display", value: "Studio")),
        Row("an empty display", "livepaper://next?display=", .notAUUID(key: "display", value: "")),
        Row("a UUID with a brace", "livepaper://pause?display={\(studio)}", .notAUUID(key: "display", value: "{\(studio)}")),
    ]

    @Test(arguments: rejected)
    func `rejects anything else with a reason`(row: Row<String, CommandRejection>) {
        #expect(throws: row.expected) { try Command(string: row.input) }
        if let url = URL(string: row.input) {
            #expect(throws: row.expected) { try Command(url: url) }
        }
    }

    @Test(arguments: rejected)
    func `a rejection says why in a sentence`(row: Row<String, CommandRejection>) {
        let reason = row.expected.reason

        #expect(!reason.isEmpty)
        #expect(reason.first?.isUppercase == true || reason.first == "“")
        #expect(!reason.contains("\n"))
    }

    /// What the sender wrote that a rejection carries: anything, since any web page can open a link.
    static func written(_ rejection: CommandRejection) -> String? {
        switch rejection {
        case .unknownVerb(let text), .path(let text), .relativeFile(let text), .unknownKey(_, let text): text
        case .notAUUID(_, let text), .invalidValue(_, let text): text
        default: nil
        }
    }

    @Test(arguments: rejected)
    func `a rejection is logged by its kind, repeating nothing the sender wrote`(row: Row<String, CommandRejection>) {
        let kind = row.expected.kind

        #expect(!kind.isEmpty)
        #expect(!kind.contains("\n"))
        // A value as short as “all” is the grammar's own word, and in “wallpaper” besides.
        if let written = Self.written(row.expected), written.count > 3 {
            #expect(!kind.contains(written))
        }
    }

    @Test func `a rejection repeats a long value only in part`() {
        let junk = String(repeating: "x", count: 10_000)
        let rejection = CommandRejection.unknownVerb(junk)

        #expect(rejection.reason.count < 120)
    }
}
