import Foundation

/// A way into the app that is not its window (M7). Each turns what it is
/// handed into a `Command`, which the app model runs like any other.
public enum EntryPoint: Hashable, Sendable, CaseIterable {
    /// "Set as Live Wallpaper" in the Services menu, on files or folders.
    case services
    /// Files dropped on the menu-bar item.
    case menuBarDrop
    /// Open With in the Finder.
    case openWith
    /// Files dropped on the Dock icon, there only while the window is open, since the app is `LSUIElement`.
    case dock
    /// A `livepaper://` URL LaunchServices handed over: anything can open one, a web page included.
    case urlScheme
    /// A request line on the command socket, from the `livepaper` tool.
    case commandSocket

    /// What files handed to this door ask for: an import that sets everywhere
    /// from Services and the menu-bar drop, neither of which names a display,
    /// and an import alone from Open With and the Dock. Nil when nothing handed
    /// over is a file, and from the doors that hand over commands instead.
    public func command(importing files: [URL]) -> Command? {
        let files = files.filter(\.isFileURL)
        guard !files.isEmpty else { return nil }
        switch self {
        case .services, .menuBarDrop: return .import(files, setEverywhere: true)
        case .openWith, .dock: return .import(files, setEverywhere: false)
        case .urlScheme, .commandSocket: return nil
        }
    }

    /// Whether this door takes the command. `status` answers with JSON, which
    /// only the socket can carry back; a door for files takes only the import it makes.
    public func accepts(_ command: Command) -> Bool {
        switch self {
        case .services, .menuBarDrop, .openWith, .dock:
            if case .import = command { return true }
            return false
        case .urlScheme: return command != .status
        case .commandSocket: return true
        }
    }

    /// The command a URL handed to this door asks for, or why there is none.
    public func command(from url: URL) throws(CommandRejection) -> Command {
        try accepted(Command(url: url))
    }

    /// The command a request line asks for, or why there is none.
    public func command(from line: String) throws(CommandRejection) -> Command {
        try accepted(Command(string: line))
    }

    /// Whether the window asks the user before the command runs. An import
    /// through the scheme does, since any web page can open the scheme; every
    /// other door is the user's own act, and an assignment through the scheme
    /// can only name what the library already holds.
    public func needsConfirmation(_ command: Command) -> Bool {
        guard self == .urlScheme, case .import = command else { return false }
        return true
    }

    private func accepted(_ command: Command) throws(CommandRejection) -> Command {
        guard accepts(command) else { throw .notThroughThisDoor(command.verb) }
        return command
    }
}

extension Command {
    /// The wallpaper an import with `setEverywhere` goes on to assign to every
    /// display, given the wallpapers it resulted in, new or already in the
    /// library: one per source that did not fail. Only exactly one wallpaper
    /// sets; several never do, since nothing says which the user meant. The
    /// same wallpaper twice is one wallpaper.
    public func wallpaperToSetEverywhere(resulting wallpapers: [WallpaperID]) -> WallpaperID? {
        guard case .import(_, setEverywhere: true) = self, let first = wallpapers.first else { return nil }
        return wallpapers.allSatisfy { $0 == first } ? first : nil
    }
}
