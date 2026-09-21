// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// The host app. Launching it registers the embedded wallpaper extension. Every spike
// row that can be driven from the app is a command:
//
//   Livepaper [noselect]                        register, select Livepaper as the wallpaper (S8b), show status, restart the agent on a spiral
//   Livepaper s1 write=a|b clip=<path>          copy a clip into a library location, point the extension at it
//   Livepaper config mode=colour|video [video=<name>] [crossfade=1] [probe=1] [location=a|b] [display=<uuid>=<name>]
//   Livepaper s2 engine=sbdl|looper clip=<path> loops=200 [probe=1|2] [reset=strip|keep] [out=<json>]
//   Livepaper s5 a=<path> b=<path> [count=6] [out=<json>]
//   Livepaper s7 a=<name> b=<name> [count=50] [seconds=10] [location=a|b]
//   Livepaper s8 probe | still=<image path> | restore=<image path>
//   Livepaper select | deselect [store=<copy>] [saved=<copy>]   S8b: edit the wallpaper store; with store=, only that copy, no agent restart
//   Livepaper login register|unregister|status
//   Livepaper check                             ask the extension to log what each surface plays and whether pictures change

import AppKit
import AVFoundation
import ServiceManagement

let arguments = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") }
let command = arguments.first ?? "status"
var options: [String: String] = [:]
for argument in arguments.dropFirst() {
    let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
    options[parts[0]] = parts.count > 1 ? parts[1] : "1"
}

func finish(_ code: Int32 = 0) -> Never { exit(code) }

func writeJSON<T: Encodable>(_ value: T, to path: String?) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value) else { return }
    print(String(decoding: data, as: UTF8.self))
    if let path { try? data.write(to: URL(fileURLWithPath: path)) }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

switch command {
case "s1": runS1()
case "config": runConfig()
case "s2": S2Harness.shared.run()
case "s5": S5Harness.shared.run()
case "s7": runS7()
case "s8": runS8()
case "select":
    if let copy = options["store"] { finish(selectLivepaper(storeURL: URL(fileURLWithPath: copy), live: false) ? 0 : 1) }
    guard selectLivepaper() else { finish(1) }
    reportSelection(after: 8) { finish($0 ? 0 : 1) }
case "deselect":
    if let copy = options["store"] {
        deselectLivepaper(storeURL: URL(fileURLWithPath: copy), savedURL: options["saved"].map { URL(fileURLWithPath: $0) } ?? WallpaperStore.savedURL, live: false)
    } else {
        deselectLivepaper()
    }
    finish()
case "login": runLogin()
case "check":
    DarwinNotify.post(Spike.check)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish() }
default: StatusWindow.shared.show(select: options["noselect"] == nil)
}
app.run()

// MARK: - S1 and config

/// Generations only go up, whichever library location the last config went to.
func nextGeneration() -> Int {
    max(SpikeConfig.load(from: Spike.libraryA)?.generation ?? 0, SpikeConfig.load(from: Spike.libraryB)?.generation ?? 0) + 1
}

/// S1: write a clip and a config into location a or b. A consent prompt shows up as a
/// long blocking write (and as tccd lines in `log stream`); a denial as EPERM.
func runS1() {
    let location = options["write"] ?? "a"
    let library = Spike.library(location)
    guard let clip = options["clip"] else { spikeLog("s1: clip=<path> required"); finish(2) }
    let source = URL(fileURLWithPath: clip)
    let target = library.appendingPathComponent(source.lastPathComponent)
    let started = Date()
    do {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
        var config = SpikeConfig()
        config.generation = nextGeneration()
        config.mode = "video"
        config.video = source.lastPathComponent
        try config.save(to: library)
        spikeLog(String(format: "s1: wrote %@ and config generation %d to %@ in %.2f s", target.lastPathComponent, config.generation, library.path, Date().timeIntervalSince(started)))
    } catch {
        spikeLog(String(format: "s1: write to %@ FAILED after %.2f s: %@", library.path, Date().timeIntervalSince(started), "\(error)"))
        finish(1)
    }
    DarwinNotify.post(Spike.configChanged)
    waitForHeartbeat(seconds: 8)
}

