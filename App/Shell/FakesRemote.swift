import AppKit

/// Lets a script drive the fakes run, and only the fakes run: the manual script
/// and the PR's media need the popover, the windows and the Fakes menu on cue,
/// and on a Mac whose menu-bar item sits under the notch nothing can click them.
///
///     Tools/pr-media/fakes.sh open popover
///     Tools/pr-media/fakes.sh menu "Recovering at Restart Agent"
///
/// A command is words: a verb, then what it acts on. Unknown commands are logged and ignored.
final class FakesRemote {
    /// The distributed notification a command arrives by; its object is the command.
    static let notification = Notification.Name("app.livepaper.fakes.command")

    /// Kept for the life of the run, as the remote is.
    private var observer: (any NSObjectProtocol)?

    init(perform: @escaping @MainActor (_ verb: String, _ rest: String) -> Void) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification, object: nil, queue: .main
        ) { notification in
            guard let command = notification.object as? String else { return }
            let words = command.split(separator: " ", maxSplits: 1).map(String.init)
            guard let verb = words.first else { return }
            MainActor.assumeIsolated { perform(verb, words.count > 1 ? words[1] : "") }
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
