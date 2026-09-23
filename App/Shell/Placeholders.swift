import DesignSystem
import LivepaperCore
import SwiftUI

// What each scene shows until M6's screens take their place: a little of the
// model in plain words, so it can be seen working.

/// The popover's stand-in: each display's card in words, the status line, and the footer.
struct PopoverPlaceholder: View {
    @Environment(AppModel.self) private var model
    @Environment(AppWindows.self) private var windows

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Livepaper")
                .font(.headline)
            ForEach(model.nowPlaying) { card in
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(model.display(card.display)?.name ?? "Display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.wallpaper?.name ?? "No wallpaper")
                    Text(card.status ?? (card.isPlaying ? "Playing" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            StatusLine(status: model.statusLine.statusLineStatus) { model.restartWallpaperService() }
            Divider()
            HStack(spacing: Spacing.small) {
                Button(model.isPausedAll ? "Resume All" : "Pause All") { model.togglePauseAll() }
                Button(model.isMuted ? "Unmute" : "Mute") { model.toggleMute() }
                Spacer(minLength: 0)
                Button("Open Library", systemImage: "square.grid.2x2") { windows.openLibrary() }
                    .labelStyle(.iconOnly)
                    .help("Open Library")
                Button("Settings", systemImage: "gearshape") { windows.openSettings() }
                    .labelStyle(.iconOnly)
                    .help("Settings")
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .frame(width: 320, alignment: .leading)
        .padding(Spacing.tight)
    }
}

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

/// Settings' stand-in: the pause rules.
struct SettingsPlaceholder: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Pause Rules") {
                Toggle("When the desktop is covered", isOn: rule(\.whenDesktopCovered))
                Toggle("When the display is asleep or locked", isOn: rule(\.whenDisplayAsleepOrLocked))
                Toggle("In Low Power Mode", isOn: rule(\.inLowPowerMode))
                Toggle("On battery", isOn: rule(\.onBattery))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func rule(_ rule: WritableKeyPath<PauseRules, Bool>) -> Binding<Bool> {
        Binding(get: { model.pauseRules[keyPath: rule] }, set: { model.setPauseRule(rule, $0) })
    }
}

#Preview("Popover") {
    GlassPopover { PopoverPlaceholder() }
        .fixedSize()
        .padding(Spacing.section)
        .environment(AppModel.preview())
        .environment(AppWindows())
}

#Preview("Library") {
    LibraryPlaceholder()
        .environment(AppModel.preview())
}

#Preview("Settings") {
    SettingsPlaceholder()
        .environment(AppModel.preview())
}
