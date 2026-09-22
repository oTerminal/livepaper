// Feeding the layer pass after pass on one timeline. Adapted from Phosphene's VideoRenderer.swift
// (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene) by way of the spike's
// LoopEngine, with the spike's fixes (`Spikes/results/S2.md`). See NOTICE at the repository root.

import AVFoundation
import QuartzCore

extension LoopEngine {
    var wantsAudio: Bool {
        volume > 0 && !audioBroken && media?.audioTrack != nil
    }

    /// Runs `body` on the engine's queue after what is queued there already: the way out of a
    /// renderer's callback, which may not re-enter itself.
    nonisolated func later(_ body: @escaping @Sendable (isolated LoopEngine) -> Void) {
        queue.async { [weak self] in self?.assumeIsolated(body) }
    }

    // MARK: Video

    /// The first frame goes in with the clock stopped and is shown as soon as it is decoded, so
    /// that it cannot be judged late. The first buffer a reader vends is a marker: skip to a frame.
    func enqueueFirstFrame(from pass: Pass) -> Bool {
        while let buffer = pass.video.copyNextSampleBuffer() {
            guard let frame = stamped(buffer) else { continue }
            frame.displayImmediately()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            renderer.enqueue(frame)
            CATransaction.commit()
            CATransaction.flush()
            return true
        }
        return false
    }