func runConfig() {
    let library = Spike.library(options["location"] ?? "a")
    var config = SpikeConfig.load(from: library) ?? SpikeConfig()
    config.generation = nextGeneration()
    config.mode = options["mode"] ?? config.mode
    config.video = options["video"] ?? config.video
    config.crossfade = options["crossfade"] == "1"
    config.probe = options["probe"] == "1"
    if let display = options["display"] {
        let parts = display.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { config.perDisplay = (config.perDisplay ?? [:]).merging([parts[0]: parts[1]]) { $1 } }
    }
    do { try config.save(to: library) } catch { spikeLog("config: save failed: \(error)"); finish(1) }
    spikeLog("config: generation \(config.generation) mode \(config.mode) video \(config.video ?? "-") crossfade \(config.crossfade)")
    DarwinNotify.post(Spike.configChanged)
    waitForHeartbeat(seconds: 6)
}

/// Extension -> app. Prints each heartbeat, then exits.
func waitForHeartbeat(seconds: TimeInterval) {
    var seen = 0
    DarwinNotify.observe(Spike.heartbeat) {
        seen += 1
        let beat = Heartbeat.latest
        spikeLog("app: heartbeat from extension: generation \(beat.generation), loops \(beat.loops) (extension -> app notification works)")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        if seen == 0 { spikeLog("app: NO heartbeat in \(Int(seconds)) s (extension not running, or notifications blocked)") }
        finish(seen == 0 ? 1 : 0)
    }
}

// MARK: - S7

/// 50 switches in 10 s, ending on `b`. The extension must end on the last one.
func runS7() {
    let library = Spike.library(options["location"] ?? "a")
    let count = Int(options["count"] ?? "50") ?? 50
    let seconds = Double(options["seconds"] ?? "10") ?? 10
    guard let a = options["a"], let b = options["b"] else { spikeLog("s7: a=<name> b=<name> required"); finish(2) }
    var generation = nextGeneration()
    var sent = 0
    Timer.scheduledTimer(withTimeInterval: seconds / Double(count), repeats: true) { timer in
        sent += 1
        var config = SpikeConfig()
        config.generation = generation
        config.mode = "video"
        // Odd count ends on a, so make the final one explicit.
        config.video = sent == count ? b : (sent.isMultiple(of: 2) ? b : a)
        try? config.save(to: library)
        DarwinNotify.post(Spike.configChanged)
        generation += 1
        guard sent == count else { return }
        timer.invalidate()
        spikeLog("s7: sent \(count) switches in \(seconds) s; last was generation \(generation - 1) -> \(b)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            let reported = Heartbeat.latest.generation
            let ok = reported == generation - 1
            spikeLog("s7: extension reports generation \(reported): \(ok ? "ended on the last request" : "MISMATCH") (run `Livepaper check` to see which clip is really on screen)")
            finish(ok ? 0 : 1)
        }
    }
}

// MARK: - S8

