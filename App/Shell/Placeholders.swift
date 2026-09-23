import DesignSystem
import SwiftUI

// What each scene shows until M6's screens take their place.

/// The popover's stand-in: its footer's two ways out, Open Library and Settings.
struct PopoverPlaceholder: View {
    @Environment(AppWindows.self) private var windows

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Livepaper")
                .font(.headline)
            Text("The displays, their wallpapers and the transport come here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: Spacing.small) {
                Button("Open Library", systemImage: "square.grid.2x2") { windows.openLibrary() }
                Spacer(minLength: 0)
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

/// The library window's stand-in.
struct LibraryPlaceholder: View {
    var body: some View {
        EmptyState(
            title: "Library",
            message: "The sidebar, the grid of wallpapers and the inspector come here.",
            systemImage: "square.grid.2x2"
        )
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// Settings' stand-in.
struct SettingsPlaceholder: View {
    var body: some View {
        Form {
            Section("Pause Rules") {
                Text("The pause rules, Open at Login, the hotkeys and leaving Livepaper come here.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Popover") {
    GlassPopover { PopoverPlaceholder() }
        .fixedSize()
        .padding(Spacing.section)
        .environment(AppWindows())
}

#Preview("Library") {
    LibraryPlaceholder()
}

#Preview("Settings") {
    SettingsPlaceholder()
}