    func feedVideo(_ run: Int) {
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.assumeIsolated { $0.pumpVideo(run) }
        }
    }

    private func pumpVideo(_ run: Int) {
        // A retired engine's layer may be another engine's by now: its renderer is left alone.
        guard !isRetired else { return }
        guard run == generation else {
            renderer.stopRequestingMediaData()
            return
        }
        if renderer.status == .failed {
            tally.failures += 1
            logger.error("\(PlaybackLog.rendererFailed(self.video?.url, self.renderer.error), privacy: .public)")
            troubled(run)
            return
        }
        if renderer.requiresFlushToResumeDecoding {
            // The decoder needs a sync frame after a flush, and the reader is somewhere in the
            // middle of a GOP: start the file again rather than feed it P-frames.
            tally.flushes += 1
            logger.notice("\(PlaybackLog.rendererAskedForFlush(self.video?.url), privacy: .public)")
            troubled(run)
            return
        }
        while renderer.isReadyForMoreMediaData {
            guard let pass = videoPass else { return }
            guard let buffer = pass.video.copyNextSampleBuffer() else {
                renderer.stopRequestingMediaData()
                if pass.reader.status == .failed {
                    // Nil also means the reader broke, which is not the end of a pass.
                    tally.failures += 1
                    logger.error("\(PlaybackLog.readerFailed(self.video?.url, pass.reader.error), privacy: .public)")
                    troubled(run)
                } else {
                    later { $0.videoPassEnded(run) }
                }
                return
            }
            if let frame = stamped(buffer) { renderer.enqueue(frame) }
        }
    }

    /// The buffer as the layer is to see it, or nil for a marker.
    private func stamped(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let stamp = ledger.stamp(buffer.vended) else { return nil }
        if stamp.opensSeam { noteSeam(at: stamp.presentationTime) }
        guard let frame = buffer.shifted(by: stamp.shift) else { return nil }
        if stamp.dropsDecoderReset { frame.dropDecoderReset() }
        return frame
    }

    private func noteSeam(at time: CMTime) {
        let lead = (time - synchroniser.currentTime()).seconds
        tally.smallestSeamLead = min(tally.smallestSeamLead ?? lead, lead)
        let rate = Double(synchroniser.rate)
        if metricsSubject != nil, rate > 0 {
            probe.seam(dueAt: CACurrentMediaTime() + lead / rate)
        }
    }

    /// A renderer that failed or asks for a flush, or a reader that broke: start again from a
    /// fresh reader, since the one in hand is mid-GOP. A file that keeps failing is left for the watchdog.
    private func troubled(_ run: Int) {
        renderer.stopRequestingMediaData()
        guard run == generation else { return }
        restartsWithoutLoop += 1
        guard restartsWithoutLoop <= Self.restartLimit else {
            logger.error("\(PlaybackLog.gaveUp(self.video?.url, restarts: Self.restartLimit), privacy: .public)")
            haltFeeding()
            return
        }
        Task { await self.restart() }
    }

    private func videoPassEnded(_ run: Int) {
        guard run == generation, !isRetired, let finished = videoPass, let media else { return }
        let loopsBefore = ledger.loops
        ledger.finishPass()
        guard ledger.loops > loopsBefore else {
            // A pass with no frames would loop for ever and show nothing.
            tally.failures += 1
            logger.error("\(PlaybackLog.passWithoutFrames(media.video.url), privacy: .public)")
            troubled(run)
            return
        }
        restartsWithoutLoop = 0
        loopCompleted()

        let next: Pass
        if let opened = nextPass {
            next = opened
        } else {
            tally.nextReaderMisses += 1
            do {
                next = try Pass(reading: media, withAudio: wantsAudio)
            } catch {
                tally.failures += 1
                logger.error("\(PlaybackLog.readerFailed(media.video.url, error), privacy: .public)")
                troubled(run)
                return
            }
        }
        nextPass = nil
        next.offset = ledger.offset
        videoPass = next

        if audioPass === finished, !audioWaitsForVideo {
            // The audio is still reading this pass, and moves on when it reaches its end.
        } else {
            finished.cancel()
            if audioPass === finished || audioPass == nil {
                audioWaitsForVideo = false
                moveAudio(to: next, run)
            }
        }
        feedVideo(run)
        openNextPassLater(run)
    }

    // MARK: The next reader

    func openNextPassLater(_ run: Int) {
        later { $0.openNextPass(run) }
    }

    private func openNextPass(_ run: Int) {
        guard run == generation, !isRetired, nextPass == nil, let media else { return }
        // A miss here is tried again at the seam and counted there.
        nextPass = try? Pass(reading: media, withAudio: wantsAudio)
    }

    /// The volume went on or off: the next pass's reader is opened again, with or without the audio track.
    func reopenNextPass(_ run: Int) async {
        if volume > 0, !audioBroken {
            await loadAudioTrack()
        }
        guard run == generation else { return }
        nextPass?.cancel()
        nextPass = nil
        openNextPassLater(run)
    }

    func loadAudioTrack() async {
        guard let asset = media?.asset, media?.audioTrackLoaded == false else { return }
        let track = try? await asset.loadTracks(withMediaType: .audio).first
        guard media?.asset === asset else { return }
        media?.audioTrack = track
        media?.audioTrackLoaded = true
    }

    // MARK: Audio

    /// The audio reads `pass` from its start, stamped with that pass's offset, into an audio
    /// renderer on the layer's synchroniser; a pass without the audio track ends the audio.
    func moveAudio(to pass: Pass, _ run: Int) {
        guard pass.audio != nil else {
            dropAudio()
            return
        }
        audioPass = pass
        let audio: AVSampleBufferAudioRenderer
        if let existing = audioRenderer {
            audio = existing
        } else {
            audio = AVSampleBufferAudioRenderer()
            synchroniser.addRenderer(audio)
            audioRenderer = audio
        }
        audio.volume = Float(volume) * (isPaused ? 0 : 1)
        audio.requestMediaDataWhenReady(on: queue) { [weak self] in
            self?.assumeIsolated { $0.pumpAudio(run) }
        }
    }

    private func pumpAudio(_ run: Int) {
        guard let audio = audioRenderer else { return }
        guard run == generation, !isRetired else {
            audio.stopRequestingMediaData()
            return
        }
        if audio.status == .failed {
            // An audio output left unread can hold the video up, so the video starts again without it.
            tally.failures += 1
            logger.error("\(PlaybackLog.audioFailed(self.video?.url, audio.error), privacy: .public)")
            audioBroken = true
            dropAudio()
            troubled(run)
            return
        }
        while audio.isReadyForMoreMediaData {
            guard let pass = audioPass, let output = pass.audio else {
                audio.stopRequestingMediaData()
                return
            }
            guard let buffer = output.copyNextSampleBuffer() else {
                audio.stopRequestingMediaData()
                later { $0.audioPassEnded(run) }
                return
            }
            guard buffer.numSamples > 0, buffer.dataBuffer != nil,
                  let sample = buffer.shifted(by: pass.offset + buffer.editShift) else { continue }
            audio.enqueue(sample)
        }
    }

    private func audioPassEnded(_ run: Int) {
        guard run == generation, !isRetired, let finished = audioPass else { return }
        guard let newer = videoPass, newer !== finished else {
            // The video is still in this pass; its seam brings the audio along.
            audioWaitsForVideo = true
            return
        }
        finished.cancel()
        moveAudio(to: newer, run)
    }

    func dropAudio() {
        audioPass = nil
        audioWaitsForVideo = false
        guard let audio = audioRenderer else { return }
        audio.stopRequestingMediaData()
        audio.flush()
        synchroniser.removeRenderer(audio, at: .invalid, completionHandler: nil)
        audioRenderer = nil
    }

    // MARK: Metrics

    private func loopCompleted() {
        guard let subject = metricsSubject, (tally.loops + ledger.loops) % Self.metricsInterval == 0 else { return }
        let metrics = metrics()
        let logger = logger
        renderer.loadVideoPerformanceMetrics { performance in
            var metrics = metrics
            metrics.droppedFrames = performance?.numberOfDroppedFrames
            metrics.totalFrames = performance?.totalNumberOfFrames
            logger.notice("\(metrics.logLine(for: subject), privacy: .public)")
        }
    }
}
