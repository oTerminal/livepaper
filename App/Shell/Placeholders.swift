import DesignSystem
import LivepaperCore
import SwiftUI

// What each scene shows until M6's screens take their place: a little of the
// model in plain words, so it can be seen working.

/// The library window's stand-in: the counts, the wallpapers with a way to set
/// one and delete it, and the import list, over a drop target with the toast.
struct LibraryPlaceholder: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        content
            .frame(minWidth: 720, minHeight: 480)
            .dropDestination(for: URL.self) { urls, _ in
                model.importItems(at: urls)
                return true
            }
            .toastHost($model.toasts) { model.undo($0) }
    }

    @ViewBuilder private var content: some View {
        if model.libraryProblem != nil {
            EmptyState(title: "The library could not be read", systemImage: "exclamationmark.triangle")
        } else if model.library.wallpapers.isEmpty && model.importList.rows.isEmpty {
            EmptyState(
                title: "No Wallpapers",
                message: "Drop a video here, or choose one.",
                systemImage: "square.grid.2x2",
                actionTitle: "Import…",
                action: { model.chooseFilesToImport() }
            )
        } else {
            List {
                Section(counts) {
                    ForEach(model.grid) { wallpaper in
                        HStack {
                            Text(wallpaper.name)
                            Spacer()
                            Button("Set on All Displays") { model.setOnAllDisplays(.wallpaper(wallpaper.id)) }
                            Button("Delete") { model.delete(wallpaper.id) }
                        }
                    }
                }
                Section("Imports") {
                    ForEach(model.importList.rows) { row in
                        Text("\(row.candidate.name): \(String(describing: row.state.importProgressState))")
                    }
                }
            }
        }
    }

    private var counts: String {
        let counts = model.sidebarCounts
        return "\(counts.all) wallpapers, \(counts.favourites) favourites, \(counts.playlists.count) playlists"
    }
}

#Preview("Library") {
    LibraryPlaceholder()
        .environment(AppModel.preview())
}
