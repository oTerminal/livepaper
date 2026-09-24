import DesignSystem
import LivepaperCore

extension AppDelegate {
    /// Runs each hotkey's action as it is pressed, for the app's life: the
    /// model's, or the library window's, which the app's windows own.
    func watchHotkeys() {
        let presses = model.services.hotkeyPresses
        Task { [weak self] in
            for await action in presses {
                self?.hotkeyPressed(action)
            }
        }
    }

    /// A hotkey, in whatever app is in front (M7). It never animates the
    /// interface (M3-design-system.md): an open popover's controls change in one
    /// frame. What the displays show still crossfades, since that is content.
    private func hotkeyPressed(_ action: HotkeyAction) {
        withoutAnimation {
            switch action {
            case .pauseOrResumeAll: model.togglePauseAll()
            case .nextWallpaper: model.nextOnEveryPlaylist()
            case .mute: model.toggleMute()
            case .openLibrary: windows.openLibrary()
            }
        }
    }
}
