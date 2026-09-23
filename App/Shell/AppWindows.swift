import AppKit
import SwiftUI

/// Opens the library window and Settings from anywhere: the popover, a menu,
/// and M7's hotkeys. The Dock icon follows the library window: it comes when
/// the window opens and goes when it closes, and the app stays in the menu bar.
@MainActor @Observable
final class AppWindows {
    static let libraryID = "library"

    /// Runs before either window opens: the popover closes, so that it is not left over the window.
    @ObservationIgnored var willOpenWindow: (() -> Void)?
    private(set) var isLibraryOpen = false

    /// SwiftUI's actions, read from a view in the app by `SceneActionsReader`.
    /// Until a view has read them, a fresh environment's do the same: they reach
    /// the app's scenes wherever they are called from (seen on macOS 27).
    @ObservationIgnored private var openWindow: OpenWindowAction?
    @ObservationIgnored private var openSettingsAction: OpenSettingsAction?

    /// Opens the library window, or brings it forward, with the Dock icon.
    func openLibrary() {
        willOpenWindow?()
        NSApp.setActivationPolicy(.regular)
        (openWindow ?? EnvironmentValues().openWindow)(id: Self.libraryID)
        NSApp.activate()
    }

    /// Opens Settings and brings it forward. It brings no Dock icon.
    func openSettings() {
        willOpenWindow?()
        (openSettingsAction ?? EnvironmentValues().openSettings)()
        NSApp.activate()
    }

    fileprivate func read(openWindow: OpenWindowAction, openSettings: OpenSettingsAction) {
        self.openWindow = openWindow
        openSettingsAction = openSettings
    }

    fileprivate func libraryDidOpen() {
        isLibraryOpen = true
        NSApp.setActivationPolicy(.regular)
    }

    /// The close button or Command-W: the Dock icon goes, the app keeps running.
    fileprivate func libraryDidClose() {
        isLibraryOpen = false
        NSApp.setActivationPolicy(.accessory)
    }
}

extension View {
    /// The library window's root: the Dock icon comes and goes with it.
    func libraryWindow(_ windows: AppWindows) -> some View {
        environment(windows)
            .background(SceneActionsReader(windows: windows))
            .onAppear { windows.libraryDidOpen() }
            .onDisappear { windows.libraryDidClose() }
    }
}

/// Hands SwiftUI's scene actions to `AppWindows`, from wherever it sits.
struct SceneActionsReader: View {
    let windows: AppWindows
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { windows.read(openWindow: openWindow, openSettings: openSettings) }
    }
}
