import Foundation
import LivepaperCore
import LivepaperImport
import Testing

/// What a command's import tells its sender: each row, skipped source and
/// unsearchable URL as an `ImportedSource`, in the words the toasts use.
struct ImportedSourceTests {
    @Test func `a row is nothing until it is done, then what it came to`() {
        var list = ImportList()
        _ = list.enqueue([.numbered(1), .numbered(2), .numbered(3)], ids: [.row(1), .row(2), .row(3)])
        let waiting = list.rows.map(\.importedSource)

        _ = list.received(.finished(.imported(.numbered(1), ImportListTests.report)), for: .row(1), at: Moment.launch)
        _ = list.received(.finished(.duplicate(of: .numbered(7))), for: .row(2), at: Moment.launch)
        _ = list.failed(.row(3), error: ImportError.rejected(.noVideo), at: Moment.launch)

        #expect(waiting == [nil, nil, nil])
        #expect(list.rows.map(\.importedSource) == [
            .imported(Wallpaper.numbered(1).id, name: "Harbour 1"),
            .alreadyThere(Wallpaper.numbered(7).id, name: "Harbour 7"),
            .notImported(name: "Harbour 3", reason: "It has no picture to play"),
        ])
    }

    @Test func `a skipped source, one that could not be searched, and one cancelled say why`() {
        let skipped = SkippedSource(url: URL(filePath: "/Users/tester/Downloads/431960"), reason: .wallpaperEngine(.runsCode("web")))

        #expect(ImportedSource.skipped(skipped) == .notImported(
            name: "431960",
            reason: "It is a web page for Wallpaper Engine, which runs code of its own; only video and scene items can be imported"
        ))
        #expect(
            ImportedSource.notImported(name: "Gone", error: DiscoverError.notFound(URL(filePath: "/Gone")))
                == .notImported(name: "Gone", reason: "It could not be found")
        )
        #expect(ImportedSource.cancelled(name: "Harbour 1") == .notImported(name: "Harbour 1", reason: "Its import was cancelled"))
    }
}
