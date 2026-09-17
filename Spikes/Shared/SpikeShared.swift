// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.

import Foundation
import os

enum Spike {
    static let appBundleID = "app.livepaper.spike"
    static let extensionBundleID = "app.livepaper.spike.extension"
    static let logger = Logger(subsystem: "app.livepaper.spike", category: "spike")

    /// App -> extension: "re-read spike-config.json".
    static let configChanged = "app.livepaper.spike.configChanged"
    /// Extension -> app: the notification's state is a packed `Heartbeat`.
    static let heartbeat = "app.livepaper.spike.heartbeat"
    /// App -> extension: "log what every surface is playing and whether pictures are changing".
    static let check = "app.livepaper.spike.check"
    /// Extension -> app: WallpaperAgent keeps connecting without ever calling a method.
    static let spiral = "app.livepaper.spike.spiral"

    /// The real home directory. Inside the sandbox `NSHomeDirectory()` is the container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// S1 (a): Application Support, read by the extension through a read-only
    /// home-relative sandbox exception. A spike-only folder so nothing collides
    /// with the product's `Livepaper/` later.
    static var libraryA: URL {
        realHome.appendingPathComponent("Library/Application Support/LivepaperSpike", isDirectory: true)
    }

    /// S1 (b): the extension's own container, written by the unsandboxed app.
    static var libraryB: URL {
        realHome.appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Documents/library", isDirectory: true)
    }

    static func library(_ location: String) -> URL { location == "b" ? libraryB : libraryA }
}

/// Extension -> app, packed into the 64-bit state of the heartbeat notification.
struct Heartbeat {
    var generation: Int
    var loops: Int

    init(generation: Int, loops: Int) { self.generation = generation; self.loops = loops }
    init(packed: UInt64) { generation = Int(packed >> 32); loops = Int(packed & 0xFFFF_FFFF) }
    var packed: UInt64 { UInt64(generation) << 32 | UInt64(loops & 0xFFFF_FFFF) }

    static func post(_ beat: Heartbeat) {
        DarwinNotify.setState(Spike.heartbeat, beat.packed)
        DarwinNotify.post(Spike.heartbeat)
    }

    static var latest: Heartbeat { Heartbeat(packed: DarwinNotify.state(Spike.heartbeat) ?? 0) }
}

/// What the app asks the extension to show. The whole state every time, so
/// applying it twice is harmless.
struct SpikeConfig: Codable, Equatable {
    var generation: Int = 0
    /// "colour" (S0) or "video".
    var mode: String = "colour"
    /// File name inside the library folder.
    var video: String?
    /// Crossfade to the new video (S5) instead of switching in place (S7).
    var crossfade: Bool = false
    /// S3: display UUID -> file name, overriding `video` for that display.
    var perDisplay: [String: String]?
    /// S2 inside the extension: run the displayed-frame probe and log its numbers.
    var probe: Bool?

    static let fileName = "spike-config.json"

    static func load(from library: URL) -> SpikeConfig? {
        guard let data = try? Data(contentsOf: library.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(SpikeConfig.self, from: data)
    }

    func save(to library: URL) throws {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: library.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// Logs to the unified log (readable from outside the sandbox with `log show`)
/// and to stderr for the command-line harness.
func spikeLog(_ message: String) {
    Spike.logger.notice("\(message, privacy: .public)")
    FileHandle.standardError.write(Data("[spike] \(message)\n".utf8))
}

enum DarwinNotify {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Retains the handler for the life of the process, which is what a spike wants.
    static func observe(_ name: String, _ handler: @escaping () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, DispatchQueue.main) { _ in handler() }
    }

    /// A 64-bit value attached to a notification name: a heartbeat without a file.
    static func setState(_ name: String, _ value: UInt64) {
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return }
        notify_set_state(token, value)
        notify_cancel(token)
    }

    static func state(_ name: String) -> UInt64? {
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return nil }
        defer { notify_cancel(token) }
        var value: UInt64 = 0
        return notify_get_state(token, &value) == NOTIFY_STATUS_OK ? value : nil
    }
}
