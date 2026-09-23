import LivepaperCore
import SwiftUI

/// What the library window asks a name for: a wallpaper or playlist being
/// renamed, or a new playlist, which a wallpaper's menu starts with that wallpaper in it.
enum NamePrompt: Equatable {
    case renameWallpaper(WallpaperID, name: String)
    case renamePlaylist(PlaylistID, name: String)
    case newPlaylist(with: WallpaperID?)

    var title: String {
        switch self {
        case .renameWallpaper: "Rename Wallpaper"
        case .renamePlaylist: "Rename Playlist"
        case .newPlaylist: "New Playlist"
        }
    }

    var confirmTitle: String {
        switch self {
        case .renameWallpaper, .renamePlaylist: "Rename"
        case .newPlaylist: "Create"
        }
    }

    /// What the field starts with.
    var name: String {
        switch self {
        case .renameWallpaper(_, let name), .renamePlaylist(_, let name): name
        case .newPlaylist: ""
        }
    }
}

extension View {
    /// Asks for a name in an alert on the window, and hands it to `commit`
    /// unless it is empty. Cancel, or Escape, leaves everything as it was.
    func namePrompt(_ prompt: Binding<NamePrompt?>, commit: @escaping (NamePrompt, String) -> Void) -> some View {
        modifier(NamePromptAlert(prompt: prompt, commit: commit))
    }
}

private struct NamePromptAlert: ViewModifier {
    @Binding var prompt: NamePrompt?
    let commit: (NamePrompt, String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(prompt?.title ?? "", isPresented: isPresented, presenting: prompt) { prompt in
                TextField("Name", text: $name)
                Button(prompt.confirmTitle) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        commit(prompt, trimmed)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: prompt, initial: true) { _, prompt in
                name = prompt?.name ?? ""
            }
    }

    private var isPresented: Binding<Bool> {
        Binding { prompt != nil } set: { isShown in
            if !isShown { prompt = nil }
        }
    }
}
