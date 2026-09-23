import DesignSystem
import Foundation
import LivepaperCore

// What the displays show: Set on Display, the playlist pickers, the transport,
// mute, and the wallpaper service. Pause All is in AppModel.swift, with the
// rest of the host's life.

extension AppModel {
    // MARK: Set on display

    /// Sets a wallpaper or a playlist where `SetOnDisplayButton` says: a
    /// display's `targetID`, or `SetOnDisplayTarget.allID`. The button's state
    /// (`setOnDisplayState(for:)`) is working until the display has it, done for
    /// 1.5 s, then idle.
    func setOnDisplay(_ assignment: Assignment, target: SetOnDisplayTarget.ID) {
        if target == SetOnDisplayTarget.allID {
            setOnAllDisplays(assignment)
        } else if let display = displays.first(where: { $0.targetID == target }) {
            set(assignment, on: display.identity)
        }
    }

    func set(_ assignment: Assignment, on display: DisplayIdentity) {
        var rng = SystemRandomNumberGenerator()
        let next = state.assigning(assignment, to: [display], now: Date(), rng: &rng)
        showFeedback(for: assignment, until: commit(state: next))
    }

    /// Every display, plugged in now or later, shows it.
    func setOnAllDisplays(_ assignment: Assignment) {
        var rng = SystemRandomNumberGenerator()
        let next = state.assigningToAll(assignment, connected: displays.map(\.identity), now: Date(), rng: &rng)
        showFeedback(for: assignment, until: commit(state: next))
    }

    /// Takes a display's own assignment away: it shows what All Displays has, or nothing.
    func unassign(_ display: DisplayIdentity) {
        commit(state: state.unassigning(display))
    }

    /// A display's playlist picker in the popover. Nil is "No Playlist", which
    /// keeps the wallpaper the display shows now.
    func choosePlaylist(_ id: PlaylistID?, for display: DisplayIdentity) {
        var rng = SystemRandomNumberGenerator()
        commit(state: state.choosingPlaylist(id, for: display, in: library, now: Date(), rng: &rng))
    }

    private func showFeedback(for assignment: Assignment, until applied: Task<Void, Never>?) {
        let token = feedbackTokens[assignment, default: 0] + 1
        feedbackTokens[assignment] = token
        setOnDisplayFeedback[assignment, default: SetOnDisplayFeedback()].started()
        Task {
            await applied?.value
            guard feedbackTokens[assignment] == token else { return }
            setOnDisplayFeedback[assignment]?.applied(at: Date())
            guard let idleAt = setOnDisplayFeedback[assignment]?.idleAt else { return }
            try? await Task.sleep(for: .seconds(max(idleAt.timeIntervalSinceNow, 0)))
            setOnDisplayFeedback[assignment]?.tick(at: Date())
        }
    }

    // MARK: The transport

    /// One display's pause: its decoder is kept, so resuming is instant.
    func togglePause(on display: DisplayIdentity) {
        commit(state: state.settingPaused(!state.pausedDisplays.contains(display), for: display))
    }

    /// The next wallpaper of the playlist the display shows (`NowPlaying.canSkip`).
    func next(on display: DisplayIdentity) {
        guard case .playlist? = state.assignment(for: display) else { return }
        if let showing = state.wallpaper(shownOn: display, in: library) {
            histories[display, default: RotationHistory()].leaving(showing.id)
        }
        var rng = SystemRandomNumberGenerator()
        commit(state: state.rotating(display, .next(at: Date()), rng: &rng))
    }

    /// Back through what the display's playlist showed this session, then back
    /// through the playlist's order.
    func previous(on display: DisplayIdentity) {
        guard case .playlist(let id)? = state.assignment(for: display), let playlist = state[playlist: id] else { return }
        let showing = state.wallpaper(shownOn: display, in: library)?.id
        guard let back = histories[display, default: RotationHistory()].previous(in: playlist, current: showing) else { return }
        commit(state: state.steppingBack(display, to: back))
    }

    // MARK: Mute

    /// Every display at volume 0, whatever its wallpaper's volume.
    func setMuted(_ isMuted: Bool) {
        var next = state
        next.isMuted = isMuted
        commit(state: next)
    }

    func toggleMute() {
        setMuted(!state.isMuted)
    }

    // MARK: The wallpaper service

    /// The status line's Restart, when the service is not responding.
    func restartWallpaperService() {
        let host = services.host
        Task { await host.recover(.restartAgent) }
    }

    /// "Log Playback Metrics": the extension's probe. Never kept.
    func setPlaybackMetrics(_ isOn: Bool) {
        services.setPlaybackMetrics(isOn)
    }
}
