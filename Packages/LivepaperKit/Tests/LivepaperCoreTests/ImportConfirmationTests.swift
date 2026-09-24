import Foundation
import LivepaperCore
import Testing

struct ImportConfirmationTests {
    static let home = "/Users/sam"

    static func file(_ path: String) -> URL {
        URL(filePath: path)
    }

    struct Asked: Sendable {
        var files: [URL]
        var setEverywhere = false
    }

    static let intro = "A livepaper:// link asks Livepaper to import this. "
        + "Any app or web page can open such a link, so import only what you expected."
    static let introForSeveral = intro.replacingOccurrences(of: "this", with: "these")

    static let rows: [Row<Asked, ImportConfirmation>] = [
        Row(
            "one file, named in the title, its path under the home folder shortened",
            Asked(files: [file("/Users/sam/Movies/Ocean.mov")]),
            ImportConfirmation(title: "Import “Ocean.mov”?", message: intro + "\n\n~/Movies/Ocean.mov", importTitle: "Import")
        ),
        Row(
            "one file to set everywhere says so",
            Asked(files: [file("/Users/sam/Movies/Ocean.mov")], setEverywhere: true),
            ImportConfirmation(
                title: "Import “Ocean.mov” and set it on every display?",
                message: intro + "\n\n~/Movies/Ocean.mov",
                importTitle: "Import and Set"
            )
        ),
        Row(
            "several files, counted, a path outside the home folder kept whole",
            Asked(files: [file("/Users/sam/Movies/Ocean.mov"), file("/Volumes/Loops/Forest.mp4")]),
            ImportConfirmation(
                title: "Import 2 files?",
                message: introForSeveral + "\n\n~/Movies/Ocean.mov\n/Volumes/Loops/Forest.mp4",
                importTitle: "Import"
            )
        ),
        Row(
            "several to set everywhere: only one wallpaper resulting is set",
            Asked(files: [file("/Users/sam/a.mov"), file("/Users/sam/b.mov")], setEverywhere: true),
            ImportConfirmation(
                title: "Import 2 files?",
                message: introForSeveral + "\n\n~/a.mov\n~/b.mov" + "\n\nIf they make one wallpaper, it is set on every display.",
                importTitle: "Import"
            )
        ),
        Row(
            "past five, the rest are counted",
            Asked(files: (1...7).map { file("/Users/sam/\($0).mov") }),
            ImportConfirmation(
                title: "Import 7 files?",
                message: introForSeveral + "\n\n" + (1...5).map { "~/\($0).mov" }.joined(separator: "\n") + "\nand 2 more",
                importTitle: "Import"
            )
        ),
        Row(
            "a home folder whose name another folder starts with is not shortened there",
            Asked(files: [file("/Users/samantha/Ocean.mov")]),
            ImportConfirmation(title: "Import “Ocean.mov”?", message: intro + "\n\n/Users/samantha/Ocean.mov", importTitle: "Import")
        ),
    ]

    @Test(arguments: rows)
    func `an import through the scheme names what it would import before it does`(row: Row<Asked, ImportConfirmation>) {
        let confirmation = ImportConfirmation(files: row.input.files, setEverywhere: row.input.setEverywhere, home: Self.home)

        #expect(confirmation == row.expected)
    }
}
