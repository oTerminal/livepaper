import DesignSystem
import LivepaperCore
import SwiftUI

// What each scene shows until M6's screens take their place: a little of the
// model in plain words, so it can be seen working. The library window's is gone:
// LibraryWindow took its place.

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

#Preview("Settings") {
    SettingsPlaceholder()
        .environment(AppModel.preview())
}
