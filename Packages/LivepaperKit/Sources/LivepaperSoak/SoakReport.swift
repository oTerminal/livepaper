import Foundation

/// A soak's log, samples and markers read into `docs/reports/soak-<date>.md`
/// (M8-hardening.md, "The soak"): per trigger, the events and the episodes by
/// level and outcome; the largest presented gap per wallpaper; RSS by hour; and
/// every episode's excerpt. The next soak compares against it.
public struct SoakReport: Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Nothing to judge: an empty log is no soak, never a pass.
        case noSoak(String)
        case pass
        /// Nothing failed, but a rule could not be judged.
        case incomplete([String])
        case fail([String])
    }

    /// "No agent restart twice in 600 s" (`AgentRestart`).
    public static let agentRestartGap: TimeInterval = 600
    /// The app and the extension, whose memory the soak holds to its rule.
    public static let processes = ["Livepaper", "WallpaperExtension"]

    /// The first `host: status live`: the soak's clock starts there.
    public let start: Date?
    public let end: Date?
    public let episodes: Episodes
    public let gaps: WallpaperGaps
    public let memory: [MemoryTrend]
    public let verdict: Verdict
    public let markdown: String

    public init(
        log: SoakLog, samples: [ResourceSample], markers: [SoakMarker],
        unreadSampleRows: Int = 0, unreadMarkerRows: Int = 0, timeZone: TimeZone
    ) {
        let start = log.entries.first { $0.event == .hostStatus(.live) }?.line.time
        let end = markers.last { $0.kind == .end }?.time ?? [log.lines.last?.time, samples.map(\.time).max()].compactMap(\.self).max()
        let episodes = Episodes(log: log, markers: markers)
        let gaps = WallpaperGaps(log.entries.compactMap { if case .metrics(let line) = $0.event { line } else { nil } })
        let memory = Self.processes.map { MemoryTrend(process: $0, samples: samples, start: start ?? .distantPast) }
        let restarts = log.entries.filter { if case .agentRestarted = $0.event { true } else { false } }.map(\.line.time)
        self.start = start
        self.end = end
        self.episodes = episodes
        self.gaps = gaps
        self.memory = memory
        verdict = Self.verdict(start: start, episodes: episodes, gaps: gaps, memory: memory, restarts: restarts)

        var writer = ReportWriter(timeZone: timeZone)
        writer.header(verdict: verdict, start: start, end: end)
        writer.inputs(
            log: log, samples: samples.count, unreadSamples: unreadSampleRows, markers: markers.count, unreadMarkers: unreadMarkerRows
        )
        if start != nil {
            writer.triggers(episodes)
            writer.episodes(episodes, log: log)
            writer.gaps(gaps)
            writer.memory(memory)
            writer.service(log: log, restarts: restarts, episodes: episodes)
        }
        writer.unparsed(log.unparsed)
        markdown = writer.text
    }

    private static func verdict(
        start: Date?, episodes: Episodes, gaps: WallpaperGaps, memory: [MemoryTrend], restarts: [Date]
    ) -> Verdict {
        guard start != nil else { return .noSoak("the log has no `host: status live`") }
        var failures: [String] = []
        let unrecovered = episodes.all.filter { $0.outcome != .recovered }.count
        if unrecovered > 0 { failures.append(counted(unrecovered, "unrecovered episode")) }
        let atSeams = gaps.wallpapers.map(\.overLimitAtSeams).reduce(0, +)
        if atSeams > 0 { failures.append(counted(atSeams, "gap", "gaps") + " over 1.5 frame durations at a seam") }
        for trend in memory {
            if case .fail(let growth) = trend.verdict { failures.append("\(trend.process)'s memory grew \(percent(growth)) %") }
        }
        for (earlier, later) in zip(restarts, restarts.dropFirst()) where later.timeIntervalSince(earlier) < agentRestartGap {
            failures.append("2 agent restarts \(Int(later.timeIntervalSince(earlier).rounded())) s apart, under \(Int(agentRestartGap)) s")
        }
        if !episodes.judgedWhileCovered.isEmpty {
            failures.append(counted(episodes.judgedWhileCovered.count, "recover verdict") + " on a covered display")
        }
        if !failures.isEmpty { return .fail(failures) }
        let unjudged = memory.compactMap { trend -> String? in
            if case .inconclusive(let reason) = trend.verdict { "\(trend.process)'s memory: \(reason)" } else { nil }
        }
        return unjudged.isEmpty ? .pass : .incomplete(unjudged)
    }
}

