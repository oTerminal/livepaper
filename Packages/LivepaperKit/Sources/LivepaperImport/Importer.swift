import Foundation
import LivepaperCore

public enum ImportStage: String, Equatable, Sendable, CaseIterable {
    case fingerprint
    case probe
    /// The ffmpeg helper, for the files AVFoundation cannot open. Skipped for the rest.
    case convert
    /// Writing the optimised copy: a remux or a transcode, either of which leaves the timing clean.
    case normalise
    case validate
    case artefacts
    case commit
}

public struct ImportProgress: Equatable, Sendable {
    public let stage: ImportStage
    /// 0 to 1 within the stage. Nil when the stage cannot tell.
    public let fraction: Double?

    public init(stage: ImportStage, fraction: Double? = nil) {
        self.stage = stage
        self.fraction = fraction
    }
}

/// The two ways an optimised copy is written.
public enum CopyWriter: Equatable, Sendable {
    case remux
    case transcode
}

/// How an import got to its optimised copy, for the diagnostics export and the tests.
public struct ImportReport: Equatable, Sendable {
    /// What the planner made of the source file.
    public var plan: ImportPlan
    /// What wrote the optimised copy that was kept.
    public var writtenBy: CopyWriter
    /// The validator's findings on the optimised copy.
    public var seam: LoopSeamReport

    public init(plan: ImportPlan, writtenBy: CopyWriter, seam: LoopSeamReport) {
        self.plan = plan
        self.writtenBy = writtenBy
        self.seam = seam
    }
}

public enum ImportOutcome: Equatable, Sendable {
    case imported(Wallpaper, ImportReport)
    /// The same source file was imported before, as this wallpaper. Nothing was written.
    case duplicate(of: Wallpaper)
}

public enum ImportError: Error, Equatable, Sendable {
    case rejected(RejectReason)
    /// The file needs the ffmpeg helper and there is none.
    case helperMissing
    /// The helper converted the file, and AVFoundation cannot read what it made.
    case helperOutputUnreadable
    /// The optimised copy would not loop without a gap, even transcoded. The report says what was wrong with it.
    case loopSeam(LoopSeamReport)
}

public enum ImportEvent: Equatable, Sendable {
    case progress(ImportProgress)
    case finished(ImportOutcome)
}

/// What to do with an optimised copy once the validator has read it: a
/// failure sends the file back through transcode once, then rejects.
public enum SeamVerdict: Equatable, Sendable {
    case keep
    case transcodeAgain
    case reject
}

public func judgeAttempt(_ report: LoopSeamReport, transcodesSoFar retries: Int) -> SeamVerdict {
    if report.passes { return .keep }
    return retries == 0 ? .transcodeAgain : .reject
}

/// What runs an import: the real `Importer`, or a fake one in tests and the app's fakes run.
public protocol ImportRunning: Sendable {
    /// The import as a stream of events, ending with `.finished`. Letting go of the stream cancels the import.
    func events(importing candidate: ImportCandidate) -> AsyncThrowingStream<ImportEvent, any Error>
}

extension Importer: ImportRunning {}

/// Turns a source file into a wallpaper in the library: one optimised copy
/// that loops without a gap, a poster and a hover preview.
///
/// The source file is only ever read. Everything is built in `.staging/<id>/`
/// and renamed into place at the end, and a failed or cancelled import leaves
/// nothing behind.
public struct Importer: Sendable {
    public let location: LibraryLocation
    let library: any ImportLibrary
    let ffmpeg: FFmpegTool?
    let validate: @Sendable (URL) async throws -> LoopSeamReport
    let makeID: @Sendable () -> WallpaperID
    let now: @Sendable () -> Date

