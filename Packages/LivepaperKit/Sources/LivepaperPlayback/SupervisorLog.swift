import LivepaperCore

/// Every line `PlaybackSupervisor` logs, worded here and nowhere else. Other
/// milestones parse them (M8-hardening.md's soak, M10-1.0.md's checklist), so
/// each is `key=value` after a fixed phrase, and `SupervisorLogTests` pins them.
public enum SupervisorLog {
    /// What every line about one surface carries.
    public struct Surface: Equatable, Sendable {
        public var surface: SurfaceID
        public var display: DisplayIdentity
        public var isPreview: Bool
        /// The wallpaper it shows or is about to, if any.
        public var wallpaper: WallpaperID?
        /// The render state's generation, if one has been read.
        public var generation: UInt64?

        public init(surface: SurfaceID, display: DisplayIdentity, isPreview: Bool, wallpaper: WallpaperID?, generation: UInt64?) {
            self.surface = surface
            self.display = display
            self.isPreview = isPreview
            self.wallpaper = wallpaper
            self.generation = generation
        }

        var fields: String {
            let wallpaper = wallpaper?.description ?? "none"
            let generation = generationText(generation)
            return "surface=\(surface) display=\(display) preview=\(isPreview) wallpaper=\(wallpaper) generation=\(generation)"
        }
    }

    // MARK: Surface events

    public static func acquired(_ surface: Surface, reused: Bool) -> String {
        "acquire \(reused ? "reused" : "new") \(surface.fields)"
    }

    public static func invalidated(_ surface: Surface) -> String {
        "invalidate \(surface.fields)"
    }

    public static func invalidatedUnknown(_ surface: SurfaceID) -> String {
        "invalidate unknown surface=\(surface)"
    }

    public static func tornDown(_ surface: Surface) -> String {
        "torn down \(surface.fields)"
    }

    public static func nowShowing(_ surface: Surface, crossfade: Bool) -> String {
        "now showing \(surface.fields) crossfade=\(crossfade)"
    }

    public static func holdingStill(_ surface: Surface) -> String {
        "holding still \(surface.fields)"
    }

    public static func showingNothing(_ surface: Surface) -> String {
        "showing nothing \(surface.fields)"
    }

    public static func updated(_ surface: Surface, mode: SurfacePresentationMode) -> String {
        "update \(surface.fields) mode=\(mode.rawValue)"
    }

    // MARK: Decisions and the render state

    public static func decision(display: DisplayIdentity, target: SurfaceTarget, generation: UInt64?) -> String {
        "decision display=\(display) decision=\(name(of: target)) generation=\(generationText(generation))"
    }

    /// `kept` is the generation still shown when the file cannot be trusted.
    public static func renderState(_ read: RenderStateRead, kept: UInt64?) -> String {
        switch read {
        case .read(let state):
            "render state read generation=\(state.generation) stopped=\(state.isStopped) displays=\(state.displays.count)"
        case .missing: "render state missing, showing nothing"
        case .unreadable(let reason): "render state unreadable, keeping generation=\(generationText(kept)): \(reason)"
        }
    }

    // MARK: The watchdog

    public static func checkStarted(_ trigger: WatchdogTrigger, judging count: Int) -> String {
        "check started reason=\(trigger.rawValue) surfaces=\(count)"
    }

    public static func counted(_ surface: Surface, _ count: PictureCount) -> String {
        "check count \(surface.fields) displayed=\(count.displayed) expected=\(count.expected)"
    }

    /// `attempt` is how many recoveries had been tried on the surface before this verdict.
    public static func verdict(_ surface: Surface, _ step: WatchdogStep, attempt: Int) -> String {
        let verdict = switch step {
        case .healthy: "healthy"
        case .recover(let level): name(of: level)
        case .requestRestart: name(of: .restartAgent)
        }
        return "check verdict \(surface.fields) verdict=\(verdict) attempt=\(attempt)"
    }

    public static func recoveryTried(_ surface: Surface, level: RecoveryLevel) -> String {
        "recovery tried \(surface.fields) level=\(name(of: level))"
    }

    /// The heartbeat now carries `restartAgentRequested`.
    public static func restartRequested(_ surface: Surface) -> String {
        "restart requested \(surface.fields)"
    }

    /// The heartbeat no longer carries `restartAgentRequested`.
    public static let restartRequestCleared = "restart request cleared"

    /// The app's `HostNotification.recover`.
    public static func recoverRequested(_ level: RecoveryLevel, stalled count: Int) -> String {
        "recover requested level=\(name(of: level)) stalled=\(count)"
    }

    // MARK: Names

    static func name(of target: SurfaceTarget) -> String {
        switch target {
        case .nothing: "nothing"
        case .still: "still"
        case .playback(_, .play): "play"
        case .playback(_, .pause(let reason)): "pause.\(name(of: reason))"
        case .playback(_, .suspend(let reason)): "suspend.\(name(of: reason))"
        }
    }

    static func name(of level: RecoveryLevel) -> String {
        switch level {
        case .flush: "flush"
        case .rebuildSurface: "rebuildSurface"
        case .rebuildPipeline: "rebuildPipeline"
        case .restartAgent: "restartAgent"
        }
    }

    static func name(of reason: PauseReason) -> String {
        switch reason {
        case .user: "user"
        case .desktopCovered: "desktopCovered"
        case .displayAsleep: "displayAsleep"
        case .displayLocked: "displayLocked"
        case .lowPowerMode: "lowPowerMode"
        case .onBattery: "onBattery"
        }
    }
}

/// A generation, or `none` before any render state was read.
private func generationText(_ generation: UInt64?) -> String {
    generation.map(String.init) ?? "none"
}
