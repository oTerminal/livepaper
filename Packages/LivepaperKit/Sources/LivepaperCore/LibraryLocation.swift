import Foundation

public enum LibraryPathError: Error, Equatable, Sendable {
    case empty
    case absolute
    /// A step of the path that is not a plain name.
    case illegalComponent(String)
    case escapesRoot
}

/// Where the library is on disk (record 0002).
///
/// The home folder is the caller's to supply. Inside the extension's sandbox
/// the home-directory APIs return the container, so nothing in Core calls them.
public struct LibraryLocation: Equatable, Sendable {
    public let root: URL

    public init(home: URL) {
        root = home.appending(path: "Library/Application Support/Livepaper", directoryHint: .isDirectory).standardizedFileURL
    }

    /// The versioned manifest of the library, written by the app only.
    public var manifest: URL { root.appending(path: "library.json", directoryHint: .notDirectory) }

    /// What the extension is to show, replaced atomically by the app.
    public var renderState: URL { root.appending(path: "render-state.json", directoryHint: .notDirectory) }

    /// Where an import is built, on the same volume, so that committing it is a rename.
    public var staging: URL { root.appending(path: ".staging", directoryHint: .isDirectory) }

    /// Turns a path from the manifest or the render state into a URL inside the library.
    ///
    /// The extension may read the library and nothing else, so what reaches it
    /// is held to the names the library itself writes: steps of ASCII letters,
    /// digits, `.`, `-` and `_`, none starting with a dot. That leaves no room
    /// for parent steps, absolute paths, lookalike characters or anything that
    /// reads like a link. It is a check of the name only: Core does not touch
    /// the file system, so a caller that must rule out a real symlink resolves
    /// it and asks `contains` again.
    public func resolve(_ relative: String) throws(LibraryPathError) -> URL {
        guard !relative.isEmpty else { throw .empty }
        guard !relative.hasPrefix("/") else { throw .absolute }

        var url = root
        for component in relative.split(separator: "/", omittingEmptySubsequences: false) {
            guard Self.isPlainName(component) else { throw .illegalComponent(String(component)) }
            url.append(path: component, directoryHint: .notDirectory)
        }
        guard contains(url) else { throw .escapesRoot }
        return url
    }

    /// Whether a URL, once normalised, is the root or inside it.
    public func contains(_ url: URL) -> Bool {
        let inside = url.standardizedFileURL.pathComponents
        let base = root.pathComponents
        return inside.count >= base.count && Array(inside.prefix(base.count)) == base
    }

    private static func isPlainName(_ component: Substring) -> Bool {
        guard let first = component.unicodeScalars.first, first != "." else { return false }
        return component.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": true
            default: false
            }
        }
    }
}