    public init(
        location: LibraryLocation,
        library: any ImportLibrary,
        ffmpeg: FFmpegTool?,
        validate: @escaping @Sendable (URL) async throws -> LoopSeamReport = { try await validateLoopSeam(of: $0) },
        makeID: @escaping @Sendable () -> WallpaperID = { WallpaperID(uuid: UUID()) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.location = location
        self.library = library
        self.ffmpeg = ffmpeg
        self.validate = validate
        self.makeID = makeID
        self.now = now
    }

    /// The import as a stream of events, ending with `.finished`. Letting go of the stream cancels the import.
    public func events(importing candidate: ImportCandidate) -> AsyncThrowingStream<ImportEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let outcome = try await run(candidate) { continuation.yield(.progress($0)) }
                    continuation.yield(.finished(outcome))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent
    public func run(
        _ candidate: ImportCandidate, progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportOutcome {
        let source = candidate.source

        progress(ImportProgress(stage: .fingerprint))
        let fingerprint = try await fingerprint(of: source)
        if let existing = try await library.wallpaper(withFingerprint: fingerprint) { return .duplicate(of: existing) }

        progress(ImportProgress(stage: .probe))
        let probe = try await probeSource(at: source)
        let plan = planImport(probe)
        if case .reject(let reason) = plan { throw ImportError.rejected(reason) }
        if plan == .ffmpeg, ffmpeg == nil { throw ImportError.helperMissing }

        let id = makeID()
        let staging = location.staging.appending(path: id.description, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let staged = try await build(source, probe: probe, plan: plan, in: staging, progress: progress)
            let wallpaper = try wallpaper(id: id, name: candidate.name, fingerprint: fingerprint, staged: staged)

            try Task.checkCancellation()
            progress(ImportProgress(stage: .commit))
            // From here the import runs to its end: a cancel must not land between the rename and the manifest.
            return try await commit(staging, as: wallpaper, report: staged.report)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    // MARK: Stages

    private struct Staged {
        var details: WallpaperDetails
        var hasHoverPreview: Bool
        var report: ImportReport
    }

    private enum File {
        static let optimisedCopy = "wallpaper.mov"
        static let poster = "poster.heic"
        static let hoverPreview = "hover.mov"
        static let intermediate = "ffmpeg.mov"
    }

    private func build(
        _ source: URL, probe: ProbeResult, plan: ImportPlan, in staging: URL, progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> Staged {
        // What the optimised copy is written from: the source file, or what ffmpeg made of it.
        var material = (url: source, probe: probe, plan: plan)
        let intermediate = staging.appending(path: File.intermediate)
        if plan == .ffmpeg, let ffmpeg {
            progress(ImportProgress(stage: .convert, fraction: 0))
            try await ffmpeg.convert(source, to: intermediate) { progress(ImportProgress(stage: .convert, fraction: $0)) }
            let converted = try await probeSource(at: intermediate)
            material = (intermediate, converted, planImport(converted))
        }
        if case .reject(let reason) = material.plan { throw ImportError.rejected(reason) }
        guard let video = material.probe.video, material.plan != .ffmpeg else { throw ImportError.helperOutputUnreadable }

        let optimisedCopy = staging.appending(path: File.optimisedCopy)
        let rate = FrameRate.forOptimisedCopy(of: video)
        var writtenBy: CopyWriter = material.plan == .remux ? .remux : .transcode
        var transcodes = 0
        var seam: LoopSeamReport
        while true {
            let report: @Sendable (Double) -> Void = { progress(ImportProgress(stage: .normalise, fraction: $0)) }
            report(0)
            switch writtenBy {
            case .remux: try await remux(material.url, to: optimisedCopy, rate: rate, progress: report)
            case .transcode: try await transcode(material.url, to: optimisedCopy, as: .optimisedCopy(rate: rate), progress: report)
            }

            progress(ImportProgress(stage: .validate))
            seam = try await validate(optimisedCopy)
            let verdict = judgeAttempt(seam, transcodesSoFar: transcodes)
            if verdict == .keep { break }
            guard verdict == .transcodeAgain else { throw ImportError.loopSeam(seam) }
            try FileManager.default.removeItem(at: optimisedCopy)
            writtenBy = .transcode
            transcodes += 1
        }
        // The library keeps only the optimised copy: what ffmpeg made must not be renamed into place with it.
        if FileManager.default.fileExists(atPath: intermediate.path) { try FileManager.default.removeItem(at: intermediate) }

        progress(ImportProgress(stage: .artefacts))
        try await makePoster(of: optimisedCopy, at: staging.appending(path: File.poster))
        let hasHoverPreview = try await makeHoverPreview(of: optimisedCopy, rate: rate, at: staging.appending(path: File.hoverPreview))

        return Staged(
            details: try await details(of: optimisedCopy),
            hasHoverPreview: hasHoverPreview,
            report: ImportReport(plan: plan, writtenBy: writtenBy, seam: seam)
        )
    }

    /// The hover preview is a nicety. One that cannot be made, or would not
    /// loop, is left out, and the wallpaper is imported without it.
    private func makeHoverPreview(of optimisedCopy: URL, rate: FrameRate, at destination: URL) async throws -> Bool {
        do {
            try await transcode(optimisedCopy, to: destination, as: .hoverPreview(of: rate)) { _ in }
            if try await validate(destination).passes { return true }
        } catch is CancellationError {
            throw CancellationError()
        } catch {}
        try? FileManager.default.removeItem(at: destination)
        return false
    }

    private func details(of optimisedCopy: URL) async throws -> WallpaperDetails {
        guard let video = try await probeSource(at: optimisedCopy).video else { throw MediaError.noVideoTrack }
        let byteCount = try FileManager.default.attributesOfItem(atPath: optimisedCopy.path)[.size] as? Int ?? 0
        let codec = VideoProbe.keptCodecs[video.codec] ?? video.codec
        return WallpaperDetails(
            duration: video.duration, width: video.width, height: video.height,
            frameRate: (video.nominalFrameRate * 100).rounded() / 100, codec: codec, byteCount: byteCount
        )
    }

    private func wallpaper(id: WallpaperID, name: String, fingerprint: Fingerprint, staged: Staged) throws -> Wallpaper {
        let folder = "\(location.wallpapers.lastPathComponent)/\(id)"
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Wallpaper(
            id: id,
            name: name.isEmpty ? "Wallpaper" : name,
            importedAt: now(),
            fingerprint: fingerprint,
            optimisedCopy: try LibraryPath("\(folder)/\(File.optimisedCopy)"),
            poster: try LibraryPath("\(folder)/\(File.poster)"),
            hoverPreview: staged.hasHoverPreview ? try LibraryPath("\(folder)/\(File.hoverPreview)") : nil,
            details: staged.details
        )
    }

    /// The rename first, the manifest after it: a manifest never names files
    /// that are not there. If the manifest cannot be saved, the files go again.
    private func commit(_ staging: URL, as wallpaper: Wallpaper, report: ImportReport) async throws -> ImportOutcome {
        let folder = location.wallpapers.appending(path: wallpaper.id.description, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: location.wallpapers, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staging, to: folder)
        do {
            try await library.insert(wallpaper)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            // Another import of the same file got there first.
            if case LibraryError.duplicate(let id) = error, let winner = try? await library.wallpaper(withID: id) {
                return .duplicate(of: winner)
            }
            throw error
        }
        return .imported(wallpaper, report)
    }
}
