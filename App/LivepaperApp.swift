import AppKit
import DesignSystem
import SwiftUI

/// A menu-bar agent (`LSUIElement`) with a library window, which brings the Dock
/// icon while it is open, and Settings. The menu-bar item is AppKit's
/// (`MenuBarItem`), so its popover can be glass and run the design system's motion.
/// Every scene reads the one `AppModel` from its environment.
@main
struct LivepaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Library", id: AppWindows.libraryID) {
            LibraryWindow()
                .environment(delegate.model)
                .environment(delegate.workshop)
                .libraryWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        .defaultSize(width: 1180, height: 760)
        // An agent opens no window at launch, and none comes back from the last run.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            // Import, never Add: files and folders, as the Import button takes them.
            CommandGroup(replacing: .newItem) {
                Button("Import…") { delegate.model.chooseFilesToImport() }
                    .keyboardShortcut("o")
                Button("Wallpaper Engine Workshop") { delegate.windows.openWorkshop() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                DeleteWallpaperCommand(model: delegate.model)
            }
        }

        // Record 0009: Steam's Workshop pages, and Get.
        Window("Wallpaper Engine Workshop", id: AppWindows.workshopID) {
            WorkshopWindow()
                .environment(delegate.model)
                .environment(delegate.workshop)
                .workshopWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        .defaultSize(width: 1180, height: 820)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // M7: first-run onboarding, opened at launch when the preferences say it has not run.
        Window("Welcome to Livepaper", id: AppWindows.onboardingID) {
            OnboardingWindow()
                .environment(delegate.model)
                .environment(delegate.onboarding)
                .onboardingWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.center) }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(delegate.model)
                .environment(delegate.workshop)
                .background(SceneActionsReader(windows: delegate.windows))
                .launchOptions(delegate.options)
        }
    }
}

/// Makes the model, on the real host or, with `-fakes YES`, on the fakes; puts
/// the menu-bar item up at launch; and holds Quit until the stopped render state
/// is written, so that each display is left holding its poster (record 0003).
///
/// A translocated launch (M7) shows the move card and nothing else: no
/// menu-bar item, no model launch, so no library read, host, sensors, hotkeys
/// or socket, no doors, and nothing written at quit. Closing the card quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options = LaunchOptions.current
    let windows = AppWindows()
    let model: AppModel
    /// The Workshop (record 0009): Valve's steamcmd, or the fakes' stand-in.
    let workshop: WorkshopModel
    /// `livepaper://` links and the command socket (M7).
    let doors: Doors
    /// First-run onboarding (M7), decided as the app starts.
    let onboarding: Onboarding
    /// The fakes run's world, which its Fakes menu drives. Nil when wired: then
    /// nothing fake is made, and the model drives the real wallpaper.
    private let fakes: Fakes?
    private var menuBarItem: MenuBarItem?
    /// Takes the fakes run's commands from a script; nil when wired.
    private var remote: FakesRemote?

    override init() {
        let options = LaunchOptions.current
        if options.isFakes {
            let fakes = Fakes(library: options.fakeLibrary, onboarding: options.onboarding)
            self.fakes = fakes
            model = AppModel(services: fakes.makeServices())
        } else {
            fakes = nil
            model = AppModel(services: .wired())
        }
        workshop = WorkshopModel(services: options.isFakes ? .fakes() : .wired(), library: model)
        doors = Doors(model: model, windows: windows, workshop: workshop)
        onboarding = Onboarding(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = options.nsAppearance
        if let fakes {
            remote = FakesRemote { [weak self] verb, rest in self?.perform(verb, rest, fakes: fakes) }
        }
        guard startsLivepaper else {
            AppLog.logger.notice("\(AppLog.translocatedLaunch, privacy: .public)")
            // A turn later, once SwiftUI has its scenes up.
            Task { [windows] in windows.openOnboarding() }
            return
        }
        let popover = PopoverView()
            .environment(model)
            .environment(windows)
            .background(SceneActionsReader(windows: windows))
        // The popover holds cards of `Radius.card`: 4 pt keeps them concentric with its 20 pt corners.
        let item = MenuBarItem(options: options, menu: menu, contentPadding: Spacing.tight, content: popover)
        windows.willOpenWindow = { [weak item] in item?.closePopover() }
        windows.didCloseLibrary = { [model] in model.libraryWindowDidClose() }
        workshop.showWorkshop = { [windows] in windows.openWorkshop() }
        menuBarItem = item
        watchHotkeys()
        model.launch()
        if onboarding.shows {
            // A turn later, once SwiftUI has its scenes up.
            Task { [windows] in windows.openOnboarding() }
        }
        if let socket = model.services.commandSocket {
            doors.openSocket(at: socket)
        }
    }

    /// `livepaper://` links. A link that launched the app arrives before
    /// `applicationDidFinishLaunching`; the model runs it once the launch has
    /// read the library. A file is left, with a log line: importing is done in
    /// the app's window alone.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard startsLivepaper else {
            AppLog.logger.notice("\(AppLog.translocatedDoor(urls.count), privacy: .public)")
            return
        }
        doors.open(urls)
    }

    /// False on a translocated launch, which shows the move card alone and starts nothing.
    private var startsLivepaper: Bool { onboarding.plan.startsLivepaper }

    /// A command from `Tools/pr-media/fakes.sh`. The popover opens and closes with
    /// motion, as a click would, so that a recording shows it.
    private func perform(_ verb: String, _ rest: String, fakes: Fakes) {
        switch (verb, rest) {
        case ("open", "popover"): menuBarItem?.openPopover(animated: true)
        case ("close", "popover"): menuBarItem?.closePopover(animated: true)
        case ("open", "library"): windows.openLibrary()
        case ("open", "settings"): windows.openSettings()
        case ("open", "workshop"): windows.openWorkshop()
        case ("menu", let title):
            let menu = fakes.menu(model: model) { [weak self] in self?.menuBarItem?.openPopover(animated: true) }
            if !menu.performItem(titled: title) { AppLog.logger.notice("fakes: no menu item \(title, privacy: .public)") }
        case ("quit", _): NSApp.terminate(nil)
        default:
            let commands = FakesCommands(model: model, doors: doors)
            let system = FakesSystemCommands(onboarding: onboarding, fakes: fakes, windows: windows)
            guard !commands.perform(verb, rest), !system.perform(verb, rest) else { return }
            AppLog.logger.notice("fakes: unknown command \(verb, privacy: .public) \(rest, privacy: .public)")
        }
    }

    /// Log Playback Metrics and Quit; the fakes run adds its Fakes submenu.
    private var menu: MenuBarItem.Menu {
        let fakesMenu: (() -> NSMenu)? = fakes.map { fakes in
            { [weak self, model] in
                fakes.menu(model: model) { self?.menuBarItem?.openPopover() }
            }
        }
        return MenuBarItem.Menu(
            isPlaybackMetricsOn: { [model] in model.isPlaybackMetricsOn },
            setPlaybackMetrics: { [model] in model.setPlaybackMetrics($0) },
            fakes: fakesMenu
        )
    }

    /// Closing the library window leaves the app in the menu bar. Closing the
    /// move card quits, since a translocated launch has nothing else.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !startsLivepaper
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Nothing was started, so there is no stopped state to write.
        guard startsLivepaper else { return .terminateNow }
        // steamcmd runs in a session of its own, and would outlive the app.
        workshop.stopAll()
        doors.closeSocket()
        Task {
            await model.quit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
