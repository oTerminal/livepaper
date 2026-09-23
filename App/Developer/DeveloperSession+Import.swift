import AppKit
import LivepaperCore
import LivepaperImport
import UniformTypeIdentifiers

extension DeveloperSession {
    var canImport: Bool { storedLibrary != nil && !isImporting }

    /// Asks for video files and imports them one after another. The importer
    /// runs off the main actor (`Importer.run` is `@concurrent`).
    func importVideos() {
        guard canImport, let storedLibrary else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Video"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.movie] + importableExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let files = panel.urls
        // The bundled helper, when the build had one (project.yml); without it, files only ffmpeg can open are refused.
        let importer = Importer(
            location: location,
            library: storedLibrary,
            ffmpeg: FFmpegTool.locate(replacement: nil, bundled: Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"))
        )
        isImporting = true
        Task {
            for file in files {
                await importFile(file, with: importer)
            }
            await reloadLibrary()
            isImporting = false
        }
    }

    private func importFile(_ file: URL, with importer: Importer) async {
        let candidate = ImportCandidate(source: file, name: file.deletingPathExtension().lastPathComponent)
        do {
            switch try await importer.run(candidate) {
            case .imported(let wallpaper, _):
                logger.notice("\(DeveloperLog.importFinished(wallpaper), privacy: .public)")
            case .duplicate(let wallpaper):
                logger.notice("\(DeveloperLog.importDuplicate(of: wallpaper), privacy: .public)")
            }
        } catch {
            logger.error("\(DeveloperLog.importFailed(file.lastPathComponent, error), privacy: .public)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "“\(file.lastPathComponent)” was not imported"
            alert.informativeText = String(describing: error)
            NSApp.activate()
            alert.runModal()
        }
    }
}
