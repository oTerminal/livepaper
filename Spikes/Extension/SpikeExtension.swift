// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.

import AppKit
import ExtensionFoundation
import Foundation

@main
final class SpikeExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        let info = Bundle.main.infoDictionary
        spikeLog("extension: INIT pid \(ProcessInfo.processInfo.processIdentifier) build \(info?["CFBundleVersion"] ?? "?") path \(Bundle.main.bundlePath)")
        guard PrivateBridge.load() else { return }

        LibraryProbe.run()
        DarwinNotify.observe(Spike.configChanged) {
            spikeLog("extension: configChanged received (app -> extension notification works)")
            SurfaceStore.shared.applyConfig()
        }
        DarwinNotify.observe(Spike.check) { SurfaceStore.shared.checkAdvancing(after: "check request") }
        observeSleepAndLock()
        startHeartbeat()
    }

    var configuration: some AppExtensionConfiguration { ExtensionConfig() }

    /// S4: log every transition with a timestamp, and check 2 s after each wake that
    /// playback is really advancing.
    private func observeSleepAndLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, label) in [
            (NSWorkspace.screensDidSleepNotification, "screensDidSleep"),
            (NSWorkspace.screensDidWakeNotification, "screensDidWake"),
            (NSWorkspace.willSleepNotification, "willSleep"),
            (NSWorkspace.didWakeNotification, "didWake"),
            (NSWorkspace.sessionDidResignActiveNotification, "sessionDidResignActive"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive"),
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                spikeLog("extension: \(label)")
                if label.contains("Wake") || label.contains("BecomeActive") { SurfaceStore.shared.checkAdvancing(after: label) }
            }
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributed.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                spikeLog("extension: \(name)")
                if name.hasSuffix("Unlocked") { SurfaceStore.shared.checkAdvancing(after: name) }
            }
        }
    }

    /// Extension -> app: a Darwin notification whose 64-bit state carries the config
    /// generation and the front engine's loop count.
    private func startHeartbeat() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            let store = SurfaceStore.shared
            Heartbeat.post(Heartbeat(generation: store.generation, loops: store.frontLoops))
            store.logLoopMetrics()
        }
    }
}

/// S1: can this sandboxed process read each candidate library location?
enum LibraryProbe {
    static func run() {
        spikeLog("s1: NSHomeDirectory = \(NSHomeDirectory()); real home = \(Spike.realHome.path)")
        for (label, url) in [("a (Application Support + exception)", Spike.libraryA), ("b (own container)", Spike.libraryB)] {
            let config = url.appendingPathComponent(SpikeConfig.fileName)
            do {
                let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
                let bytes = (try? Data(contentsOf: config).count) ?? -1
                spikeLog("s1: location \(label): READABLE, \(names.count) entries, config \(bytes) bytes")
            } catch {
                spikeLog("s1: location \(label): NOT readable: \((error as NSError).domain) \((error as NSError).code)")
            }
        }
    }
}
