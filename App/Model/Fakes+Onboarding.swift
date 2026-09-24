import Foundation
import LivepaperCore
import LivepaperSystem
import LivepaperTestSupport
import os

/// Which first launch the fakes run plays, for recording onboarding:
/// `-onboarding YES` (a fresh install), or `translocated`, `afterLeaving` or
/// `updated`. Without it, the fakes run is one that ran onboarding before.
enum FakeOnboarding: String {
    case fresh
    case translocated
    case afterLeaving
    case updated

    init?(argument: String) {
        switch argument.lowercased() {
        case "yes", "true", "1", "fresh": self = .fresh
        case "translocated": self = .translocated
        case "afterleaving": self = .afterLeaving
        case "updated": self = .updated
        default: return nil
        }
    }

    /// What the preferences would hold.
    var record: OnboardingRecord {
        switch self {
        case .fresh, .translocated: OnboardingRecord()
        case .afterLeaving: OnboardingRecord(onboardedVersion: "0.1.0 (1)", hasLeft: true)
        case .updated: OnboardingRecord(onboardedVersion: "0.0.9 (1)")
        }
    }

    /// Whether Livepaper is the system wallpaper when the run starts.
    var isSelected: Bool { self == .updated }
}

extension Fakes {
    /// Onboarding on the fakes: the record in memory, the bundle's samples, and a
    /// library on disk only when the scenario says a Livepaper ran before.
    func onboardingServices() -> OnboardingServices {
        OnboardingServices(
            record: onboardingRecord,
            isTranslocated: onboarding == .translocated,
            ranBefore: onboarding.map { $0 == .afterLeaving || $0 == .updated } ?? true,
            version: BundleVersion.main.words,
            samples: SampleWallpaper.bundled(),
            showApplicationsFolder: { Fakes.logger.notice("fakes: the Applications folder would open in the Finder") }
        )
    }

    static let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: "fakes")
}

/// Selecting Livepaper on the fakes: the real `Selection`, over a store,
/// pluginkit, an agent and a pane that touch nothing on the Mac. A select writes
/// the fake store; restarting the fake agent makes the fake host's next heartbeat
/// say live, as the extension acquiring its desktop surface does. The fakes
/// remote can make the store unreadable, for the pane's fallback, and stand in
/// for the user's click there.
final class FakeSelectionWorld {
    let store: FakeWallpaperStore
    let pane = FakeWallpaperPane()
    let selection: Selection
    private let host: FakeRenderHost

    init(host: FakeRenderHost) {
        self.host = host
        store = FakeWallpaperStore(namesLivepaper: host.isSelected)
        selection = Selection(
            host: host,
            store: store,
            extensions: FakeExtensionListing(),
            agent: FakeWallpaperAgent(host: host, store: store),
            restartStore: FakeAgentRestartStore(),
            pane: pane,
            clock: SystemWallClock(),
            logger: Fakes.logger
        )
    }

    /// The user choosing "Livepaper" in System Settings: the next heartbeat says live.
    func chooseLivepaperInPane() {
        store.namesLivepaper = true
        host.isSelected = true
        host.heartbeatLater()
    }

    /// The user choosing another wallpaper in System Settings: the next heartbeat says not selected.
    func chooseAnotherInPane() {
        store.namesLivepaper = false
        host.isSelected = false
        host.heartbeatLater()
    }
}

/// WallpaperAgent's store, as far as selecting needs one: whether it names
/// Livepaper, and whether it can be read.
final class FakeWallpaperStore: WallpaperStoreEditing {
    var namesLivepaper: Bool
    var isReadable = true
    private var hasKeptCopy = false

    init(namesLivepaper: Bool) {
        self.namesLivepaper = namesLivepaper
    }

    func select(at now: Date) throws(WallpaperStoreError) -> WallpaperStoreEdit {
        guard isReadable else { throw .unreadable(.store) }
        guard !namesLivepaper else { return WallpaperStoreEdit(changed: 0, desktopEntries: 2) }
        namesLivepaper = true
        hasKeptCopy = true
        return WallpaperStoreEdit(changed: 2, desktopEntries: 2, keptCopy: true)
    }

    func deselect() throws(WallpaperStoreError) -> WallpaperStoreEdit {
        guard isReadable else { throw .unreadable(.store) }
        guard namesLivepaper else { return WallpaperStoreEdit(changed: 0, desktopEntries: 2) }
        guard hasKeptCopy else { throw .noKeptCopy }
        namesLivepaper = false
        return WallpaperStoreEdit(changed: 2, desktopEntries: 2)
    }

    func removeKeptCopy() {
        hasKeptCopy = false
    }
}

/// Lists the extension, as pluginkit does once it is installed.
final class FakeExtensionListing: ExtensionListing {
    func isListed(_ bundleIdentifier: String) async -> Bool { true }
}

/// A restart after a short while, as launchd brings the agent back; the host's
/// next heartbeat then says what the store names.
final class FakeWallpaperAgent: AgentRestarting {
    private let host: FakeRenderHost
    private let store: FakeWallpaperStore
    private var pid: Int32 = 400

    init(host: FakeRenderHost, store: FakeWallpaperStore) {
        self.host = host
        self.store = store
    }

    func restartAgent() async -> AgentRestartOutcome {
        try? await Task.sleep(for: .milliseconds(300))
        host.isSelected = store.namesLivepaper
        host.heartbeatLater()
        pid += 1
        return .restarted(previous: pid - 1, current: pid)
    }
}

/// In memory: the fakes never write the real app's preferences.
final class FakeAgentRestartStore: AgentRestartStore {
    var lastRestart: Date?
}

/// Opens nothing, and logs that it would have.
final class FakeWallpaperPane: WallpaperPaneOpening {
    private(set) var opened = 0

    func openWallpaperPane() -> Bool {
        opened += 1
        Fakes.logger.notice("fakes: System Settings would open at Wallpaper")
        return true
    }
}
