import AppKit

/// Lets a script drive the fakes run, and only the fakes run: the manual script
/// and the PR's media need the popover, the windows and the Fakes menu on cue,
/// and on a Mac whose menu-bar item sits under the notch nothing can click them.
///
///     Tools/pr-media/fakes.sh open popover
///     Tools/pr-media/fakes.sh menu "Recovering at Restart Agent"
///
/// A command is words: a verb, then what it acts on. Unknown commands are logged and ignored.
/// Two fakes runs at once keep apart by name: `-fakesRemote <name>` on the run,
/// `LIVEPAPER_FAKES=<name>` for the script.
final class FakesRemote {
    /// The distributed notification a command arrives by; its object is the command.
    static let notification = Notification.Name(
        "app.livepaper.fakes.command" + (LaunchOptions.current.fakesRemote.map { ".\($0)" } ?? "")
    )

    /// Kept for the life of the run, as the remote is.
    private var observer: (any NSObjectProtocol)?

    init(perform: @escaping @MainActor (_ verb: String, _ rest: String) -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification, object: nil, queue: .main
        ) { notification in
            guard let command = notification.object as? String else { return }
            let words = command.split(separator: " ", maxSplits: 1).map(String.init)
            guard let verb = words.first else { return }
            let rest = words.count > 1 ? words[1] : ""
            // From a timer on the run loop, not from this main-queue callout: Quit
            // waits for the model in a nested run loop, which cannot run the main
            // queue from inside one of its own callouts, so the model's quit never
            // ran and `fakes.sh quit` left the app hung.
            let timer = Timer(timeInterval: 0, repeats: false) { _ in
                MainActor.assumeIsolated { perform(verb, rest) }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}

extension NSMenu {
    /// Chooses the item with this title, in this menu or any submenu, as a click would.
    /// Answers whether there was one.
    @discardableResult
    func performItem(titled title: String) -> Bool {
        for (index, item) in items.enumerated() {
            if item.title == title, item.isEnabled, item.action != nil {
                performActionForItem(at: index)
                return true
            }
            if let submenu = item.submenu, submenu.performItem(titled: title) { return true }
        }
        return false
    }
}
