import Foundation

extension AppState {
    /// The wallpaper a display shows: its assignment's, or its playlist's
    /// rotation. A wallpaper the library has lost counts as nothing.
    func wallpaper(shownOn display: DisplayIdentity, in library: Library) -> Wallpaper? {
        switch assignment(for: display) {
        case .wallpaper(let id)?:
            return library[id]
        case .playlist(let id)?:
            guard let playlist = self[playlist: id] else { return nil }
            let rotation = rotation[display] ?? RotationState()
            return rotation.showing(in: playlist) { library[$0] != nil }.flatMap { library[$0] }
        case nil:
            return nil
        }
    }
}

extension RenderState {
    /// The render state for this library and app state on the connected
    /// displays, applied on every change.
    ///
    /// A display that shows nothing is left out, so the extension shows nothing
    /// there. Mute is the app's: every volume is 0 and the extension leaves the
    /// audio track unopened. The generation continues `previous`'s, and the
    /// answer is nil when it would say nothing `previous` does not. With no
    /// previous state it is generation 1 even when nothing is shown, so that the
    /// extension learns it should show nothing. A stopped previous state is
    /// followed by a live one: resuming is making a new state.
    public static func make(
        library: Library, state: AppState, connected: [DisplayIdentity], conditions: SensedConditions?, previous: RenderState?
    ) -> RenderState? {
        let displays = Set(connected).sorted(byDisplay: \.self).compactMap { identity -> Display? in
            guard let wallpaper = state.wallpaper(shownOn: identity, in: library) else { return nil }
            return Display(
                identity: identity,
                wallpaper: wallpaper.id,
                optimisedCopy: wallpaper.optimisedCopy,
                poster: wallpaper.poster,
                presentation: wallpaper.presentation,
                volume: state.isMuted ? 0 : wallpaper.volume,
                userPaused: state.pausedDisplays.contains(identity)
            )
        }
        guard let previous else {
            return RenderState(displays: displays, pauseRules: state.pauseRules, conditions: conditions)
        }
        let unchanged = !previous.isStopped
            && previous.displays == displays
            && previous.pauseRules == state.pauseRules
            && previous.conditions == conditions
        if unchanged { return nil }
        return previous.next { next in
            next.isStopped = false
            next.displays = displays
            next.pauseRules = state.pauseRules
            next.conditions = conditions
        }
    }
}
