import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// usage: recordwindow <window id> <seconds> <out.mov | out.mp4>
//
// Records one window, by the id winid prints, for <seconds> at the window's native pixel size
// (2x on a Retina display) and up to 60 fps, as HEVC. The filter is
// SCContentFilter(desktopIndependentWindow:), so only that window's own content is recorded, even
// where other windows cover it; that holds for the desktop's wallpaper window too. The file lasts
// exactly <seconds>: a window that stops changing holds its last frame. It needs Screen Recording
// for the terminal, which is allowed for capture tooling on the developer's Mac and never for
// product code.
let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

struct RecordingError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

guard arguments.count == 3, let windowID = CGWindowID(arguments[0]),
      let seconds = Double(arguments[1]), seconds > 0 else {
    fail("usage: recordwindow <window id> <seconds> <out.mov | out.mp4>")
}
let url = URL(fileURLWithPath: arguments[2])

/// Writes the stream's complete frames to the file. Every piece of state lives on `queue`, which is
/// also the stream's sample handler queue.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "recordwindow")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let duration: CMTime
    private var start: CMTime?
    private var outcome: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    init(url: URL, width: Int, height: Int, seconds: Double) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(url: url, fileType: url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoExpectedSourceFrameRateKey: 60,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError("cannot write \(width)x\(height) video") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecordingError("cannot write \(url.path)") }
        duration = CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Returns once the file is written, or throws why it could not be.
    func finished() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let outcome = self.outcome { continuation.resume(with: outcome) } else { self.continuation = continuation }
            }
        }
    }

    /// Fails unless the window yields a frame within `seconds`.
    func expectFrame(within seconds: Double) {
        queue.asyncAfter(deadline: .now() + seconds) {
            if self.start == nil { self.complete(.failure(RecordingError("the window drew no frame in \(Int(seconds)) s"))) }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, outcome == nil, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete
        else { return }
        let time = sampleBuffer.presentationTimeStamp
        if start == nil {
            start = time
            writer.startSession(atSourceTime: time)
            queue.asyncAfter(deadline: .now() + duration.seconds) { self.finish() }
        }
        guard let start, time - start < duration, input.isReadyForMoreMediaData else { return }
        if !input.append(sampleBuffer) {
            complete(.failure(writer.error ?? RecordingError("cannot append a frame")))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.complete(.failure(error)) }
    }

    private func finish() {
        guard outcome == nil, let start else { return }
        input.markAsFinished()
        // Ending the session after the last frame holds that frame, so the file lasts `duration`.
        writer.endSession(atSourceTime: start + duration)
        writer.finishWriting {
            self.queue.async {
                self.complete(self.writer.status == .completed
                    ? .success(()) : .failure(self.writer.error ?? RecordingError("cannot finish the file")))
            }
        }
    }

    private func complete(_ result: Result<Void, Error>) {
        guard outcome == nil else { return }
        if case .failure = result, writer.status == .writing { writer.cancelWriting() }
        outcome = result
        continuation?.resume(with: result)
        continuation = nil
    }
}

// Top-level code picks the completion-handler forms of these, so they are bridged by hand.
extension SCStream {
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            startCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stopCapture { _ in continuation.resume() }
        }
    }
}

// ScreenCaptureKit needs this process's window server connection, which a command-line tool opens
// only when it first asks CoreGraphics something.
_ = CGMainDisplayID()

do {
    // The wallpaper window sits below the desktop level and may count as off screen.
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
        fail("no window \(windowID) to record")
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let scale = CGFloat(filter.pointPixelScale)
    // Even sizes, which the encoders need.
    let width = Int(filter.contentRect.width * scale) & ~1
    let height = Int(filter.contentRect.height * scale) & ~1
    guard width > 0, height > 0 else { fail("window \(windowID) has no size") }

    let configuration = SCStreamConfiguration()
    configuration.width = width
    configuration.height = height
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    configuration.captureResolution = .best
    configuration.showsCursor = false
    configuration.queueDepth = 8

    let recorder = try Recorder(url: url, width: width, height: height, seconds: seconds)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
    try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
    try await stream.start()
    recorder.expectFrame(within: 5)
    let result: Result<Void, Error>
    do { try await recorder.finished(); result = .success(()) } catch { result = .failure(error) }
    await stream.stop()
    try result.get()
    print("\(url.path) (\(width) x \(height) px)")
} catch {
    fail("cannot record window \(windowID): \(error.localizedDescription)")
}
