import Foundation
import LivepaperCore
import LivepaperImport

// Commands from the doors that are not the window (M7): Open With, the Dock,
// Services, the menu-bar drop, `livepaper://` links and the command socket.
// Every door's input becomes one `Command` (`EntryPoint`), and this runs it
// through the same actions the window's controls use, so the app stays the one
// writer. What is refused says why, in `CommandRefusal`'s words.

/// What a command can ask of the app beyond the model: its windows, and the
/// Steam account's name, which the diagnostics report leaves out.
struct CommandShell {
    var openLibrary: () -> Void
    var openSettings: () -> Void
    var steamAccount: () -> String?
}

extension AppModel {
    /// Runs a command from a door and answers it. A command that arrives
    /// before the launch has read the library and the displays waits for it.
    /// An import answers once its rows are done.
    func perform(_ command: Command, from door: EntryPoint, shell: CommandShell) async -> CommandReply {
        AppLog.logger.notice("\(AppLog.command(command, from: door), privacy: .public)")
        await untilReady()
        let reply = await run(command, shell: shell)
        if case .refused(let reason) = reply {
            AppLog.logger.notice("\(AppLog.commandRefused(command, reason: reason), privacy: .public)")
        } else {
            AppLog.logger.notice("\(AppLog.commandDone(command), privacy: .public)")
        }
        return reply
    }

    /// `status`: the host, the displays by name and what each shows, the library, Pause All and mute.
    var statusReport: StatusReport {
        StatusReport(
            host: hostStatus,
            displays: Dictionary(displays.map { ($0.identity, $0.name) }) { first, _ in first },
            library: library,
            state: state,
            isPausedAll: isPausedAll
        )
    }

    /// Returns once the launch has read the library and the display sensor has
    /// named the displays, and at once after that, or at quit. A door can hand
    /// over a command before either: a file opened with Livepaper arrives
    /// before the launch has finished.
    func untilReady() async {
        while !(isLaunched && areDisplaysKnown), !isQuitting, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func run(_ command: Command, shell: CommandShell) async -> CommandReply {
        // What reads, or opens a window, runs whatever the library's state.
        switch command {
        case .status: return .status(statusReport)
        case .diagnostics: return .diagnostics(await diagnosticsReport(steamAccount: shell.steamAccount()).text)
        case .library: shell.openLibrary()
        case .settings: shell.openSettings()
        case .import, .set, .pause, .resume, .next, .mute, .unmute:
            if isQuitting { return .refused(.quitting) }
            if libraryProblem != nil { return .refused(.libraryUnreadable) }
            do throws(CommandRefusal) {
                return try await carryOut(command)
            } catch {
                return .refused(error)
            }
        }
        return .done(message: nil)
    }

    /// The commands that change something, through the actions the window's controls use.
    private func carryOut(_ command: Command) async throws(CommandRefusal) -> CommandReply {
        switch command {
        case .import(let files, _): return await importing(files, for: command)
        case .set(let assignment, let target): try set(assignment, on: target)
        case .pause(let target): try setPaused(true, target)
        case .resume(let target): try setPaused(false, target)
        case .next(let target): return try moveOn(target)
        case .mute, .unmute: setMuted(command == .mute)
        case .status, .diagnostics, .library, .settings: break
        }
        return .done(message: nil)
    }

    /// Through the import list, as a drop is: the rows show in the library
    /// window, and the reply waits for them. With `setEverywhere`, the one
    /// wallpaper that resulted, new or already there, goes on every display.
    private func importing(_ files: [URL], for command: Command) async -> CommandReply {
        let enqueued = await enqueueImport(files)
        let sources = await outcomes(of: enqueued.rows) + enqueued.notListed
        if let wallpaper = command.wallpaperToSetEverywhere(resulting: sources.compactMap(\.wallpaper)), library[wallpaper] != nil {
            setOnAllDisplays(.wallpaper(wallpaper))
        }
        return command.importReply(sources)
    }

    private func set(_ assignment: Assignment, on target: DisplayTarget) throws(CommandRefusal) {
        try state.checking(assignment, in: library)
        switch target {
        case .all:
            setOnAllDisplays(assignment)
        case .display(let display):
            _ = try target.displays(connected: displays.map(\.identity))
            set(assignment, on: display)
        }
    }

    /// All is Pause All or Resume All; a display is that display's own pause.
    private func setPaused(_ isPaused: Bool, _ target: DisplayTarget) throws(CommandRefusal) {
        guard case .display(let display) = target else {
            return isPaused ? pauseAll() : resumeAll()
        }
        _ = try target.displays(connected: displays.map(\.identity))
        commit(state: state.settingPaused(isPaused, for: display))
    }

    /// Next on each display named that shows a playlist, paused or not.
    private func moveOn(_ target: DisplayTarget) throws(CommandRefusal) -> CommandReply {
        let moving = try state.displaysMovingOn(target, connected: displays.map(\.identity))
        for display in moving {
            next(on: display)
        }
        return .movedOn(moving.map { identity in
            (display: display(identity)?.name ?? identity.description, wallpaper: state.wallpaper(shownOn: identity, in: library)?.name)
        })
    }
}
