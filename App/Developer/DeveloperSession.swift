import AppKit
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import Observation
import os

/// A connected display as the menu offers it, named as macOS names it.
struct MenuDisplay: Identifiable, Equatable {
    let identity: DisplayIdentity
    let name: String

    var id: DisplayIdentity { identity }

    init(_ display: ConnectedDisplay) {
        identity = display.identity
        let screen = NSScreen.screens.first { $0.displayID == display.displayID }
        name = screen?.localizedName ?? "Display \(display.displayID)"
    }
}

/// Drives the real render host from the developer menu, so that the checks on
/// screen (docs/specs/M5-engine.md) can be run until M6's screens replace it.
///
/// It owns the library, the host client and the sensors, keeps what each
/// display shows in memory, and applies a new render state whenever that or
/// the sensed conditions change.
@Observable
final class DeveloperSession {
    private(set) var status: RenderHostStatus = .stopped
    private(set) var library = Library()
    private(set) var isLibraryReadable = true
    /// The connected displays, as the display sensor last said.
    private(set) var displays: [MenuDisplay] = []
    private(set) var isPlaybackMetricsOn = false
    /// Set by the import (DeveloperSession+Import.swift).
    var isImporting = false
    /// Set by the scripted checks (DeveloperSession+Checks.swift).
    var runningCheck: DeveloperCheck?

