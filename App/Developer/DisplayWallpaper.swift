import LivepaperCore

/// What the developer menu has one display show, until M6's `AppState` takes over.
struct DisplayWallpaper: Equatable {
    var wallpaper: WallpaperID
    var presentation: Presentation
    var volume: Double
    var userPaused: Bool

    /// A wallpaper set on a display starts from its own presentation; the
    /// display keeps the volume and the pause it had.
    init(_ wallpaper: Wallpaper, replacing previous: DisplayWallpaper?) {
        self.wallpaper = wallpaper.id
        presentation = wallpaper.presentation
        volume = previous?.volume ?? 0
        userPaused = previous?.userPaused ?? false
    }

    /// A display as the last render state had it. The pause is not carried
    /// over, so that a relaunch plays again without a click (check "Stopped").
    init(restoring display: RenderState.Display) {
        wallpaper = display.wallpaper
        presentation = display.presentation
        volume = display.volume
        userPaused = false
    }
}

extension RenderState {
    /// The displays that show something, in a fixed order, with the library's
    /// files. A display whose wallpaper has left the library is left out.
    static func displays(_ shown: [DisplayIdentity: DisplayWallpaper], in library: Library) -> [Display] {
        shown
            .sorted { $0.key.description < $1.key.description }
            .compactMap { identity, shown in
                guard let wallpaper = library[shown.wallpaper] else { return nil }
                return Display(
                    identity: identity,
                    wallpaper: wallpaper.id,
                    optimisedCopy: wallpaper.optimisedCopy,
                    poster: wallpaper.poster,
                    presentation: shown.presentation,
                    volume: shown.volume,
                    userPaused: shown.userPaused
                )
            }
    }

    /// The live state that follows `previous`, whose generation it continues;
    /// `nil` when it would say nothing `previous` does not, or when there is
    /// neither a previous state nor anything to show.
    static func following(
        _ previous: RenderState?, displays: [Display], pauseRules: PauseRules, conditions: SensedConditions?
    ) -> RenderState? {
        guard let previous else {
            if displays.isEmpty { return nil }
            return RenderState(displays: displays, pauseRules: pauseRules, conditions: conditions)
        }
        let unchanged = !previous.isStopped
            && previous.displays == displays
            && previous.pauseRules == pauseRules
            && previous.conditions == conditions
        if unchanged { return nil }
        return previous.next { state in
            state.isStopped = false
            state.displays = displays
            state.pauseRules = pauseRules
            state.conditions = conditions
        }
    }
}
