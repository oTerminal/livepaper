import Foundation

/// What one display's card in the popover shows.
public struct NowPlaying: Equatable, Sendable, Identifiable {
    public var id: DisplayIdentity { display }
    public var display: DisplayIdentity
    /// Nil reads "No wallpaper", with a Choose accessory.
    public var wallpaper: Wallpaper?
    /// The playlist the display shows, if it shows one.
    public var playlist: PlaylistID?
    /// Why it is not playing, in words; nil while it plays or shows nothing.
    public var status: String?
    public var isPlaying: Bool
    /// The display's own pause, which its play and pause button shows. Pause All is not one.
    public var isUserPaused: Bool
    /// Next and Previous: only for a playlist with at least two wallpapers in the library.
    public var canSkip: Bool

    public init(
        display: DisplayIdentity,
        wallpaper: Wallpaper?,
        playlist: PlaylistID? = nil,
        status: String? = nil,
        isPlaying: Bool,
        isUserPaused: Bool = false,
        canSkip: Bool = false
    ) {
        self.display = display
        self.wallpaper = wallpaper
        self.playlist = playlist
        self.status = status
        self.isPlaying = isPlaying
        self.isUserPaused = isUserPaused
        self.canSkip = canSkip
    }
}

/// One card per connected display, in the order given.
///
/// The status is `decidePlayback`'s reason on what `render` last carried, with
/// the state's pause rules and the user's pause from the state, so that a pause
/// shows before the render state that carries it is applied. A stopped render
/// state (Pause All) reads "Paused"; with none applied yet, only the user's
/// pause counts.
public func nowPlaying(
    library: Library, state: AppState, connected: [DisplayIdentity], render: RenderState? = nil, host: HostCapabilities, now: Date
) -> [NowPlaying] {
    connected.map { display in
        var card = NowPlaying(
            display: display,
            wallpaper: state.wallpaper(shownOn: display, in: library),
            isPlaying: false,
            isUserPaused: state.pausedDisplays.contains(display)
        )
        if case .playlist(let id)? = state.assignment(for: display), let playlist = state[playlist: id] {
            card.playlist = id
            card.canSkip = playlist.wallpapers.count { library[$0] != nil } >= 2
        }
        guard card.wallpaper != nil else { return card }
        guard render?.isStopped != true else {
            card.status = PauseReason.user.words
            return card
        }

        var conditions = render?.playbackConditions(for: display, now: now) ?? PlaybackConditions(sensedAt: .distantPast, now: now)
        conditions.userPaused = card.isUserPaused
        switch decidePlayback(conditions, rules: state.pauseRules, host: host) {
        case .play:
            card.isPlaying = true
        case .pause(let reason), .suspend(let reason):
            card.status = reason.words
        }
        return card
    }
}

extension PauseReason {
    /// A card's status, as short as the card is narrow.
    var words: String {
        switch self {
        case .user: "Paused"
        case .desktopCovered: "Paused: desktop covered"
        case .displayAsleep: "Paused: display asleep"
        case .displayLocked: "Paused: locked"
        case .lowPowerMode: "Paused: Low Power Mode"
        case .onBattery: "Paused: on battery"
        }
    }
}
