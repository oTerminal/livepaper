import AppKit
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
            LibraryPlaceholder()
                .environment(delegate.model)
                .libraryWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        // An agent opens no window at launch, and none comes back from the last run.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            // Import, never Add: files and folders, as the Import button takes them.
            CommandGroup(replacing: .newItem) {
                Button("Import…") { delegate.model.chooseFilesToImport() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsPlaceholder()
                .environment(delegate.model)
                .background(SceneActionsReader(windows: delegate.windows))
                .launchOptions(delegate.options)
        }
    }
}

/// Makes the model, on the real host or, with `-fakes YES`, on the fakes; puts
/// the menu-bar item up at launch; and holds Quit until the stopped render state
/// is written, so that each display is left holding its poster (record 0003).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options = LaunchOptions.current
    let windows = AppWindows()
    let model: AppModel
    /// The fakes run's world, which its Fakes menu drives. Nil when wired: then
    /// nothing fake is made, and the model drives the real wallpaper.
    private let fakes: Fakes?
    private var menuBarItem: MenuBarItem?
    /// Takes the fakes run's commands from a script; nil when wired.
    private var remote: FakesRemote?

    override init() {
        let options = LaunchOptions.current
        if options.isFakes {
            let fakes = Fakes(library: options.fakeLibrary)
            self.fakes = fakes
            model = AppModel(services: fakes.makeServices())
        } else {
            fakes = nil
            model = AppModel(services: .wired())
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = options.nsAppearance
        let popover = PopoverPlaceholder()
            .environment(model)
            .environment(windows)
            .background(SceneActionsReader(windows: windows))
        let item = MenuBarItem(options: options, menu: menu, content: popover)
        windows.willOpenWindow = { [weak item] in item?.closePopover() }
        windows.didCloseLibrary = { [model] in model.libraryWindowDidClose() }
        menuBarItem = item
        if let fakes {
            remote = FakesRemote { [weak self] verb, rest in self?.perform(verb, rest, fakes: fakes) }
        }
        model.launch()
    }

    /// A command from `Tools/pr-media/fakes.sh`. The popover opens and closes with
    /// motion, as a click would, so that a recording shows it.
    private func perform(_ verb: String, _ rest: String, fakes: Fakes) {
        switch (verb, rest) {
        case ("open", "popover"): menuBarItem?.openPopover(animated: true)
        case ("close", "popover"): menuBarItem?.closePopover(animated: true)
        case ("open", "library"): windows.openLibrary()
        case ("open", "settings"): windows.openSettings()
        case ("menu", let title):
            let menu = fakes.menu(model: model) { [weak self] in self?.menuBarItem?.openPopover(animated: true) }
            if !menu.performItem(titled: title) { AppLog.logger.notice("fakes: no menu item \(title, privacy: .public)") }
        case ("quit", _): NSApp.terminate(nil)
        default: AppLog.logger.notice("fakes: unknown command \(verb, privacy: .public) \(rest, privacy: .public)")
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

    /// Closing the library window leaves the app in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.quit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
