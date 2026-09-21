// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// The per-selector class whitelist is adapted from Phosphene's
// WallpaperExtensionConfig.swift (MIT, (c) 2026 kageroumado). See Spikes/NOTICE.

import ExtensionFoundation
import Foundation

struct ExtensionConfig: AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        let exported = NSXPCInterface(with: (any WallpaperExtensionXPCProtocol).self)
        let classes = NSMutableSet(array: [
            NSString.self, NSNumber.self, NSData.self, NSArray.self, NSDictionary.self, NSURL.self, NSError.self,
        ])
        PrivateBridge.payloadClassNames.compactMap { objc_getClass($0) }.forEach(classes.add)
        let allowed = classes as! Set<AnyHashable>

        // (selector, argument index, is reply block)
        let slots: [(Selector, Int, Bool)] = [
            (#selector(XPCHandler.acquire(withId:request:reply:)), 0, false),
            (#selector(XPCHandler.acquire(withId:request:reply:)), 1, false),
            (#selector(XPCHandler.acquire(withId:request:reply:)), 0, true),
            (#selector(XPCHandler.update(withId:request:reply:)), 0, false),
            (#selector(XPCHandler.update(withId:request:reply:)), 1, false),
            (#selector(XPCHandler.invalidate(withId:reply:)), 0, false),
            (#selector(XPCHandler.snapshot(withId:reply:)), 0, false),
            (#selector(XPCHandler.snapshot(withId:reply:)), 0, true),
            (#selector(XPCHandler.provideSettingsViewModels(withContentTypes:reply:)), 0, false),
            (#selector(XPCHandler.provideSettingsViewModels(withContentTypes:reply:)), 0, true),
            (#selector(XPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 0, false),
            (#selector(XPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 1, false),
            (#selector(XPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 0, true),
            (#selector(XPCHandler.removeChoiceRequest(withChoiceRequest:reply:)), 0, false),
            (#selector(XPCHandler.selectedChoicesDidChange(for:reply:)), 0, false),
            (#selector(XPCHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), 0, false),
            (#selector(XPCHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), 1, false),
            (#selector(XPCHandler.isChoiceDownloaded(with:reply:)), 0, false),
            (#selector(XPCHandler.download(withChoiceID:reply:)), 0, false),
            (#selector(XPCHandler.pauseDownload(for:reply:)), 0, false),
            (#selector(XPCHandler.cancelDownload(for:reply:)), 0, false),
            (#selector(XPCHandler.resumeDownload(for:reply:)), 0, false),
            (#selector(XPCHandler.removeDownload(for:reply:)), 0, false),
            (#selector(XPCHandler.migrateSelectedChoice(for:reply:)), 0, false),
            (#selector(XPCHandler.migrateSelectedChoice(for:reply:)), 0, true),
            (#selector(XPCHandler.migrate(from:to:reply:)), 0, false),
            (#selector(XPCHandler.migrate(from:to:reply:)), 1, false),
            (#selector(XPCHandler.skipShuffledContent(withId:reply:)), 0, false),
            (#selector(XPCHandler.canSkipShuffledContent(withId:reply:)), 0, false),
            (#selector(XPCHandler.handleDebugRequest(for:reply:)), 0, false),
            (#selector(XPCHandler.handleDebugRequest(for:reply:)), 0, true),
            (#selector(XPCHandler.handleNotification(withNamed:reply:)), 0, false),
        ]
        for (selector, index, ofReply) in slots {
            exported.setClasses(allowed, for: selector, argumentIndex: index, ofReply: ofReply)
        }

        let handler = XPCHandler(peer: connection.processIdentifier)
        connection.exportedInterface = exported
        connection.exportedObject = handler
        connection.remoteObjectInterface = NSXPCInterface(with: (any WallpaperExtensionProxyXPCProtocol).self)
        connection.invalidationHandler = { [weak handler] in
            guard let handler else { return }
            // S7: a connection that is dropped without ever calling a method is the
            // signature of a wedged WallpaperAgent. Contexts are kept either way:
            // the agent drops and re-acquires routinely.
            SpiralDetector.shared.connectionEnded(served: handler.served, peer: handler.peer)
        }
        connection.resume()
        spikeLog("extension: accepted connection from pid \(connection.processIdentifier)")
        return true
    }
}

/// Counts consecutive empty connections and asks the app, at most once per
/// 10 minutes, to restart WallpaperAgent. The sandbox cannot do that itself.
final class SpiralDetector {
    static let shared = SpiralDetector()
    private let lock = NSLock()
    private var empties = 0
    private var lastSignal = Date.distantPast

    func connectionEnded(served: Bool, peer: Int32) {
        lock.lock()
        defer { lock.unlock() }
        if served { empties = 0; return }
        empties += 1
        spikeLog("extension: EMPTY connection from pid \(peer) (\(empties) in a row)")
        guard empties >= 4, Date().timeIntervalSince(lastSignal) > 600 else { return }
        lastSignal = Date()
        spikeLog("extension: SPIRAL detected, asking the app to restart WallpaperAgent")
        DarwinNotify.post(Spike.spiral)
    }
}
