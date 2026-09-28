import Foundation
import LivepaperSoak
import Testing

/// "Hour 24's mean RSS at most 10 % over hour 2's, app and extension; hour 1 is
/// warm-up; under 200 samples, inconclusive" (M8-hardening.md, "Energy, idle and memory").
struct MemoryTests {
    /// One sample every 5 minutes from the soak's start, `rss(hour)` kilobytes in hour `hour` (1-based).
    static func samples(count: Int = 288, process: String = "WallpaperExtension", rss: (Int) -> Int) -> [ResourceSample] {
        (0..<count).map { index in
            let seconds = TimeInterval(index * 300 + 60)
            return ResourceSample(time: .soak(seconds), process: process, pid: 711, cpu: 1.5, rssKilobytes: rss(Int(seconds) / 3_600 + 1))
        }
    }

    static let rows: [Row<[ResourceSample], MemoryTrend.Verdict>] = [
        Row("flat", samples { _ in 100_000 }, .pass(growth: 0)),
        Row("hour 1 is warm-up", samples { $0 == 1 ? 20_000 : 100_000 }, .pass(growth: 0)),
        Row("9 % more by hour 24", samples { $0 == 24 ? 109_000 : 100_000 }, .pass(growth: 0.09)),
        Row("11 % more by hour 24", samples { $0 == 24 ? 111_000 : 100_000 }, .fail(growth: 0.11)),
        Row("under 200 samples", samples(count: 199) { _ in 100_000 }, .inconclusive("199 samples, under 200")),
        Row("no hour 24", samples(count: 240) { _ in 100_000 }, .inconclusive("no samples in hour 24")),
    ]

    @Test(arguments: rows)
    func `the memory rule`(row: Row<[ResourceSample], MemoryTrend.Verdict>) throws {
        let trend = MemoryTrend(process: "WallpaperExtension", samples: row.input, start: .soakStart)

        switch (trend.verdict, row.expected) {
        case let (.pass(growth), .pass(expected)), let (.fail(growth), .fail(expected)):
            #expect(abs(growth - expected) < 0.000_1)
        default:
            #expect(trend.verdict == row.expected)
        }
    }

    @Test
    func `hourly means, and only the process asked for`() {
        let samples = Self.samples(count: 36) { $0 * 1_000 } + Self.samples(count: 36, process: "Livepaper") { _ in 5 }
        let trend = MemoryTrend(process: "WallpaperExtension", samples: samples, start: .soakStart)

        #expect(trend.hourlyMeans == [1: 1_000, 2: 2_000, 3: 3_000])
        #expect(trend.sampleCount == 36)
    }

    @Test
    func `reads soak.sh's samples, counting a row it cannot read`() throws {
        let csv = """
        time,process,pid,cpu,rss_kb
        2026-09-28T10:00:00+0100,WallpaperExtension,711,2.5,104232
        2026-09-28T10:00:00+0100,Livepaper,500,0.0,88120
        2026-09-28T10:05:00+0100,WallpaperExtension,711,,104300

        """

        let read = ResourceSample.read(csv: csv)

        #expect(read.samples == [
            ResourceSample(
                time: Date(timeIntervalSince1970: 1_790_586_000), process: "WallpaperExtension", pid: 711, cpu: 2.5, rssKilobytes: 104_232
            ),
            ResourceSample(time: Date(timeIntervalSince1970: 1_790_586_000), process: "Livepaper", pid: 500, cpu: 0, rssKilobytes: 88_120),
        ])
        #expect(read.unreadRows == 1)
    }
}
