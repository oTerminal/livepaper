import Foundation

/// What the library window asks before it runs an import a `livepaper://`
/// link asked for (`EntryPoint.needsConfirmation`): any app or web page can
/// open the scheme, so the user sees what would be imported, and from where,
/// and says Import or Cancel.
public struct ImportConfirmation: Equatable, Sendable {
    /// The most paths listed; the rest are counted.
    public static let listed = 5

    public var title: String
    public var message: String
    /// The button that imports; the other is Cancel.
    public var importTitle: String

    public init(title: String, message: String, importTitle: String) {
        self.title = title
        self.message = message
        self.importTitle = importTitle
    }

    /// `home` is the home folder's path, which a listed path is shortened to `~` under.
    public init(files: [URL], setEverywhere: Bool, home: String) {
        let one = files.count == 1
        if one, let file = files.first {
            let name = "“\(file.lastPathComponent)”"
            title = setEverywhere ? "Import \(name) and set it on every display?" : "Import \(name)?"
        } else {
            title = "Import \(files.count) files?"
        }
        importTitle = one && setEverywhere ? "Import and Set" : "Import"

        var paths = files.prefix(Self.listed).map { Self.shortened($0.path(percentEncoded: false), home: home) }
        if files.count > Self.listed { paths.append("and \(files.count - Self.listed) more") }
        var parts = [
            "A livepaper:// link asks Livepaper to import \(one ? "this" : "these"). "
                + "Any app or web page can open such a link, so import only what you expected.",
            paths.joined(separator: "\n"),
        ]
        if setEverywhere, !one { parts.append("If they make one wallpaper, it is set on every display.") }
        message = parts.joined(separator: "\n\n")
    }

    /// `~/Movies/Ocean.mov` for a path under the home folder; any other path whole.
    private static func shortened(_ path: String, home: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
