import Foundation
import Testing
@testable import LivepaperCore

/// Every test gets its own folder under the temporary directory, removed afterwards.
final class LibraryStoreTests {
    let directory: URL
    let store: FileLibraryStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LivepaperCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FileLibraryStore(manifest: directory.appending(path: "Livepaper/library.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// What `library-v1.0.json` says.
    static func fixtureLibrary() throws -> Library {
        try Library.of(
            Wallpaper(
                id: .numbered(1),
                name: "Ocean at Dusk",
                isFavourite: true,
                addedAt: Date(timeIntervalSince1970: 1_789_984_800.25),
                fingerprint: Fingerprint(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"),
                optimisedCopy: "wallpapers/AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov",
                poster: "wallpapers/AAAAAAAA-0000-0000-0000-000000000001/poster.heic",
                hoverPreview: "wallpapers/AAAAAAAA-0000-0000-0000-000000000001/hover.mov",
                details: WallpaperDetails(duration: 12.5, width: 3840, height: 2160, frameRate: 60, codec: "hevc", byteCount: 48_000_000),
                presentation: Presentation(fit: .fill, focalPoint: Point(x: 0.25, y: 0.5), zoom: 1.5, pan: Point(x: 0.1, y: -0.2)),
                volume: 0.4
            ),
            Wallpaper(
                id: .numbered(2),
                name: "Café Lights",
                addedAt: Date(timeIntervalSince1970: 1_789_985_100),
                fingerprint: Fingerprint(sha256: "60303ae22b998861bce3b28f33eec1be758a213c86c93c076dbe9f558c11c752"),
                optimisedCopy: "wallpapers/AAAAAAAA-0000-0000-0000-000000000002/wallpaper.mov",
                poster: "wallpapers/AAAAAAAA-0000-0000-0000-000000000002/poster.heic",
                details: WallpaperDetails(duration: 8, width: 1080, height: 1920, frameRate: 29.97, codec: "h264", byteCount: 9_500_000),
                presentation: Presentation(fit: .stretch)
            )
        )
    }

    private func damageManifest(_ damage: (Data) -> Data) throws {
        let data = try Data(contentsOf: store.manifest)
        try damage(data).write(to: store.manifest)
    }

    // MARK: Round trip

    @Test func `a saved library loads again`() throws {
        let library = try Library.of(.numbered(1), .numbered(2, name: "Café Lights", isFavourite: true))

        try store.save(library)

        #expect(try store.load() == library)
    }

    @Test func `a first launch, with no folder yet, loads an empty library`() throws {
        #expect(try store.load() == Library())
    }

    @Test func `each save replaces the one before`() throws {
        let one = try Library.of(.numbered(1))
        let two = try one.inserting(.numbered(2))

        try store.save(one)
        try store.save(two)

        #expect(try store.load() == two)
    }

    // MARK: Migration

    @Test func `the version 1.0 fixture still loads`() throws {
        try FileManager.default.createDirectory(at: store.manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixture.data("library-v1.0").write(to: store.manifest)

        #expect(try store.load() == Self.fixtureLibrary())
    }

    @Test func `a newer minor version loads, and its new fields are ignored`() throws {
        let json = try #require(String(bytes: try Library.of(.numbered(1)).encode(), encoding: .utf8))
            .replacing(#""minor" : 0"#, with: #""minor" : 4"#)
            .replacing(#""volume" : 0"#, with: #""volume" : 0, "tags" : ["calm"]"#)
        #expect(json.contains(#""minor" : 4"#) && json.contains("tags"))

        #expect(try Library.decode(Data(json.utf8)) == Library.of(.numbered(1)))
    }

    @Test func `a manifest from an unknown major version is refused, and the older manifest is not used instead`() throws {
        try store.save(try Library.of(.numbered(1)))
        try store.save(try Library.of(.numbered(1), .numbered(2)))
        try damageManifest { _ in Data(#"{"version":{"major":2,"minor":0},"wallpapers":[]}"#.utf8) }

        #expect(throws: SchemaError.unsupportedVersion(SchemaVersion(major: 2, minor: 0))) { try self.store.load() }
    }

    // MARK: Damage (Wallper's "library emptied on restart")

    static let damage: [Row<@Sendable (Data) -> Data, Void>] = [
        Row("cut short halfway", { $0.prefix($0.count / 2) }, ()),
        Row("cut down to nothing", { _ in Data() }, ()),
        Row("overwritten with something that is not a manifest", { _ in Data("[]".utf8) }, ()),
    ]

    @Test(arguments: damage)
    func `a damaged manifest loads the last good one instead of an empty library`(row: Row<@Sendable (Data) -> Data, Void>) throws {
        let lastGood = try Library.of(.numbered(1))
        try store.save(lastGood)
        try store.save(try lastGood.inserting(.numbered(2)))

        try damageManifest(row.input)

        #expect(try store.load() == lastGood)
    }

    @Test func `a damaged manifest with nothing to fall back on is an error, never an empty library`() throws {
        try store.save(try Library.of(.numbered(1)))

        try damageManifest { $0.prefix($0.count / 2) }

        #expect(throws: (any Error).self) { try self.store.load() }
    }

    @Test func `a manifest that went missing loads the last good one`() throws {
        let lastGood = try Library.of(.numbered(1))
        try store.save(lastGood)
        try store.save(try lastGood.inserting(.numbered(2)))

        try FileManager.default.removeItem(at: store.manifest)

        #expect(try store.load() == lastGood)
    }

    @Test func `saving over a damaged manifest keeps the last good one`() throws {
        let lastGood = try Library.of(.numbered(1))
        let latest = try Library.of(.numbered(1), .numbered(3))
        try store.save(lastGood)
        try store.save(try lastGood.inserting(.numbered(2)))
        try damageManifest { $0.prefix($0.count / 2) }

        try store.save(latest)
        #expect(try store.load() == latest)

        try damageManifest { $0.prefix($0.count / 2) }
        #expect(try store.load() == lastGood)
    }

    @Test func `nothing is written outside the manifest's folder`() throws {
        try store.save(try Library.of(.numbered(1)))
        try store.save(try Library.of(.numbered(1), .numbered(2)))

        let written = try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()

        #expect(written == ["Livepaper", "Livepaper/library.json", "Livepaper/library.previous.json"])
    }
}