/// What public API can see and do about the system wallpaper.
func runS8() {
    let workspace = NSWorkspace.shared
    for screen in NSScreen.screens {
        let url = workspace.desktopImageURL(for: screen)
        let screenOptions = workspace.desktopImageOptions(for: screen) ?? [:]
        spikeLog("s8: screen \(screen.localizedName): desktopImageURL = \(url?.path ?? "nil"), options = \(screenOptions.map { "\($0.key.rawValue)=\($0.value)" })")
    }
    if let path = options["still"] ?? options["restore"] {
        for screen in NSScreen.screens {
            do {
                try workspace.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
                spikeLog("s8: setDesktopImageURL(\(path)) on \(screen.localizedName): ok")
            } catch {
                spikeLog("s8: setDesktopImageURL failed: \(error)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for screen in NSScreen.screens {
                spikeLog("s8: after set: desktopImageURL = \(workspace.desktopImageURL(for: screen)?.path ?? "nil")")
            }
            finish()
        }
    } else {
        finish()
    }
}

// MARK: - S0c login item

func runLogin() {
    let service = SMAppService.mainApp
    do {
        switch arguments.dropFirst().first {
        case "register": try service.register()
        case "unregister": try service.unregister()
        default: break
        }
    } catch {
        spikeLog("login: \(error)")
    }
    let names = ["notRegistered", "enabled", "requiresApproval", "notFound"]
    spikeLog("login: status = \(names[min(service.status.rawValue, 3)]) for \(Bundle.main.bundlePath)")
    finish()
}

// MARK: - Status window

final class StatusWindow: NSObject {
    static let shared = StatusWindow()
    private var window: NSWindow?
    private let label = NSTextField(wrappingLabelWithString: "")
    private var lastAgentRestart = Date.distantPast
    private var selection = "not attempted: choose \"Livepaper\" in System Settings > Wallpaper."

    func show(select: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Livepaper spike, build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")"
        label.frame = NSRect(x: 20, y: 20, width: 480, height: 180)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
        render(heartbeat: "none yet.")
        // S8b: no click in System Settings. Launching has registered the extension; give pkd a moment to know it.
        if select {
            whenExtensionIsRegistered(tries: 20) { [self] registered in
                selection = registered && selectLivepaper() ? "selected by editing the wallpaper store." : "could not be selected: choose \"Livepaper\" in System Settings > Wallpaper."
                render(heartbeat: "none yet.")
            }
        }

        DarwinNotify.observe(Spike.heartbeat) { [self] in
            let beat = Heartbeat.latest
            render(heartbeat: "generation \(beat.generation), loops \(beat.loops), at \(Date().formatted(date: .omitted, time: .standard))")
        }
        // S7: the sandboxed extension cannot restart the agent, so it asks the app.
        DarwinNotify.observe(Spike.spiral) { [self] in
            guard Date().timeIntervalSince(lastAgentRestart) > 600 else { spikeLog("app: spiral signal ignored (rate limit)"); return }
            lastAgentRestart = Date()
            spikeLog("app: spiral signal received, running killall WallpaperAgent")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["WallpaperAgent"]
            try? task.run()
        }
    }

    /// A store that names a provider pkd does not know yet is a store the agent may throw away, so wait for it.
    private func whenExtensionIsRegistered(tries: Int, _ done: @escaping (Bool) -> Void) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-i", Spike.extensionBundleID]
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let listed = !pipe.fileHandleForReading.readDataToEndOfFile().isEmpty
        if listed || tries <= 1 {
            spikeLog("select: extension \(listed ? "is" : "is NOT") registered with pluginkit")
            return done(listed)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in whenExtensionIsRegistered(tries: tries - 1, done) }
    }

    private func render(heartbeat: String) {
        let info = Bundle.main.infoDictionary
        label.stringValue = """
        Build \(info?["CFBundleVersion"] ?? "?") at \(Bundle.main.bundlePath)

        The wallpaper extension is registered by launching this app.
        Wallpaper: \(selection)

        Extension heartbeat: \(heartbeat)
        """
    }
}

// MARK: - S2

/// 200 loops in a plain window, with either engine, and a JSON result.
final class S2Harness: NSObject {
    static let shared = S2Harness()
    private var window: NSWindow?
    private var engine: LoopEngine?
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?
    private var activity: NSObjectProtocol?
    /// Read off the main thread by the probe; written on the main thread.
    private var occluded = false

    struct LooperResult: Codable {
        var engine = "AVPlayerLooper"
        var clip = ""
        var loops = 0
        var seconds = 0.0
    }

