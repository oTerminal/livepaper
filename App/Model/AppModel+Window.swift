import AppKit
import DesignSystem
import Foundation
import LivepaperCore

// What the library window reads beyond the grid itself, and the fakes run's
// commands for it, so the manual script and the PR's media can drive the
// window where nothing can click it.

extension AppModel {
    /// Why the grid shows nothing; nil while it shows a wallpaper.
    var emptyGrid: EmptyGrid? {
        LivepaperCore.emptyGrid(library: library, state: state, section: section, search: search)
    }

    /// The frame the inspector's preview and the pan and zoom editor show: the
    /// first connected display's shape, else 16:10.
    var previewAspectRatio: CGFloat {
        displays.first?.aspectRatio ?? 16.0 / 10
    }
}

extension NSWindow {
    /// The library window's scene (`AppWindows.libraryID`): SwiftUI gives its
    /// window the scene's identifier ("library", seen on macOS 27).
    var isLibraryWindow: Bool {
        identifier?.rawValue.hasPrefix(AppWindows.libraryID) ?? false
    }
}

extension AppModel {
    /// A command from `Tools/pr-media/fakes.sh` for the library window, in the
    /// fakes run only. Answers whether it was one.
    ///
    ///     select Harbour at Dusk | deselect | section Favourites | search harbour | sort name (or newest, oldest)
    ///     set Studio Display | set All Displays | favourite | delete | undo | fit stretch | volume 0.6
    ///     new playlist Night Shift | import | cancel panel | size 1180 1100
    func performLibraryCommand(_ verb: String, _ rest: String) -> Bool {
        browsingCommand(verb, rest) ?? wallpaperCommand(verb, rest) ?? editCommand(verb, rest) ?? windowCommand(verb, rest) ?? false
    }

    /// Nil when the verb is not one of these; false when what it names is not there.
    private func browsingCommand(_ verb: String, _ rest: String) -> Bool? {
        switch verb {
        case "select":
            guard let wallpaper = library.wallpapers.first(where: { $0.name == rest }) else { return false }
            select(wallpaper.id)
        case "deselect":
            deselect()
        case "section":
            guard let section = section(named: rest) else { return false }
            self.section = section
        case "search":
            search = rest
        case "sort":
            let orders: [String: Library.SortOrder] = ["newest": .newestFirst, "oldest": .oldestFirst, "name": .name]
            guard let order = orders[rest] else { return false }
            setSortOrder(order)
        default:
            return nil
        }
        return true
    }

    private func wallpaperCommand(_ verb: String, _ rest: String) -> Bool? {
        switch verb {
        case "set":
            let assignment = selectedWallpaper.map { Assignment.wallpaper($0.id) } ?? selectedPlaylist.map { .playlist($0.id) }
            let target = rest == "All Displays" ? SetOnDisplayTarget.allID : displays.first { $0.name == rest }?.targetID
            guard let assignment, let target else { return false }
            setOnDisplay(assignment, target: target)
        case "favourite":
            guard let id = selection.selected else { return false }
            toggleFavourite(id)
        case "delete":
            deleteSelected()
        case "undo":
            // As the toast's Undo does it.
            guard case .undo(let toast) = toasts.send(.undo) else { return false }
            undo(toast)
        default:
            return nil
        }
        return true
    }

    /// The inspector's edits, as its controls make them.
    private func editCommand(_ verb: String, _ rest: String) -> Bool? {
        guard ["fit", "volume"].contains(verb) else { return nil }
        guard let id = selection.selected else { return false }
        if let fit = FitMode(rawValue: rest) {
            editPresentation(of: id) { $0.fit = fit }
        } else if let volume = Double(rest) {
            editVolume(volume, of: id)
        } else {
            return false
        }
        return true
    }

    private func windowCommand(_ verb: String, _ rest: String) -> Bool? {
        switch (verb, rest) {
        case ("new", let name) where name.hasPrefix("playlist "):
            createPlaylist(named: String(name.dropFirst("playlist ".count)), with: selection.selected.map { [$0] } ?? [])
        case ("import", _):
            chooseFilesToImport()
        case ("cancel", "panel"):
            // The Open panel, as a sheet or on its own, chosen with nothing.
            for panel in NSApp.windows.compactMap({ $0 as? NSOpenPanel }) {
                panel.cancel(nil)
            }
        case ("size", let size):
            // The library window's content size, "1180 1100", for looking at a long inspector.
            let points = size.split(separator: " ").compactMap { Double($0) }
            guard points.count == 2, let window = NSApp.windows.first(where: \.isLibraryWindow) else { return false }
            window.setContentSize(CGSize(width: points[0], height: points[1]))
        default:
            return nil
        }
        return true
    }

    /// "All Wallpapers", "Favourites", a playlist's name or a display's.
    private func section(named name: String) -> LibrarySection? {
        switch name {
        case "All Wallpapers": return .all
        case "Favourites": return .favourites
        default:
            if let playlist = playlists.first(where: { $0.name == name }) { return .playlist(playlist.id) }
            return displays.first { $0.name == name }.map { .nowPlaying($0.identity) }
        }
    }
}
