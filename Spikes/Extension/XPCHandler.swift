// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// The acquire flow (fields read by Mirror, one CAContext per WallpaperID, contexts that
// outlive the connection) follows Phosphene's WallpaperXPCHandler.swift
// (MIT, (c) 2026 kageroumado). See Spikes/NOTICE.

import AppKit
import Foundation

final class XPCHandler: NSObject, WallpaperExtensionXPCProtocol {
    let peer: Int32
    private let lock = NSLock()
    private var _served = false
    var served: Bool { lock.lock(); defer { lock.unlock() }; return _served }

    init(peer: Int32) { self.peer = peer }

    private func markServed() { lock.lock(); _served = true; lock.unlock() }

    // MARK: Lifecycle

    func acquire(withId id: Any?, request: Any?, reply: @escaping (Any?, (any Error)?) -> Void) {
        markServed()
        var size = CGSize(width: 1920, height: 1080)
        var scale: CGFloat = 2
        var displayID: UInt32 = 0
        var isPreview = false
        if let request {
            if let destination = mirrorFind("destination", in: request) {
                size = mirrorFind("size", in: destination) as? CGSize ?? size
                scale = mirrorFind("scaleFactor", in: destination) as? CGFloat ?? scale
                displayID = mirrorFind("directDisplayID", in: destination) as? UInt32 ?? 0
            }
            isPreview = mirrorFind("isPreview", in: request) as? Bool ?? false
        }
        let surfaceID = id.flatMap { mirrorFindUUID(in: $0) } ?? UUID()
        DispatchQueue.main.async {
            SurfaceStore.shared.acquire(
                surfaceID: surfaceID, displayID: displayID, size: size, scale: scale, isPreview: isPreview, peer: self.peer, reply: reply)
        }
    }

    func update(withId id: Any?, request: Any?, reply: @escaping ((any Error)?) -> Void) {
        markServed()
        let mode = request.flatMap { mirrorFind("presentationMode", in: $0) }.map(enumCaseName) ?? "?"
        let activity = request.flatMap { mirrorFind("activityState", in: $0) }.map(enumCaseName) ?? "?"
        spikeLog("extension: UPDATE presentationMode=\(mode) activityState=\(activity) pid \(peer)")
        reply(nil)
    }

    func invalidate(withId id: Any?, reply: @escaping ((any Error)?) -> Void) {
        markServed()
        let surfaceID = id.flatMap { mirrorFindUUID(in: $0) }
        DispatchQueue.main.async {
            SurfaceStore.shared.invalidate(surfaceID: surfaceID)
            reply(nil)
        }
    }

    func snapshot(withId id: Any?, reply: @escaping (Any?, (any Error)?) -> Void) {
        markServed()
        let surfaceID = id.flatMap { mirrorFindUUID(in: $0) }
        DispatchQueue.main.async {
            // S6: hand back the picture that is on screen, so the still the agent shows
            // during a lock transition matches the video it replaces.
            let frame = SurfaceStore.shared.currentFrame(surfaceID: surfaceID)
            spikeLog("extension: SNAPSHOT requested by pid \(self.peer) -> \(frame == nil ? "solid colour" : "current video frame")")
            reply(PrivateBridge.snapshotReply(colour: SurfaceLayers.spikeColour, frame: frame), nil)
        }
    }

    // MARK: Settings and choices

    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping (Any?, (any Error)?) -> Void) {
        markServed()
        let bundleID = Bundle.main.bundleIdentifier ?? Spike.extensionBundleID
        let models = PrivateBridge.thumbnailURL().flatMap { PrivateBridge.settingsViewModels(bundleID: bundleID, thumbnail: $0) }
        spikeLog("extension: PROVIDE SETTINGS VIEW MODELS -> \(models == nil ? "nil" : "1 group, 1 item") (pid \(peer))")
        reply(models, nil)
    }

    func addChoiceRequest(withChoiceRequest request: Any?, onBehalfOfProcess process: Any?, reply: @escaping (Any?, (any Error)?) -> Void) {
        markServed(); reply(nil, nil)
    }

    func removeChoiceRequest(withChoiceRequest request: Any?, reply: @escaping ((any Error)?) -> Void) {
        markServed(); reply(nil)
    }

    func selectedChoicesDidChange(for id: Any?, reply: @escaping ((any Error)?) -> Void) {
        markServed()
        spikeLog("extension: SELECTED CHOICES DID CHANGE \(id.map { String(describing: $0) } ?? "nil")")
        reply(nil)
    }

    func invokeContextMenuAction(withMenuItemID menuItemID: Any?, groupItemID: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }

    // MARK: Unused protocol surface

    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping (Bool, (any Error)?) -> Void) { reply(true, nil) }
    func download(withChoiceID choiceID: Any?, reply: @escaping ((any Error)?) -> Void) -> Any? { reply(nil); return nil }
    func pauseDownload(for choiceID: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }
    func cancelDownload(for choiceID: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }
    func resumeDownload(for choiceID: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }
    func removeDownload(for choiceID: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }
    func migrateSelectedChoice(for anId: Any?, reply: @escaping (Any?, (any Error)?) -> Void) { reply(nil, nil) }
    func migrate(from: Any?, to: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }
    func skipShuffledContent(withId anId: Any?, reply: @escaping ((any Error)?) -> Void) { reply(nil) }
    func canSkipShuffledContent(withId anId: Any?, reply: @escaping (Bool, (any Error)?) -> Void) { reply(false, nil) }
    func handleDebugRequest(for request: Any?, reply: @escaping (Any?, (any Error)?) -> Void) { reply(nil, nil) }
    func handleNotification(withNamed name: Any?, reply: @escaping ((any Error)?) -> Void) {
        spikeLog("extension: NOTIFICATION \(name.map { String(describing: $0) } ?? "nil")")
        reply(nil)
    }
}
