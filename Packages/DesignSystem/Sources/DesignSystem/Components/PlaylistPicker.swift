import SwiftUI

/// One playlist a `PlaylistPicker` offers.
public nonisolated struct PlaylistOption<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    /// How many wallpapers it holds; shown beside the title in the menu.
    public let count: Int

    public init(id: ID, title: String, count: Int) {
        self.id = id
        self.title = title
        self.count = count
    }
}

extension PlaylistOption: Sendable where ID: Sendable {}

/// Chooses the playlist a wallpaper belongs to, or none. A native menu with a
/// glass button, because it sits with the inspector's controls; a selection
/// that matches no playlist reads as "No Playlist" rather than as a blank.
public struct PlaylistPicker<ID: Hashable>: View {
    @Binding private var selection: ID?
    private let playlists: [PlaylistOption<ID>]
    private let onCreate: () -> Void

    public init(selection: Binding<ID?>, playlists: [PlaylistOption<ID>], onCreate: @escaping () -> Void) {
        _selection = selection
        self.playlists = playlists
        self.onCreate = onCreate
    }

    private var current: PlaylistOption<ID>? {
        playlists.first { $0.id == selection }
    }

    public var body: some View {
        Menu {
            if !playlists.isEmpty {
                // An inline picker gives the menu its native checkmarks.
                Picker(selection: $selection) {
                    Text("No Playlist", bundle: .module)
                        .tag(ID?.none)
                    ForEach(playlists) { playlist in
                        Text(verbatim: playlist.title)
                            .badge(playlist.count)
                            .tag(ID?.some(playlist.id))
                    }
                } label: {
                    Text("Playlist", bundle: .module)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
            }
            Button(action: onCreate) {
                Text("New Playlist…", bundle: .module)
            }
        } label: {
            Label {
                if let current {
                    Text(verbatim: current.title)
                } else {
                    Text("No Playlist", bundle: .module)
                }
            } icon: {
                Image(systemName: "rectangle.stack")
            }
            .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .accessibilityLabel(Text("Playlist", bundle: .module))
        .accessibilityValue(current.map { Text(verbatim: $0.title) } ?? Text("No Playlist", bundle: .module))
    }
}
