import AppKit
import CoreGraphics
import LivepaperCore

/// Which connected displays are fully covered by a window.
public protocol CoveredDisplaySensor: AnyObject {
    /// The covered displays now, and again each time that changes.
    func updates() -> AsyncStream<Set<DisplayIdentity>>
}

/// Reads the window list when something happens that can cover or uncover a
/// display, never on a fixed rate. No notification says that a window moved,
/// so a window dragged or resized over a whole display by hand is seen at the
/// next of these events; covering a display that way is rare, and a fullscreen
/// app, the usual case, changes the Space.
///
/// What it reads again on:
/// - an app activated, launched, quit, hidden or shown: the front window changed;
/// - the active Space changed: entering or leaving fullscreen is a Space change;
/// - the displays were reconfigured: the frames being covered changed;
/// - the Mac or its screens woke, the session became active again, or the
///   screen was unlocked: what is on screen then may not be what was before.
public final class SystemCoveredDisplaySensor: CoveredDisplaySensor {
    /// After each event the list is read twice: once the window has started to
    /// move, and once a fullscreen transition has had time to finish.
    public static let settles: [Duration] = [.milliseconds(250), .milliseconds(1000)]

    private let broadcast = Broadcast<Set<DisplayIdentity>>()
    private let triggers = NotificationTriggers()
    private var settling: Task<Void, Never>?

    public init() {
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.stop() })
    }

    public func updates() -> AsyncStream<Set<DisplayIdentity>> {
        broadcast.stream()
    }

    private func start() {
        let triggerList: [NotificationTriggers.Trigger] = [
            .workspace(NSWorkspace.didActivateApplicationNotification),
            .workspace(NSWorkspace.didLaunchApplicationNotification),
            .workspace(NSWorkspace.didTerminateApplicationNotification),
            .workspace(NSWorkspace.didHideApplicationNotification),
            .workspace(NSWorkspace.didUnhideApplicationNotification),
            .workspace(NSWorkspace.activeSpaceDidChangeNotification),
            .workspace(NSWorkspace.didWakeNotification),
            .workspace(NSWorkspace.screensDidWakeNotification),
            .workspace(NSWorkspace.sessionDidBecomeActiveNotification),
            .application(NSApplication.didChangeScreenParametersNotification),
            .distributed(SystemLockSensor.unlocked),
        ]
        triggers.start(triggerList) { [weak self] _ in self?.somethingMoved() }
        broadcast.send(Self.coveredNow())
    }

    private func stop() {
        triggers.stop()
        settling?.cancel()
        settling = nil
    }

    private func somethingMoved() {
        settling?.cancel()
        settling = Task { [weak self] in
            var waited = Duration.zero
            for settle in Self.settles {
                try? await Task.sleep(for: settle - waited)
                waited = settle
                guard !Task.isCancelled, let self else { return }
                let covered = Self.coveredNow()
                if covered != broadcast.latest { broadcast.send(covered) }
            }
        }
    }

    private static func coveredNow() -> Set<DisplayIdentity> {
        coveredDisplays(
            windows: WindowList.onScreen(),
            displays: ConnectedDisplays.current(),
            ignoringOwners: WindowList.ownersThatCoverNothing()
        )
    }
}

/// The on-screen windows, by bounds, layer and owner. Window names would need
/// Screen Recording, so they are never asked for.
enum WindowList {
    static let dockBundleIdentifier = "com.apple.dock"

    /// The app itself, and the Dock, whose display-sized window sits above the
    /// normal level on every display. The Dock is found by its bundle
    /// identifier on each read, since it gets a new process when it restarts.
    static func ownersThatCoverNothing() -> Set<Int32> {
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).map(\.processIdentifier)
        return Set(dock).union([ProcessInfo.processInfo.processIdentifier])
    }

    static func onScreen() -> [WindowListEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let owner = window[kCGWindowOwnerPID as String] as? NSNumber
            else { return nil }
            return WindowListEntry(bounds: Rect(bounds), layer: layer.intValue, ownerPID: owner.int32Value)
        }
    }
}
