import AppKit
import SwiftUI

/// A menu-bar agent (`LSUIElement`) with a library window, which brings the Dock
/// icon while it is open, and Settings. The menu-bar item is AppKit's
/// (`MenuBarItem`), so its popover can be glass and run the design system's motion.
@main
struct LivepaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Library", id: AppWindows.libraryID) {
            LibraryPlaceholder()
                .libraryWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        // An agent opens no window at launch, and none comes back from the last run.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsPlaceholder()
                .background(SceneActionsReader(windows: delegate.windows))
                .launchOptions(delegate.options)
        }
    }
}

/// Puts the menu-bar item up at launch, and holds Quit until the stopped render
/// state is written, so that each display is left holding its poster (record 0003).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options = LaunchOptions.current
    let windows = AppWindows()
    /// The real render host and sensors; never made in the fakes run, so that
    /// nothing touches the wallpaper, `render-state.json` or the extension.
    private var session: DeveloperSession?
    private var menuBarItem: MenuBarItem?
    /// The fakes run's stand-in for the probe, which it has no host to switch.
    private var isFakePlaybackMetricsOn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = options.nsAppearance
        if !options.isFakes {
            session = DeveloperSession()
        }
        let popover = PopoverPlaceholder()
            .environment(windows)
            .background(SceneActionsReader(windows: windows))
        let item = MenuBarItem(options: options, menu: menu, content: popover)
        windows.willOpenWindow = { [weak item] in item?.closePopover() }
        menuBarItem = item
        session?.launch()
    }

    private var menu: MenuBarItem.Menu {
        if let session {
            return MenuBarItem.Menu(
                isPlaybackMetricsOn: { session.isPlaybackMetricsOn },
                setPlaybackMetrics: { session.setPlaybackMetrics($0) }
            )
        }
        return MenuBarItem.Menu(
            isPlaybackMetricsOn: { [weak self] in self?.isFakePlaybackMetricsOn ?? false },
            setPlaybackMetrics: { [weak self] in self?.isFakePlaybackMetricsOn = $0 },
            fakes: { [weak self] in self?.fakesMenu() ?? NSMenu() }
        )
    }

    /// The fakes run's controls. The app model adds the fake host's status and the
    /// fake sensors; the popover can be opened from here, with its motion, where the
    /// menu bar is too full to show the item.
    private func fakesMenu() -> NSMenu {
        let menu = NSMenu(title: "Fakes")
        menu.addItem(NSMenuItem("Open Popover") { [weak self] in
            self?.menuBarItem?.openPopover()
        })
        return menu
    }

    /// Closing the library window leaves the app in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        Task {
            await session.quit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
