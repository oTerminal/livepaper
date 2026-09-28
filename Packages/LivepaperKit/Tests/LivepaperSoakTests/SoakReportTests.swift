import Foundation
import LivepaperCore
import LivepaperPlayback
import LivepaperSoak
import LivepaperSystem
import Testing

/// The soak's log, samples and markers into `docs/reports/soak-<date>.md`'s sections.
struct SoakReportTests {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let surface = SupervisorLog.Surface(
        surface: .numbered(1), display: .numbered(2), isPreview: false, wallpaper: .numbered(3), generation: 42
    )

    /// The engine's metrics line for wallpaper 3 on surface 1, clean.
    static let metrics = Logged.surface(
        PlaybackMetrics(
            video: "\(WallpaperID.numbered(3))/wallpaper.mov", loops: 20, seamsWatched: 19,
            largestPresentedGap: 1.1, largestPresentedGapAtSeam: 1.1
        ).logLine(for: .surface(.numbered(1))),
        at: .soak(3_600)
    )

    /// Twenty-four hours from the first `.live`, a wake at hour 3 that one flush cures.
    static let day: [LogLine] = [
        metrics,
        Logged.host(HostLog.status(.connecting), at: .soak(-5)),
        Logged.host(HostLog.status(.live), at: .soak(0)),
        Logged.supervisor(
            SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .play), generation: 42), at: .soak(1)
        ),
        Logged.extensionLine("extension: woke source=system", at: .soak(10_800)),
        Logged.supervisor(SupervisorLog.verdict(surface, .recover(.flush), attempt: 0), at: .soak(10_802)),
        Logged.supervisor(SupervisorLog.verdict(surface, .healthy, attempt: 1), at: .soak(10_804)),
        Logged.host(HostLog.status(.live), at: .soak(86_400)),
    ]

    static func samples(rss: (Int) -> Int = { _ in 100_000 }) -> [ResourceSample] {
        ["Livepaper", "WallpaperExtension"].flatMap { process in
            (0..<288).map { index in
                let seconds = TimeInterval(index * 300 + 60)
                return ResourceSample(time: .soak(seconds), process: process, pid: 1, cpu: 0.5, rssKilobytes: rss(Int(seconds) / 3_600 + 1))
            }
        }
    }

    static let end = [SoakMarker(time: .soak(86_500), kind: .end)]

    static func report(_ lines: [LogLine], samples: [ResourceSample] = samples(), markers: [SoakMarker] = end) -> SoakReport {
        SoakReport(log: SoakLog(lines: lines), samples: samples, markers: markers, timeZone: utc)
    }

    @Test
    func `an empty log reports no soak, not a pass`() {
        let report = SoakReport(log: SoakLog(text: ""), samples: [], markers: [], timeZone: Self.utc)

        #expect(report.verdict == .noSoak("the log has no `host: status live`"))
        #expect(report.markdown.contains("No soak"))
        #expect(!report.markdown.contains("Pass"))
    }

    @Test
    func `a day with one recovered wake passes, and says so per trigger`() {
        let report = Self.report(Self.day)

        #expect(report.verdict == .pass)
        #expect(report.start == .soakStart)
        #expect(report.markdown.contains("**Pass**"))
        #expect(report.markdown.contains("| wake | 1 | flush: 1 recovered |"))
        #expect(report.markdown.contains("| lid, asleep | 0 | none |"))
        #expect(report.markdown.contains("host: status live"))
    }

    @Test
    func `no metrics lines leaves the soak incomplete`() {
        let report = Self.report(Self.day.filter { $0 != Self.metrics })

        #expect(report.verdict == .incomplete(["no metrics lines: the playback-metrics probe was off"]))
    }

    @Test
    func `a drill's episode is listed apart and judged by the drill's own row, not the soak's`() {
        let drill = [SoakMarker(time: .soak(40_000), kind: .drill, note: "killall the extension")] + Self.end
        let report = Self.report(
            Self.day + [
                Logged.host(HostLog.status(.recovering(.flush)), at: .soak(40_020)),
                Logged.host(HostLog.status(.recovering(.restartAgent)), at: .soak(40_050)),
                Logged.host(HostLog.status(.live), at: .soak(40_060)),
            ],
            markers: drill
        )

        #expect(report.verdict == .pass)
        #expect(report.markdown.contains("| drill | 1 | restartAgent: 1 reached the restart |"))
        #expect(report.markdown.contains("Charged to drill (killall the extension)"))
    }

    static let replug: [LogLine] = [
        Logged.supervisor(SupervisorLog.invalidated(surface), at: .soak(20_000)),
        Logged.supervisor(SupervisorLog.acquired(replugged, reused: false), at: .soak(20_030)),
        Logged.supervisor(SupervisorLog.nowShowing(replugged, crossfade: false), at: .soak(20_030.8)),
        Logged.supervisor(SupervisorLog.verdict(replugged, .healthy, attempt: 0), at: .soak(20_033)),
    ]
    static let replugged = SupervisorLog.Surface(
        surface: .numbered(7), display: .numbered(2), isPreview: false, wallpaper: .numbered(3), generation: 42
    )

    @Test
    func `each replug says how soon its display showed its wallpaper, and the first verdict after it`() {
        let report = Self.report(Self.day + Self.replug)

        #expect(report.markdown.contains(
            "| 2026-09-21 19:47:10 | \(Named.display(2)) | \(Named.wallpaper(3)) in 0.8 s | healthy, attempt 0 | none |"
        ))
    }

    @Test
    func `every episode keeps its excerpt`() {
        let report = Self.report(Self.day)

        #expect(report.markdown.contains("check verdict \(Self.fieldsText) verdict=flush attempt=0"))
        #expect(report.markdown.contains("extension: woke source=system"))
    }

    static let fieldsText = "surface=\(Named.surface(1)) display=\(Named.display(2)) preview=false "
        + "wallpaper=\(Named.wallpaper(3)) generation=42"

    static let failures: [Row<SoakReport, String>] = [
        Row(
            "an unrecovered episode",
            report(day + [Logged.supervisor(SupervisorLog.verdict(surface, .recover(.flush), attempt: 0), at: .soak(50_000))]),
            "1 unrecovered episode"
        ),
        Row(
            "a gap over 1.5 frame durations at a seam",
            report(day + [Logged.surface(PlaybackMetrics(
                video: "\(WallpaperID.numbered(3))/wallpaper.mov", loops: 200, seamsWatched: 199,
                largestPresentedGap: 2.1, largestPresentedGapAtSeam: 2.1, gapsOverLimitAtSeams: 1
            ).logLine(for: .surface(.numbered(1))), at: .soak(20_000))]),
            "1 gap over 1.5 frame durations at a seam"
        ),
        Row(
            "memory grown 11 % by hour 24",
            report(day, samples: samples { $0 == 24 ? 111_000 : 100_000 }),
            "WallpaperExtension's memory grew 11 %"
        ),
        Row(
            "two agent restarts inside 600 s",
            report(day + [
                Logged.host(HostLog.restarted(.restarted(previous: 668, current: 700)), at: .soak(30_000)),
                Logged.host(HostLog.restarted(.restarted(previous: 700, current: 702)), at: .soak(30_300)),
            ]),
            "2 agent restarts 300 s apart, under 600 s"
        ),
        Row(
            "a covered surface judged",
            report(day + [
                Logged.supervisor(
                    SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .pause(.desktopCovered)), generation: 42),
                    at: .soak(40_000)
                ),
                Logged.supervisor(SupervisorLog.verdict(surface, .recover(.flush), attempt: 0), at: .soak(40_010)),
            ]),
            "1 recover verdict on a covered display"
        ),
    ]

    @Test(arguments: failures)
    func `a soak fails`(row: Row<SoakReport, String>) {
        guard case .fail(let reasons) = row.input.verdict else {
            Issue.record("not a failure: \(row.input.verdict)")
            return
        }
        #expect(reasons.contains(row.expected), "\(reasons)")
        #expect(row.input.markdown.contains(row.expected))
    }

    @Test
    func `gaps mid-pass are load, recorded with their count, and do not fail it`() {
        let metrics = PlaybackMetrics(
            video: "\(WallpaperID.numbered(3))/wallpaper.mov", loops: 200, seamsWatched: 199,
            largestPresentedGap: 1.56, largestPresentedGapAtSeam: 1.11, gapsOverLimitAtSeams: 0, gapsOverLimitElsewhere: 3
        )
        let report = Self.report(Self.day + [Logged.surface(metrics.logLine(for: .surface(.numbered(1))), at: .soak(20_000))])

        #expect(report.verdict == .pass)
        #expect(report.markdown.contains("| \(Named.wallpaper(3)) | 200 | 1.56 | mid-pass | 0 | 3 |"))
    }

    @Test
    func `too few samples leaves the soak incomplete`() {
        let report = Self.report(Self.day, samples: Array(Self.samples().prefix(150)))

        #expect(report.verdict == .incomplete([
            "Livepaper's memory: 150 samples, under 200", "WallpaperExtension's memory: 0 samples, under 200",
        ]))
    }

    @Test
    func `hourly RSS means for the app and the extension`() {
        let report = Self.report(Self.day, samples: Self.samples { $0 * 1_024 })

        #expect(report.markdown.contains("| 2 | 2.0 MB | 2.0 MB |"))
        #expect(report.markdown.contains("| 24 | 24.0 MB | 24.0 MB |"))
    }

    @Test
    func `unparsed lines are listed`() {
        let report = Self.report(Self.day + [Logged.extensionLine("extension: woken up", at: .soak(5))])

        #expect(report.markdown.contains("1 unparsed"))
        #expect(report.markdown.contains("extension: woken up"))
    }
}
