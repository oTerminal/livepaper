import LivepaperCore

/// The scripted rows of the checks on screen (docs/specs/M5-engine.md), named by their row.
nonisolated enum DeveloperCheck: String, Sendable {
    /// Six crossfades back and forth, 3 s apart.
    case crossfades = "S5"
    /// Fifty switches in 10 s, one every 200 ms.
    case switches = "S7"

    var switchCount: Int {
        switch self {
        case .crossfades: 6
        case .switches: 50
        }
    }

    var interval: Duration {
        switch self {
        case .crossfades: .seconds(3)
        case .switches: .milliseconds(200)
        }
    }
}

extension DeveloperSession {
    /// The two wallpapers a check alternates: the first two in the library.
    var checkPair: (Wallpaper, Wallpaper)? {
        guard library.wallpapers.count >= 2 else { return nil }
        return (library.wallpapers[0], library.wallpapers[1])
    }

    var canRunCheck: Bool { checkPair != nil && runningCheck == nil && !displays.isEmpty }

    /// Alternates the first two wallpapers on every connected display, one
    /// applied state per switch, on a fixed schedule from the start so that
    /// the run takes the time the check names. The first switch is a real
    /// one: it starts from whichever of the two the first display is not showing.
    func run(_ check: DeveloperCheck) {
        guard canRunCheck, let (first, second) = checkPair else { return }
        let showing = displays.first.flatMap { shown[$0.identity]?.wallpaper }
        let order = showing == first.id ? [second, first] : [first, second]

        runningCheck = check
        logger.notice("\(DeveloperLog.checkStarted(check), privacy: .public)")
        checkTask = Task {
            let clock = ContinuousClock()
            let start = clock.now
            var last: WallpaperID?
            var generation: UInt64 = 0
            for index in 0..<check.switchCount {
                do {
                    try await clock.sleep(until: start + check.interval * index)
                } catch {
                    break
                }
                let wallpaper = order[index % 2]
                generation = setOnAllDisplays(wallpaper)
                last = wallpaper.id
            }
            logger.notice("\(DeveloperLog.checkEnded(check, last: last, generation: generation), privacy: .public)")
            checkTask = nil
            runningCheck = nil
        }
    }
}