func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
}

func percent(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
}

/// The report's Markdown, section by section.
private struct ReportWriter {
    private(set) var text = ""
    private let clock: DateFormatter
    private let day: DateFormatter

    /// Lines kept for an episode: from 5 s before it opened, or its trigger when that is within a minute.
    static let excerptLead: TimeInterval = 5
    static let triggerReach: TimeInterval = 60
    static let excerptLimit = 40
    static let unparsedLimit = 50

    init(timeZone: TimeZone) {
        clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss"
        day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"
    }

    mutating func header(verdict: SoakReport.Verdict, start: Date?, end: Date?) {
        add("# Soak\(start.map { ", " + day.string(from: $0) } ?? "")")
        add("")
        switch verdict {
        case .noSoak(let reason): add("**No soak**: \(reason). Nothing here is judged.")
        case .pass: add("**Pass**: no unrecovered episode, no gap over 1.5 frame durations at a seam, memory within 10 %.")
        case .incomplete(let reasons): add("**Incomplete**: \(reasons.joined(separator: "; ")).")
        case .fail(let reasons): add("**Fail**: \(reasons.joined(separator: "; ")).")
        }
        add("")
        add("| | |")
        add("|---|---|")
        if let start, let end {
            add(
                "| Soak | \(clock.string(from: start)) to \(clock.string(from: end)) \(zone), "
                    + "\(duration(end.timeIntervalSince(start))), from the first `host: status live` |"
            )
        }
    }

    mutating func inputs(log: SoakLog, samples: Int, unreadSamples: Int, markers: Int, unreadMarkers: Int) {
        let events = log.entries.count
        let known = log.lines.count - events - log.unparsed.count
        add(
            "| Log | \(log.lines.count) lines read: \(events) events, \(known) known, \(log.unparsed.count) unparsed; "
                + "\(log.ignoredCount) of other subsystems ignored |"
        )
        add("| Samples | \(samples) rows\(unreadSamples > 0 ? ", \(unreadSamples) unread" : "") |")
        add("| Markers | \(markers) rows\(unreadMarkers > 0 ? ", \(unreadMarkers) unread" : "") |")
        add("")
    }

    mutating func triggers(_ episodes: Episodes) {
        add("## Triggers")
        add("")
        add("Each episode is charged to the last trigger at or before it opened.")
        add("")
        add("| Trigger | Events | Episodes |")
        add("|---|---|---|")
        for kind in TriggerKind.allCases {
            let events = episodes.triggers.filter { $0.kind == kind }.count
            add("| \(name(of: kind)) | \(events) | \(summary(episodes.all.filter { $0.trigger?.kind == kind })) |")
        }
        let before = episodes.all.filter { $0.trigger == nil }
        if !before.isEmpty { add("| before any trigger | | \(summary(before)) |") }
        add("")
    }

