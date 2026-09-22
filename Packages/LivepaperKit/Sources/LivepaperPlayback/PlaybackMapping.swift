import Foundation
import LivepaperCore

/// What one surface should be doing, from the render state and the playback policy.
public enum SurfaceTarget: Equatable, Sendable {
    /// No render state, or none for this surface's display: the neutral colour.
    case nothing
    /// The stopped render state: the poster, and no decoder (record 0003).
    case still(SurfaceWallpaper)
    /// The wallpaper, played, paused or suspended as the policy decided.
    case playback(SurfaceWallpaper, PlaybackDecision)
}

/// One call on a `SurfacePlayback`.
public enum SurfaceCall: Equatable, Sendable {
    case show(SurfaceWallpaper, crossfade: Bool)
    case holdStill(SurfaceWallpaper)
    case showNothing
    case pause
    case resume
    case suspend
}

/// The calls that take a surface from what it is doing to `target`.
///
/// Pause and suspend only ever stop what is up: a surface with nothing up, or
/// a different wallpaper, holds the poster instead of opening a video just to
/// stop it. Only a surface that plays crossfades to another video; anything
/// else switches without a fade. `show` leaves the surface playing, so
/// nothing follows it but a pause.
public func surfaceCalls(toReach target: SurfaceTarget, from state: SurfacePlaybackState, showing current: SurfaceWallpaper?) -> [SurfaceCall] {
    switch target {
    case .nothing:
        return state == .nothing ? [] : [.showNothing]

    case .still(let wallpaper):
        return state == .still && looksTheSame(current, wallpaper) ? [] : [.holdStill(wallpaper)]

    case .playback(let wallpaper, .play):
        switch state {
        case .nothing, .still:
            return [.show(wallpaper, crossfade: false)]
        case .playing:
            if current == wallpaper { return [] }
            return [.show(wallpaper, crossfade: current?.video != wallpaper.video)]
        case .paused, .suspended:
            return current == wallpaper ? [.resume] : [.show(wallpaper, crossfade: false)]
        }

    case .playback(let wallpaper, .pause):
        switch state {
        case .nothing, .still:
            return state == .still && looksTheSame(current, wallpaper) ? [] : [.holdStill(wallpaper)]
        case .playing, .paused, .suspended:
            guard current?.video == wallpaper.video else { return [.holdStill(wallpaper)] }
            guard looksTheSame(current, wallpaper) else { return [.show(wallpaper, crossfade: false), .pause] }
            switch state {
            case .playing: return [.pause]
            // The readers went with the suspend: open them again so a picture is up.
            case .suspended: return [.resume, .pause]
            default: return []
            }
        }

    case .playback(let wallpaper, .suspend):
        switch state {
        case .nothing, .still:
            return state == .still && looksTheSame(current, wallpaper) ? [] : [.holdStill(wallpaper)]
        case .playing, .paused, .suspended:
            guard looksTheSame(current, wallpaper) else { return [.holdStill(wallpaper)] }
            return state == .suspended ? [] : [.suspend]
        }
    }
}

/// When `decision` is to be taken again because the sensed conditions behind
/// it expire, or `nil` when nothing but a new render state can change it.
///
/// Only a pause or suspend that a sensed condition caused expires: the user's
/// pause never does, and conditions that play go on playing once they are
/// stale. Conditions exactly `PlaybackConditions.expiry` old still count, so
/// this is the first moment after that.
public func decisionExpiry(of decision: PlaybackDecision, conditions: PlaybackConditions) -> Date? {
    switch decision {
    case .play, .pause(.user), .suspend(.user):
        return nil
    case .pause, .suspend:
        let boundary = conditions.sensedAt.addingTimeInterval(PlaybackConditions.expiry / .seconds(1))
        return Date(timeIntervalSinceReferenceDate: boundary.timeIntervalSinceReferenceDate.nextUp)
    }
}

extension SurfaceWallpaper {
    /// A display's wallpaper from the render state, its paths resolved inside the library.
    public init(_ display: RenderState.Display, in location: LibraryLocation) {
        self.init(
            wallpaper: display.wallpaper,
            video: location.url(for: display.optimisedCopy),
            poster: location.url(for: display.poster),
            presentation: display.presentation,
            volume: display.volume
        )
    }
}

/// The same picture on screen: only the volume may differ.
private func looksTheSame(_ current: SurfaceWallpaper?, _ wallpaper: SurfaceWallpaper) -> Bool {
    guard let current else { return false }
    return current.video == wallpaper.video && current.poster == wallpaper.poster && current.presentation == wallpaper.presentation
}
