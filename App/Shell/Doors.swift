import AppKit
import LivepaperCore
import LivepaperSystem

/// The ways into the app that are not its window (M7): Open With and the
/// Dock, `livepaper://` links, "Set as Live Wallpaper" in the Services menu,
/// files dropped on the menu-bar item, and the command socket the `livepaper`
/// tool talks to. Each turns what it is handed into one `Command`
/// (`EntryPoint`), which the model runs as the window's controls run the same
/// actions. It is `NSApp.servicesProvider`, which is why it is an `NSObject`.
final class Doors: NSObject {
    private let model: AppModel
    private let windows: AppWindows
    private let workshop: WorkshopModel
    private var server: CommandServer?

    init(model: AppModel, windows: AppWindows, workshop: WorkshopModel) {
        self.model = model
        self.windows = windows
        self.workshop = workshop
    }

    private var shell: CommandShell {
        CommandShell(
            openLibrary: { [windows] in windows.openLibrary() },
            openSettings: { [windows] in windows.openSettings() },
            steamAccount: { [workshop] in workshop.account }
        )
    }

    // MARK: LaunchServices

    /// `application(_:open:)`: files from Open With, or dropped on the Dock
    /// icon (there only while the window is open, the app being an agent),
    /// and `livepaper://` links.
    func open(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            hand(files, to: Self.isFromTheDock ? .dock : .openWith)
        }
        for link in urls where !link.isFileURL {
            open(link: link)
        }
    }

    /// Files handed to a door that makes an import of them.
    func hand(_ files: [URL], to door: EntryPoint) {
        AppLog.logger.notice("\(AppLog.handed(files.count, to: door), privacy: .public)")
        guard let command = door.command(importing: files) else { return }
        run(command, from: door)
    }

    /// Anything can open a link, a web page included: a rejection is logged and
    /// goes no further, and an import is asked about in the library window first.
    private func open(link: URL) {
        let command: Command
        do throws(CommandRejection) {
            command = try EntryPoint.urlScheme.command(from: link)
        } catch {
            AppLog.logger.error("\(AppLog.linkRefused(error), privacy: .public)")
            return
        }
        if EntryPoint.urlScheme.needsConfirmation(command) {
            confirm(command)
        } else {
            run(command, from: .urlScheme)
        }
    }

    /// Runs a command. A link's `diagnostics` has no one to answer, so its report goes on the clipboard.
    private func run(_ command: Command, from door: EntryPoint) {
        Task {
            let reply = await model.perform(command, from: door, shell: shell)
            if door == .urlScheme, case .diagnostics(let text) = reply {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                AppLog.logger.notice("\(AppLog.diagnosticsCopied, privacy: .public)")
            }
        }
    }

    /// The import a link asked for, named in an alert on the library window: Import or Cancel.
    private func confirm(_ command: Command) {
        guard case .import(let files, let setEverywhere) = command else { return }
        AppLog.logger.notice("\(AppLog.confirming(command), privacy: .public)")
        let words = ImportConfirmation(files: files, setEverywhere: setEverywhere, home: NSHomeDirectory())
        Task {
            // A link that launched the app arrives before the scenes are up.
            await model.untilReady()
            windows.openLibrary()
            guard let window = await libraryWindow() else {
                AppLog.logger.error("\(AppLog.noLibraryWindow, privacy: .public)")
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = words.title
            alert.informativeText = words.message
            alert.addButton(withTitle: words.importTitle)
            alert.addButton(withTitle: "Cancel")
            let isConfirmed = await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
            AppLog.logger.notice("\(AppLog.confirmed(isConfirmed), privacy: .public)")
            if isConfirmed {
                run(command, from: .urlScheme)
            }
        }
    }

    /// The library window, once SwiftUI has put it up: within a second or so of asking.
    private func libraryWindow() async -> NSWindow? {
        for _ in 0..<40 {
            if let window = NSApp.windows.first(where: { $0.isLibraryWindow && $0.isVisible }) { return window }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Whether the files being opened were dropped on the Dock icon, from the
    /// Apple event that carries them; otherwise it is Open With, or a drop on
    /// the app in the Finder, which is the same door.
    private static var isFromTheDock: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let sender = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: sender)?.bundleIdentifier == "com.apple.dock"
    }

    // MARK: Services

    /// "Set as Live Wallpaper" (`NSServices` in `project.yml`, whose `NSMessage` names this).
    @objc func setAsLiveWallpaper(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !files.isEmpty else {
            error.pointee = "Livepaper was handed no files to import."
            return
        }
        hand(files, to: .services)
    }

    // MARK: The command socket

    /// Opens the socket once the launch has read the library, for the `livepaper` tool.
    func openSocket(at socket: URL) {
        let server = CommandServer(socket: socket) { [weak self] command in
            guard let self else { return .refused(.quitting) }
            return await model.perform(command, from: .commandSocket, shell: shell)
        }
        Task {
            await model.untilReady()
            guard self.server == nil, !model.isQuitting else { return }
            do {
                try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
                try server.start()
                self.server = server
                AppLog.logger.notice("\(AppLog.socketOpened(at: socket), privacy: .public)")
            } catch {
                AppLog.logger.error("\(AppLog.socketNotOpened(error), privacy: .public)")
            }
        }
    }

    /// At quit: the socket file goes, and the tool finds no one there.
    func closeSocket() {
        guard let server else { return }
        server.stop()
        self.server = nil
        AppLog.logger.notice("\(AppLog.socketClosed, privacy: .public)")
    }

    // MARK: The fakes run

    /// A door driven from `Tools/pr-media/fakes.sh`, where nothing can drop a
    /// file or open a link on the fakes run alone:
    ///
    ///     door link livepaper://next | door socket livepaper://status
    ///     door services <file> | door drop <file> | door open <file> | door dock <file>
    ///
    /// A file is a path, or the name of one of the Fakes menu's sample files,
    /// or `samples` for them all. `socket` runs the command as the socket
    /// would and logs its reply. Answers whether it was one of these.
    func performFake(_ rest: String, samples: () -> [URL]) -> Bool {
        let words = rest.split(separator: " ", maxSplits: 1).map(String.init)
        guard let kind = words.first, words.count == 2 else { return false }
        let argument = words[1]
        switch kind {
        case "link":
            guard let link = URL(string: argument) else { return false }
            open(link: link)
        case "socket":
            Task {
                let command: Command
                do throws(CommandRejection) {
                    command = try EntryPoint.commandSocket.command(from: argument)
                } catch {
                    AppLog.logger.notice("fakes: socket refused \(error.kind, privacy: .public)")
                    return
                }
                let reply = await model.perform(command, from: .commandSocket, shell: shell)
                // An import's reply names its source files: the model has logged it by counts.
                if case .import = command { return }
                let line = (try? reply.line()).flatMap { String(bytes: $0, encoding: .utf8) } ?? "unreadable"
                AppLog.logger.notice("fakes: socket reply \(line, privacy: .public)")
            }
        default:
            let doors: [String: EntryPoint] = ["services": .services, "drop": .menuBarDrop, "open": .openWith, "dock": .dock]
            guard let door = doors[kind] else { return false }
            let files = argument == "samples" ? samples()
                : argument.hasPrefix("/") ? [URL(filePath: argument)]
                : samples().filter { $0.lastPathComponent == argument }
            guard !files.isEmpty else { return false }
            hand(files, to: door)
        }
        return true
    }
}