    mutating func episodes(_ episodes: Episodes, log: SoakLog) {
        add("## Episodes")
        add("")
        guard !episodes.all.isEmpty else {
            add("None.")
            add("")
            return
        }
        for (index, episode) in episodes.all.enumerated() {
            add("### \(index + 1). \(subject(episode.subject)), \(episode.level.rawValue), \(outcome(episode.outcome))")
            add("")
            var facts: [String] = []
            if case .surface(let tag) = episode.subject {
                facts.append("Wallpaper \(tag.wallpaper ?? "none"), generation \(tag.generation.map(String.init) ?? "none").")
            }
            let closed = episode.closed.map {
                ", closed \(clock.string(from: $0)) (\(duration($0.timeIntervalSince(episode.opened))))"
            } ?? ""
            facts.append("Opened \(clock.string(from: episode.opened))\(closed).")
            if let trigger = episode.trigger {
                facts.append(
                    "Charged to \(name(of: trigger.kind)) at \(clock.string(from: trigger.time)), "
                        + "\(duration(episode.opened.timeIntervalSince(trigger.time))) before."
                )
            } else {
                facts.append("No trigger before it.")
            }
            add(facts.joined(separator: " "))
            add("")
            add("```")
            excerpt(for: episode, log: log).forEach { add($0) }
            add("```")
            add("")
        }
    }

    mutating func gaps(_ gaps: WallpaperGaps) {
        add("## Presented gaps")
        add("")
        guard !gaps.wallpapers.isEmpty else {
            add("No metrics lines: the playback-metrics probe was off.")
            add("")
            return
        }
        add(
            "In frame durations, from the metrics lines. Over \(WallpaperGaps.limit) at a seam is the engine's; "
                + "mid-pass at 60 fps is load (S2.md)."
        )
        add("")
        add("| Wallpaper | Loops | Largest gap | Where | Over 1.5 at seams | Over 1.5 mid-pass |")
        add("|---|---|---|---|---|---|")
        for wallpaper in gaps.wallpapers {
            let largest = wallpaper.largest.map { String(format: "%.2f", $0) } ?? "none"
            let place = wallpaper.largest == nil ? "" : wallpaper.isLargestAtSeam ? "at a seam" : "mid-pass"
            add(
                "| \(wallpaper.folder) | \(wallpaper.loops) | \(largest) | \(place) | "
                    + "\(wallpaper.overLimitAtSeams) | \(wallpaper.overLimitMidPass) |"
            )
        }
        add("")
    }

    mutating func memory(_ trends: [MemoryTrend]) {
        add("## Memory")
        add("")
        add("Mean RSS by hour from the soak's start. Hour 24's mean may be at most 10 % over hour 2's; hour 1 is warm-up.")
        add("")
        add("| Hour | " + trends.map(\.process).joined(separator: " | ") + " |")
        add("|---|" + trends.map { _ in "---|" }.joined())
        let hours = Set(trends.flatMap(\.hourlyMeans.keys)).sorted()
        for hour in hours {
            let means = trends.map { $0.hourlyMeans[hour].map { String(format: "%.1f MB", $0 / 1_024) } ?? "" }
            add("| \(hour) | " + means.joined(separator: " | ") + " |")
        }
        add("")
        for trend in trends {
            let verdict = switch trend.verdict {
            case .pass(let growth): "pass, hour 24 is \(percent(growth)) % over hour 2"
            case .fail(let growth): "fail, hour 24 is \(percent(growth)) % over hour 2"
            case .inconclusive(let reason): "inconclusive: \(reason)"
            }
            add("- \(trend.process), \(trend.sampleCount) samples: \(verdict).")
        }
        add("")
    }

    mutating func service(log: SoakLog, restarts: [Date], episodes: Episodes) {
        add("## The service")
        add("")
        var checks: [String] = []
        var launches = 0
        var spirals = 0
        for entry in log.entries {
            switch entry.event {
            case .selfCheck(let isUsable, let missing):
                checks.append(
                    missing.isEmpty ? "all present" : "\(isUsable ? "usable" : "failed"), missing: \(missing.joined(separator: ", "))"
                )
            case .extensionLaunched: launches += 1
            case .spiral: spirals += 1
            default: break
            }
        }
        add("- Bridge self-check: \(checks.isEmpty ? "not in the log" : Set(checks).sorted().map { "`\($0)`" }.joined(separator: ", ")).")
        add("- Extension launches: \(launches).")
        let closest = zip(restarts, restarts.dropFirst()).map { $1.timeIntervalSince($0) }.min()
        let apart = closest.map { ", the closest two \(Int($0.rounded())) s apart" } ?? ""
        add("- WallpaperAgent restarts by the app: \(restarts.count)\(apart).")
        add("- Spiral detections: \(spirals).")
        add("- Recover verdicts on a covered display: \(episodes.judgedWhileCovered.count).")
        add("")
    }