    func run() {
        guard let clip = options["clip"] else { spikeLog("s2: clip=<path> required"); finish(2) }
        let url = URL(fileURLWithPath: clip)
        let loops = Int(options["loops"] ?? "200") ?? 200
        let size = NSSize(width: 1280, height: 720)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "S2 \(options["engine"] ?? "sbdl") \(url.lastPathComponent)"
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        window.center()
        // A covered window is throttled to about 1 fps by the window server, and a
        // napping app gets late timers: both would be measured as engine stalls.
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled], reason: "S2 measurement")
        spikeLog("s2: pid \(ProcessInfo.processInfo.processIdentifier) engine \(options["engine"] ?? "sbdl") clip \(url.lastPathComponent) loops \(loops)")

        if options["engine"] == "looper" {
            runLooper(url: url, loops: loops, in: view)
        } else {
            let layers = SurfaceLayers(size: size, scale: window.backingScaleFactor)
            layers.probeDisplayedFrames = options["probe"] == "1" || options["probe"] == "2"
            layers.probeContent = options["probe"] == "2"
            layers.stripDecoderReset = options["reset"] != "keep"
            layers.isOccluded = { [self] in occluded }
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [self] _ in
                occluded = !window.occlusionState.contains(.visible)
                spikeLog("s2: window \(occluded ? "occluded, probe paused" : "visible again")")
            }
            view.layer?.addSublayer(layers.root)
            layers.show(url, crossfade: false) {
                guard let engine = layers.frontEngine else { finish(1) }
                self.engine = engine
                engine.onLoop = { count in
                    if count.isMultiple(of: 20) { spikeLog("s2: \(count) loops") }
                    guard count >= loops else { return }
                    engine.onLoop = nil
                    engine.finalMetrics { metrics in
                        writeJSON(metrics, to: options["out"])
                        finish()
                    }
                }
            }
        }
    }

    /// The comparison engine. Only used for CPU and energy; it has no seam metrics.
    private func runLooper(url: URL, loops: Int, in view: NSView) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer?.addSublayer(layer)
        player.play()
        self.player = player
        self.looper = looper
        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard looper.loopCount >= loops else { return }
            writeJSON(LooperResult(clip: url.lastPathComponent, loops: looper.loopCount, seconds: Date().timeIntervalSince(started)), to: options["out"])
            finish()
        }
    }
}

// MARK: - S5

/// Crossfades back and forth in a window. While a fade runs, a 5 ms poll checks that a
/// fully opaque video layer with a displayed frame exists at every sample.
final class S5Harness: NSObject {
    static let shared = S5Harness()
    private var window: NSWindow?
    private var layers: SurfaceLayers?

    struct Result: Codable {
        var crossfades = 0
        var samples = 0
        var samplesWithNoVisibleVideo = 0
    }

    private var result = Result()

    func run() {
        guard let a = options["a"], let b = options["b"] else { spikeLog("s5: a=<path> b=<path> required"); finish(2) }
        let urls = [URL(fileURLWithPath: a), URL(fileURLWithPath: b)]
        let count = Int(options["count"] ?? "6") ?? 6
        let size = NSSize(width: 1280, height: 720)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "S5 crossfade"
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
        let layers = SurfaceLayers(size: size, scale: window.backingScaleFactor)
        view.layer?.addSublayer(layers.root)
        self.layers = layers

        let poll = Timer(timeInterval: 0.005, repeats: true) { [self] _ in
            guard layers.front != nil else { return }
            result.samples += 1
            let visible = layers.video.contains { layer in
                (layer.presentation()?.opacity ?? layer.opacity) >= 0.999 && layer.isReadyForDisplay
            }
            if !visible { result.samplesWithNoVisibleVideo += 1 }
        }
        RunLoop.main.add(poll, forMode: .common)

        func step(_ index: Int) {
            guard index <= count else {
                writeJSON(result, to: options["out"])
                finish(result.samplesWithNoVisibleVideo == 0 ? 0 : 1)
            }
            layers.show(urls[index % 2], crossfade: true) { [self] in
                if index > 0 { result.crossfades += 1 }
                spikeLog("s5: showing \(urls[index % 2].lastPathComponent)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { step(index + 1) }
            }
        }
        step(0)
    }
}
