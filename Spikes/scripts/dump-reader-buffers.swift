// Throwaway spike tool (docs/specs/M1-engine-spike.md): prints what AVAssetReaderTrackOutput really vends
// for a file: marker buffers, media and output timestamps, attachments.
//   swiftc -O -o /tmp/dump-reader-buffers scripts/dump-reader-buffers.swift && /tmp/dump-reader-buffers clips/a-1080p30-h264.mp4

import AVFoundation
import CoreMedia
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
var track: AVAssetTrack?
asset.loadTracks(withMediaType: .video) { t, _ in track = t?.first; sem.signal() }
sem.wait()
let reader = try! AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track!, outputSettings: nil)
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()
var samples: [CMSampleBuffer] = []
while let s = output.copyNextSampleBuffer() { samples.append(s) }
print("samples vended:", samples.count, " reader status:", reader.status.rawValue)
func describe(_ s: CMSampleBuffer, _ label: String) {
    let pts = CMSampleBufferGetPresentationTimeStamp(s), dts = CMSampleBufferGetDecodeTimeStamp(s), dur = CMSampleBufferGetDuration(s)
    print("\(label): numSamples \(CMSampleBufferGetNumSamples(s)) size \(CMSampleBufferGetTotalSampleSize(s)) pts \(pts.value)/\(pts.timescale) dts \(dts.isValid ? "\(dts.value)/\(dts.timescale)" : "invalid") dur \(dur.value)/\(dur.timescale) out-pts \(CMSampleBufferGetOutputPresentationTimeStamp(s).seconds) out-dur \(CMSampleBufferGetOutputDuration(s).seconds)")
    for mode in [kCMAttachmentMode_ShouldPropagate, kCMAttachmentMode_ShouldNotPropagate] {
        if let d = CMCopyDictionaryOfAttachments(allocator: nil, target: s, attachmentMode: mode) as? [String: Any], !d.isEmpty { print("   buffer attachments (mode \(mode)):", d) }
    }
    if let a = CMSampleBufferGetSampleAttachmentsArray(s, createIfNecessary: false) as? [[String: Any]] { print("   sample attachments:", a) }
}
for (i, s) in samples.enumerated() where i < 2 || i >= samples.count - 3 { describe(s, "sample \(i)") }