    mutating func unparsed(_ lines: [LogLine]) {
        guard !lines.isEmpty else { return }
        add("## Unparsed lines")
        add("")
        add("Lines of the categories the soak reads that it did not recognise: a wording that changed, or a line it has no row for.")
        add("")
        add("```")
        lines.prefix(Self.unparsedLimit).forEach { add($0.text) }
        if lines.count > Self.unparsedLimit { add("… and \(lines.count - Self.unparsedLimit) more") }
        add("```")
        add("")
    }

    // MARK: Pieces

    private func excerpt(for episode: Episode, log: SoakLog) -> [String] {
        var from = episode.opened.addingTimeInterval(-Self.excerptLead)
        if let trigger = episode.trigger, episode.opened.timeIntervalSince(trigger.time) <= Self.triggerReach {
            from = min(from, trigger.time)
        }
        let to = (episode.closed ?? episode.opened.addingTimeInterval(Self.triggerReach)).addingTimeInterval(1)
        let lines = log.lines.filter { $0.time >= from && $0.time <= to }
        var excerpt = lines.prefix(Self.excerptLimit).map(\.text)
        if lines.count > Self.excerptLimit { excerpt.append("… and \(lines.count - Self.excerptLimit) more") }
        return excerpt
    }

    private func summary(_ episodes: [Episode]) -> String {
        guard !episodes.isEmpty else { return "none" }
        return LadderLevel.allCases.compactMap { level -> String? in
            let own = episodes.filter { $0.level == level }
            guard !own.isEmpty else { return nil }
            let outcomes: [(Episode.Outcome, String)] = [
                (.recovered, "recovered"), (.unrecovered(.reachedRestart), "reached the restart"),
                (.unrecovered(.neverClosed), "never closed"), (.unrecovered(.openAtEnd), "open at the end"),
            ]
            let parts = outcomes.compactMap { outcome, words -> String? in
                let count = own.filter { $0.outcome == outcome }.count
                return count > 0 ? "\(count) \(words)" : nil
            }
            return "\(level.rawValue): \(parts.joined(separator: ", "))"
        }.joined(separator: "; ")
    }

    private func name(of kind: TriggerKind) -> String {
        switch kind {
        case .wake: "wake"
        case .lid: "lid, asleep"
        case .lidOnExternal: "lid, awake on the external"
        case .displayWake: "display wake"
        case .unlock: "unlock"
        case .replug: "replug or mode change"
        case .rotation: "rotation"
        case .restart: "restart"
        case .userSwitch: "fast user switch"
        }
    }

    private func subject(_ subject: Episode.Subject) -> String {
        switch subject {
        case .surface(let tag): "\(tag.isPreview ? "Preview surface" : "Surface") \(tag.surface) on display \(tag.display)"
        case .host: "The host"
        }
    }

    private func outcome(_ outcome: Episode.Outcome) -> String {
        switch outcome {
        case .recovered: "recovered"
        case .unrecovered(.reachedRestart): "unrecovered: reached the restart"
        case .unrecovered(.neverClosed): "unrecovered: never closed"
        case .unrecovered(.openAtEnd): "unrecovered: open at the end"
        }
    }

    private var zone: String {
        clock.timeZone.abbreviation() ?? clock.timeZone.identifier
    }

    private func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min \(Int(seconds) % 60) s" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    private mutating func add(_ line: String) {
        text += line + "\n"
    }
}
