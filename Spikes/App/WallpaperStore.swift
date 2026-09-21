// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// S8b: selecting Livepaper without anybody opening System Settings, by editing the wallpaper
// store and restarting WallpaperAgent (results/S8.md, "Selecting by editing the store").
// The store is an undocumented property list in the user's Library. No private framework,
// no TCC prompt; its format can change with any macOS update, so every step checks what it
// finds and gives up (the caller falls back to "choose Livepaper in System Settings")
// instead of writing something it does not understand.
//
// The store is a tree. Wherever a wallpaper can be set (system default, all Spaces and
// displays, one display, one Space, one display in one Space) there is a node with a
// "Desktop" and an "Idle" (screen saver) entry. Only Desktop entries are touched.

import Foundation

enum WallpaperStore {
    static let url = Spike.realHome.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    /// The store as it was before the first select, kept so that deselect can put back an
    /// Aerial or a dynamic wallpaper, which no public API can name.
    static var savedURL: URL { Spike.libraryA.appendingPathComponent("wallpaper-store-before-livepaper.plist") }

    enum Failure: Error { case unreadable(String), unknownFormat(String) }

    typealias Node = [String: Any]

    static func load(_ url: URL) throws -> Node {
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(url.path) }
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Node else {
            throw Failure.unknownFormat("the store is not a dictionary")
        }
        return root
    }

    static func save(_ root: Node, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// The Desktop entry that names an extension's wallpaper, as WallpaperAgent itself writes it.
    static func desktopEntry(provider: String, configuration: Data, now: Date) -> Node {
        let choice: Node = ["Provider": provider, "Files": [Any](), "Configuration": configuration]
        return ["LastSet": now, "LastUse": now, "Content": ["Choices": [choice], "Shuffle": "$null", "EncodedOptionValues": "$null"] as Node]
    }

    static func provider(of desktop: Any?) -> String? {
        let content = (desktop as? Node)?["Content"] as? Node
        return ((content?["Choices"] as? [Any])?.first as? Node)?["Provider"] as? String
    }

    /// Visits every Desktop entry in the tree; `change` returns a replacement or nil to leave it.
    /// `path` is the keys that lead to the node holding the entry.
    static func rewritingDesktops(in node: Node, path: [String] = [], _ change: ([String], Node) -> Node?) -> (Node, Int) {
        var result = node, changed = 0
        for (key, value) in node {
            guard let child = value as? Node else { continue }
            if key == "Desktop", child["Content"] != nil {
                if let replacement = change(path, child) { result[key] = replacement; changed += 1 }
            } else {
                let (rewritten, count) = rewritingDesktops(in: child, path: path + [key], change)
                result[key] = rewritten
                changed += count
            }
        }
        return (result, changed)
    }

    static func desktopProviders(in root: Node) -> [String] {
        var found: [String] = []
        _ = rewritingDesktops(in: root) { _, desktop in found.append(provider(of: desktop) ?? "?"); return nil }
        return found
    }

    /// Every Desktop entry names `provider`. A store with no Desktop entry at all gets one as the system default.
    static func selecting(provider: String, configuration: Data, in root: Node, now: Date = Date()) -> (Node, changed: Int) {
        let entry = desktopEntry(provider: provider, configuration: configuration, now: now)
        var (result, changed) = rewritingDesktops(in: root) { _, desktop in Self.provider(of: desktop) == provider ? nil : entry }
        if desktopProviders(in: result).isEmpty {
            var systemDefault = result["SystemDefault"] as? Node ?? [:]
            systemDefault["Type"] = "individual"
            systemDefault["Desktop"] = entry
            result["SystemDefault"] = systemDefault
            changed += 1
        }
        return (result, changed)
    }

    /// Every Desktop entry that still names `provider` goes back to what `saved` had in the same place,
    /// or to the saved system default. Entries the user has changed since are left alone.
    static func deselecting(provider: String, in root: Node, saved: Node) throws -> (Node, changed: Int) {
        func lookup(_ path: [String]) -> Node? {
            var node: Node? = saved
            for key in path { node = node?[key] as? Node }
            return node?["Desktop"] as? Node
        }
        let candidates = [lookup(["SystemDefault"]), lookup(["AllSpacesAndDisplays"])].compactMap { $0 }
        guard let fallback = candidates.first(where: { Self.provider(of: $0) != provider }) else {
            throw Failure.unknownFormat("the saved store has no wallpaper of its own to go back to")
        }
        return rewritingDesktops(in: root) { path, desktop in
            guard Self.provider(of: desktop) == provider else { return nil }
            if let previous = lookup(path), Self.provider(of: previous) != provider { return previous }
            return fallback
        }
    }

    static func restartAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Commands

/// `Livepaper select [store=<path>]`: with `store`, rewrites that copy and leaves the agent alone.
/// Returns whether Livepaper is selected afterwards.
@discardableResult
func selectLivepaper(storeURL: URL = WallpaperStore.url, live: Bool = true) -> Bool {
    do {
        let root = try WallpaperStore.load(storeURL)
        let before = WallpaperStore.desktopProviders(in: root)
        if !before.isEmpty, before.allSatisfy({ $0 == Spike.extensionBundleID }) {
            spikeLog("select: already selected in all \(before.count) desktop entries, nothing written")
            return true
        }
        // A store that names Livepaper nowhere is the user's own choice, so it replaces an older copy;
        // a half-selected one only gets kept when there is nothing better.
        let untouched = !before.contains(Spike.extensionBundleID)
        if live, untouched || !FileManager.default.fileExists(atPath: WallpaperStore.savedURL.path) {
            try WallpaperStore.save(root, to: WallpaperStore.savedURL)
            spikeLog("select: kept the store as it was in \(WallpaperStore.savedURL.path)")
        }
        let (rewritten, changed) = WallpaperStore.selecting(provider: Spike.extensionBundleID, configuration: Data(Spike.choiceIdentifier.utf8), in: root)
        try WallpaperStore.save(rewritten, to: storeURL)
        spikeLog("select: \(changed) of \(max(before.count, changed)) desktop entries now name \(Spike.extensionBundleID) (they named \(Set(before).sorted()))")
        if live { WallpaperStore.restartAgent(); spikeLog("select: WallpaperAgent restarted") }
        return true
    } catch {
        spikeLog("select: FAILED, the user has to choose Livepaper in System Settings: \(error)")
        return false
    }
}

/// `Livepaper deselect [store=<path>] [saved=<path>]`
func deselectLivepaper(storeURL: URL = WallpaperStore.url, savedURL: URL = WallpaperStore.savedURL, live: Bool = true) {
    do {
        let root = try WallpaperStore.load(storeURL)
        let saved = try WallpaperStore.load(savedURL)
        let (rewritten, changed) = try WallpaperStore.deselecting(provider: Spike.extensionBundleID, in: root, saved: saved)
        guard changed > 0 else { spikeLog("deselect: Livepaper is not selected anywhere, nothing written"); return }
        try WallpaperStore.save(rewritten, to: storeURL)
        spikeLog("deselect: \(changed) desktop entries put back; they now name \(Set(WallpaperStore.desktopProviders(in: rewritten)).sorted())")
        if live {
            try? FileManager.default.removeItem(at: savedURL)
            WallpaperStore.restartAgent()
            spikeLog("deselect: WallpaperAgent restarted")
        }
    } catch {
        spikeLog("deselect: FAILED: \(error)")
    }
}

/// After a select: did the agent really come to the extension? Only a heartbeat proves it.
func reportSelection(after seconds: TimeInterval, then done: @escaping (Bool) -> Void) {
    var beats = 0
    DarwinNotify.observe(Spike.heartbeat) { beats += 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        let providers = (try? WallpaperStore.load(WallpaperStore.url)).map(WallpaperStore.desktopProviders) ?? []
        let held = !providers.isEmpty && providers.allSatisfy { $0 == Spike.extensionBundleID }
        spikeLog("select: \(seconds) s later: \(beats) heartbeats from the extension; the store \(held ? "still names Livepaper everywhere" : "names \(Set(providers).sorted())")")
        done(beats > 0 && held)
    }
}
