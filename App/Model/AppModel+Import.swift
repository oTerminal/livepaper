import AppKit
import DesignSystem
import Foundation
import LivepaperCore
import LivepaperImport
import UniformTypeIdentifiers

// Imports: a drop, the Import button and Command-O send every URL through
// `discoverSources`, the candidates wait in the `ImportList`, and one import
// runs at a time. The model is the importer's library, so an import's insert
// is saved like any other change.

extension AppModel {
    func wallpaper(withFingerprint fingerprint: Fingerprint) async throws -> Wallpaper? {
        library.wallpaper(withFingerprint: fingerprint)
    }

    func wallpaper(withID id: WallpaperID) async throws -> Wallpaper? {
        library[id]
    }

    /// Saved before it counts, then the displays follow; throws and does neither when it cannot be saved.
    func insert(_ wallpaper: Wallpaper) async throws {
        try change(library: library.inserting(wallpaper))
    }
}

extension AppModel {
    /// Files and folders, as dropped or chosen. A Wallpaper Engine folder gives
    /// its one video item; any other folder is searched. What is skipped, or
    /// cannot be read, says why in a toast; the rest join the import list.
    func importItems(at urls: [URL]) {
        guard canImport, !urls.isEmpty else { return }
        Task {
            let found = await Discovering.run(urls)
            guard canImport else { return }
            for skipped in found.skipped {
                showToast(skippedToastWords(skipped), systemImage: "exclamationmark.triangle")
            }
            for failure in found.failures {
                showToast(failedToastWords(name: failure.name, error: failure.error), systemImage: "exclamationmark.triangle")
            }
            guard !found.candidates.isEmpty else { return }
            perform(importList.enqueue(found.candidates, ids: found.candidates.map { _ in UUID() }))
        }
    }

    /// The Open panel, for the Import button and Command-O: files and folders,
    /// several at once. A sheet on the library window when that window is in
    /// front, since what is chosen goes into it; a panel of its own otherwise
    /// (Command-O from Settings).
    func chooseFilesToImport() {
        guard canImport else { return }
        let panel = NSOpenPanel()
        panel.title = "Import"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .gif, .folder] + importableExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        let chosen: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.importItems(at: panel.urls)
        }
        if let window = NSApp.keyWindow, window.isLibraryWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: chosen)
            AppLog.logger.notice("\(AppLog.choosingFiles(asSheet: true), privacy: .public)")
        } else {
            NSApp.activate()
            panel.begin(completionHandler: chosen)
            AppLog.logger.notice("\(AppLog.choosingFiles(asSheet: false), privacy: .public)")
        }
    }

    /// A row's cancel: a running import's stream is dropped, which stops it; a
    /// waiting row is taken away, and so is a failed one ("Remove from List").
    func cancelImport(_ row: ImportList.Row.ID) {
        perform(importList.cancel(row))
    }

    /// A failed row waits again where it is.
    func retryImport(_ row: ImportList.Row.ID) {
        perform(importList.retry(row))
    }

    /// Any plain toast; a delete's undo toast it replaces is final.
    func showToast(_ message: String, systemImage: String? = nil) {
        toasts.send(.show(ToastItem(message: message, systemImage: systemImage)))
    }

    // MARK: Running the list

    private func perform(_ effects: [ImportList.Effect]) {
        for effect in effects {
            switch effect {
            case .start(let id, let candidate):
                start(id, candidate)
            case .cancel(let id):
                guard runningImport?.id == id else { continue }
                runningImport?.task.cancel()
                runningImport = nil
            }
        }
        scheduleImportTick()
    }

    /// Reads the import's stream until it ends. Cancelling the task drops the stream, and that cancels the import.
    private func start(_ id: UUID, _ candidate: ImportCandidate) {
        guard let importer else { return }
        let events = importer.events(importing: candidate)
        let task = Task { [weak self] in
            do {
                for try await event in events {
                    self?.received(event, for: id)
                }
            } catch {
                self?.failed(id, candidate, error)
            }
            if self?.runningImport?.id == id {
                self?.runningImport = nil
            }
        }
        runningImport = (id, task)
    }

    private func received(_ event: ImportEvent, for id: UUID) {
        guard isRunning(id) else { return }
        let effects = importList.received(event, for: id, at: Date())
        if case .finished(let outcome) = event {
            switch outcome {
            case .imported(let wallpaper, _):
                AppLog.logger.notice("\(AppLog.importFinished(wallpaper), privacy: .public)")
            case .duplicate(let wallpaper):
                AppLog.logger.notice("\(AppLog.importDuplicate(of: wallpaper), privacy: .public)")
                showToast(duplicateToastWords(of: wallpaper), systemImage: "square.on.square")
            }
        }
        perform(effects)
    }

    private func failed(_ id: UUID, _ candidate: ImportCandidate, _ error: any Error) {
        guard isRunning(id) else { return }
        let effects = importList.failed(id, error: error, at: Date())
        if !(error is CancellationError) {
            AppLog.logger.error("\(AppLog.importFailed(candidate.name, error), privacy: .public)")
            showToast(failedToastWords(name: candidate.name, error: error), systemImage: "exclamationmark.triangle")
        }
        perform(effects)
    }

    /// Late news of a row that was cancelled changes nothing and says nothing.
    private func isRunning(_ id: UUID) -> Bool {
        guard let row = importList.rows.first(where: { $0.id == id }), case .running = row.state else { return false }
        return true
    }

    /// Finished rows, and failed rows Retry cannot help, leave `ImportList.finishedLifetime` after they ended.
    private func scheduleImportTick() {
        importTick?.cancel()
        importTick = nil
        guard let next = importList.nextTick else { return }
        importTick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            perform(importList.tick(at: Date()))
        }
    }
}

/// Discovery reads the disk, so it runs off the main actor.
private nonisolated enum Discovering {
    struct Found: Sendable {
        var candidates: [ImportCandidate] = []
        var skipped: [SkippedSource] = []
        var failures: [Failure] = []
    }

    /// A URL that could not be searched, named as a candidate would be.
    struct Failure: Sendable {
        let name: String
        let error: any Error
    }

    @concurrent
    static func run(_ urls: [URL]) async -> Found {
        var found = Found()
        for url in urls {
            do {
                let discovery = try discoverSources(at: url)
                found.candidates += discovery.candidates
                found.skipped += discovery.skipped
            } catch {
                found.failures.append(Failure(name: url.deletingPathExtension().lastPathComponent, error: error))
            }
        }
        return found
    }
}