    let location = LibraryLocation(home: .homeDirectory)
    let host: ExtensionHostClient
    /// The S2p check's window.
    @ObservationIgnored let preview = PreviewWindow()
    let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: DeveloperLog.category)

    /// What each display shows, displays that are not connected now included,
    /// so that one plugged back in gets its own wallpaper.
    @ObservationIgnored private(set) var shown: [DisplayIdentity: DisplayWallpaper] = [:]
    /// The last state handed to the host; the next one continues its generation.
    @ObservationIgnored private var current: RenderState?
    @ObservationIgnored private var conditions: SensedConditions?
    @ObservationIgnored private let pauseRules = PauseRules()
    @ObservationIgnored private(set) var storedLibrary: StoredLibrary?
    @ObservationIgnored private var sensing: ConditionsSensing?
    @ObservationIgnored private var watches: [Task<Void, Never>] = []
    /// States are written in the order they were made, each after the one before.
    @ObservationIgnored private var applying: Task<Void, Never>?
    @ObservationIgnored private var launching: Task<Void, Never>?
    @ObservationIgnored private var quitting: Task<Void, Never>?
    @ObservationIgnored var checkTask: Task<Void, Never>?

    init() {
        host = ExtensionHostClient(location: location)
    }

    // MARK: Launch and quit

    func launch() {
        guard launching == nil else { return }
        launching = Task { await start() }
    }

    /// Writes the stopped state, in which each display holds its poster
    /// (record 0003), and returns once it is written. Nothing is applied after.
    func quit() async {
        if let quitting { return await quitting.value }
        let stopping = Task { await stop() }
        quitting = stopping
        await stopping.value
    }

    private func start() async {
        // Before anything could start an import (M4-import.md, "As built").
        do {
            let swept = try sweepInterruptedImports(in: location)
            logger.notice("\(DeveloperLog.swept(swept.count), privacy: .public)")
        } catch {
            logger.error("\(DeveloperLog.sweepFailed(error), privacy: .public)")
        }
        do {
            let stored = try StoredLibrary(store: FileLibraryStore(manifest: location.manifest))
            storedLibrary = stored
            library = await stored.library
        } catch {
            isLibraryReadable = false
            logger.error("\(DeveloperLog.libraryUnreadable(error), privacy: .public)")
        }
        // Without the library every display would look lost, and the state on disk be replaced by an empty one.
        if isLibraryReadable { restore() }

        watchStatus()
        do {
            try await host.activate()
        } catch {
            logger.error("\(DeveloperLog.activationFailed(error), privacy: .public)")
        }
        let sensing = ConditionsSensing(rules: pauseRules, host: host.capabilities) { [weak self] conditions in
            self?.sensed(conditions)
        }
        self.sensing = sensing
        watchDisplays(sensing.displays)
        sensing.start()
        // The restored state, live again: a relaunch resumes without a click.
        applyShown()
    }

    private func stop() async {
        await launching?.value
        checkTask?.cancel()
        sensing?.stop()
        for watch in watches {
            watch.cancel()
        }
        watches = []
        await applying?.value
        await host.deactivate()
        let stopped = host.lastApplied.flatMap { $0.isStopped ? $0.generation : nil }
        logger.notice("\(DeveloperLog.quit(stopped: stopped), privacy: .public)")
    }

    /// What the displays showed when the app last wrote the render state,
    /// without the wallpapers that have left the library since.
    private func restore() {
        let data: Data
        do {
            data = try Data(contentsOf: location.renderState)
        } catch {
            return
        }
        do {
            let state = try RenderState.decode(data)
            current = state
            for display in state.displays where library[display.wallpaper] != nil {
                shown[display.identity] = DisplayWallpaper(restoring: display)
            }
            let line = DeveloperLog.restored(shown.count, generation: state.generation)
            logger.notice("\(line, privacy: .public)")
        } catch {
            logger.error("\(DeveloperLog.renderStateUnreadable(error), privacy: .public)")
        }
    }

    // MARK: Watching

    private func watchStatus() {
        let statuses = host.status
        watches.append(Task { [weak self] in
            for await status in statuses {
                self?.status = status
            }
        })
    }

    private func watchDisplays(_ sensor: any DisplaySensor) {
        let updates = sensor.updates()
        watches.append(Task { [weak self] in
            for await connected in updates {
                self?.displays = connected.map(MenuDisplay.init)
            }
        })
    }

    private func sensed(_ conditions: SensedConditions) {
        self.conditions = conditions
        applyShown()
    }

    // MARK: Applying

    /// Changes what the displays show, applies the state that follows, and
    /// answers the generation that carries the change.
    private func change(_ edit: (inout [DisplayIdentity: DisplayWallpaper]) -> Void) -> UInt64 {
        edit(&shown)
        return applyShown()
    }

    @discardableResult
    private func applyShown() -> UInt64 {
        guard quitting == nil else { return current?.generation ?? 0 }
        let displays = RenderState.displays(shown, in: library)
        if let next = RenderState.following(current, displays: displays, pauseRules: pauseRules, conditions: conditions) {
            current = next
            let previous = applying
            applying = Task { [host] in
                await previous?.value
                await host.apply(next)
            }
        }
        return current?.generation ?? 0
    }

    /// Reads the library again, after an import changed it.
    func reloadLibrary() async {
        guard let storedLibrary else { return }
        library = await storedLibrary.library
    }

    // MARK: The menu's actions

    @discardableResult
    func set(_ wallpaper: Wallpaper, on targets: [DisplayIdentity]) -> UInt64 {
        let generation = change { shown in
            for display in targets {
                shown[display] = DisplayWallpaper(wallpaper, replacing: shown[display])
            }
        }
        for display in targets {
            logger.notice("\(DeveloperLog.wallpaperSet(wallpaper.id, on: display, generation: generation), privacy: .public)")
        }
        return generation
    }

    /// On the displays connected now.
    @discardableResult
    func setOnAllDisplays(_ wallpaper: Wallpaper) -> UInt64 {
        set(wallpaper, on: displays.map(\.identity))
    }

    func setFit(_ fit: FitMode) {
        let generation = change { shown in
            for display in shown.keys {
                shown[display]?.presentation.fit = fit
            }
        }
        logger.notice("\(DeveloperLog.fit(fit, generation: generation), privacy: .public)")
    }

    func setFocalPoint(_ point: Point) {
        let generation = change { shown in
            for display in shown.keys {
                shown[display]?.presentation.focalPoint = point
            }
        }
        logger.notice("\(DeveloperLog.focalPoint(point, generation: generation), privacy: .public)")
    }

    func setVolume(_ volume: Double) {
        let generation = change { shown in
            for display in shown.keys {
                shown[display]?.volume = volume
            }
        }
        logger.notice("\(DeveloperLog.volume(volume, generation: generation), privacy: .public)")
    }

    func pauseAll() {
        let generation = setUserPaused(true)
        logger.notice("\(DeveloperLog.pauseAll(generation: generation), privacy: .public)")
    }

    func resume() {
        let generation = setUserPaused(false)
        logger.notice("\(DeveloperLog.resume(generation: generation), privacy: .public)")
    }

    private func setUserPaused(_ paused: Bool) -> UInt64 {
        change { shown in
            for display in shown.keys {
                shown[display]?.userPaused = paused
            }
        }
    }

    func restartWallpaperService() {
        Task { await host.recover(.restartAgent) }
    }

    func runWatchdogCheck() {
        host.requestCheck()
    }

    /// Never kept: every launch starts with the probe off.
    func setPlaybackMetrics(_ on: Bool) {
        host.setPlaybackMetrics(on)
        isPlaybackMetricsOn = host.isPlaybackMetricsOn
    }
}

extension NSScreen {
    /// CoreGraphics' number for the display this screen is on.
    fileprivate var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
