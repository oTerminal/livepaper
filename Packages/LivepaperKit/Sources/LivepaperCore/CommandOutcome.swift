import Foundation

/// Why the app does not run a command a door sent it: what the command names
/// is not there, or nothing can be changed now (M7). The app logs `reason`,
/// and the socket replies with it.
public enum CommandRefusal: Error, Hashable, Sendable, CustomStringConvertible {
    case noSuchWallpaper(WallpaperID)
    case noSuchPlaylist(PlaylistID)
    /// A display that is not connected now.
    case notConnected(DisplayIdentity)
    /// `next` names displays none of which shows a playlist.
    case noPlaylistShown(DisplayTarget)
    /// Nothing is written while the library could not be read.
    case libraryUnreadable
    case quitting

    public var reason: String {
        switch self {
        case .noSuchWallpaper(let id): "The library has no wallpaper \(id)"
        case .noSuchPlaylist(let id): "There is no playlist \(id)"
        case .notConnected(let display): "Display \(display) is not connected"
        case .noPlaylistShown(.all): "No display shows a playlist"
        case .noPlaylistShown(.display(let display)): "Display \(display) does not show a playlist"
        case .libraryUnreadable: "The library could not be read, so Livepaper changes nothing"
        case .quitting: "Livepaper is quitting"
        }
    }

    public var description: String { reason }
}

extension CommandReply {
    public static func refused(_ refusal: CommandRefusal) -> CommandReply {
        .refused(reason: refusal.reason)
    }
}

// MARK: - What a command acts on

extension DisplayTarget {
    /// The connected displays this names, in their order: every one for `all`,
    /// else the one it names, which must be connected.
    public func displays(connected: [DisplayIdentity]) throws(CommandRefusal) -> [DisplayIdentity] {
        switch self {
        case .all: return connected
        case .display(let display):
            guard connected.contains(display) else { throw .notConnected(display) }
            return [display]
        }
    }
}

extension AppState {
    /// Throws unless the library holds the wallpaper, or this state the
    /// playlist: a command names only what is there.
    public func checking(_ assignment: Assignment, in library: Library) throws(CommandRefusal) {
        switch assignment {
        case .wallpaper(let id): guard library[id] != nil else { throw .noSuchWallpaper(id) }
        case .playlist(let id): guard self[playlist: id] != nil else { throw .noSuchPlaylist(id) }
        }
    }

    /// `next`: the displays among those named that show a playlist, in the
    /// connected displays' order, paused or not (Next works on a paused
    /// display and leaves it paused). Refused when none does.
    public func displaysMovingOn(_ target: DisplayTarget, connected: [DisplayIdentity]) throws(CommandRefusal) -> [DisplayIdentity] {
        let moving = try target.displays(connected: connected).filter { display in
            guard case .playlist(let id)? = assignment(for: display) else { return false }
            return self[playlist: id] != nil
        }
        guard !moving.isEmpty else { throw .noPlaylistShown(target) }
        return moving
    }
}

// MARK: - Replies

/// What one source of an import a command asked for came to, for its reply.
public enum ImportedSource: Hashable, Sendable {
    case imported(WallpaperID, name: String)
    /// Nothing was imported: the library has it already, as this wallpaper.
    case alreadyThere(WallpaperID, name: String)
    /// Skipped, failed or cancelled. `reason` is a sentence about "it", as the import's toasts say it.
    case notImported(name: String, reason: String)

    /// The wallpaper it made, or already was.
    public var wallpaper: WallpaperID? {
        switch self {
        case .imported(let id, _), .alreadyThere(let id, _): id
        case .notImported: nil
        }
    }

    var line: String {
        switch self {
        case .imported(_, let name): "Imported “\(name)”."
        case .alreadyThere(_, let name): "“\(name)” is already in the library."
        case .notImported(let name, let reason): "“\(name)” was not imported. \(reason)."
        }
    }
}

extension Command {
    /// The reply to an import once every source is done: a line for each, in
    /// order, and whether the one wallpaper that resulted went on every
    /// display (`wallpaperToSetEverywhere(resulting:)`). Refused when nothing
    /// resulted, so that the tool exits with its refusal.
    public func importReply(_ sources: [ImportedSource]) -> CommandReply {
        let resulting = sources.compactMap(\.wallpaper)
        guard !resulting.isEmpty else {
            return .refused(reason: sources.isEmpty ? "Nothing to import was found" : sources.map(\.line).joined(separator: "\n"))
        }
        var lines = sources.map(\.line)
        if let set = wallpaperToSetEverywhere(resulting: resulting) {
            let name = sources.first { $0.wallpaper == set }.map(Self.name) ?? set.description
            lines.append("Set “\(name)” on every display.")
        } else if case .import(_, setEverywhere: true) = self {
            lines.append("Nothing was set on every display: the import made \(Set(resulting).count) wallpapers.")
        }
        return .done(message: lines.joined(separator: "\n"))
    }

    private static func name(of source: ImportedSource) -> String {
        switch source {
        case .imported(_, let name), .alreadyThere(_, let name), .notImported(let name, _): name
        }
    }
}

extension CommandReply {
    /// `next`'s reply: what each display it moved on shows now, by the
    /// display's name and the wallpaper's; nil when the display shows none.
    public static func movedOn(_ displays: [(display: String, wallpaper: String?)]) -> CommandReply {
        .done(message: displays.map { display, wallpaper in
            wallpaper.map { "\(display) now shows “\($0)”." } ?? "\(display) moved on."
        }.joined(separator: "\n"))
    }
}
