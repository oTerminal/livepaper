import Foundation

/// One process at one of `soak.sh`'s five-minute samples: a row of `samples.csv`,
/// `time,process,pid,cpu,rss_kb`.
public struct ResourceSample: Equatable, Sendable {
    public var time: Date
    public var process: String
    public var pid: Int
    /// Percent of one core, at that moment.
    public var cpu: Double
    public var rssKilobytes: Int

    public init(time: Date, process: String, pid: Int, cpu: Double, rssKilobytes: Int) {
        self.time = time
        self.process = process
        self.pid = pid
        self.cpu = cpu
        self.rssKilobytes = rssKilobytes
    }

    /// Every row after the header; a row that does not read is counted, not guessed at.
    public static func read(csv: String) -> (samples: [ResourceSample], unreadRows: Int) {
        var samples: [ResourceSample] = []
        var unread = 0
        for row in CSV.rows(csv, header: "time,process,pid,cpu,rss_kb") {
            guard row.count == 5, let time = Timestamp.date(row[0]), !row[1].isEmpty, let pid = Int(row[2]),
                  let cpu = Double(row[3]), let rss = Int(row[4]) else {
                unread += 1
                continue
            }
            samples.append(ResourceSample(time: time, process: String(row[1]), pid: pid, cpu: cpu, rssKilobytes: rss))
        }
        return (samples, unread)
    }
}

/// One process's resident memory over the soak, by hour from its start, and the
/// rule it is held to: hour 24's mean at most 10 % over hour 2's; hour 1 is
/// warm-up; under 200 samples, inconclusive.
public struct MemoryTrend: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// `growth` is hour 24's mean over hour 2's, less one.
        case pass(growth: Double)
        case fail(growth: Double)
        case inconclusive(String)
    }

    public static let minimumSamples = 200
    public static let allowedGrowth = 0.10
    public static let firstHour = 2
    public static let lastHour = 24

    public var process: String
    /// Mean RSS in kilobytes, by hour: hour 1 is the soak's first.
    public var hourlyMeans: [Int: Double]
    public var sampleCount: Int
    public var verdict: Verdict

    public init(process: String, samples: [ResourceSample], start: Date) {
        let own = samples.filter { $0.process == process && $0.time >= start }
        var byHour: [Int: [Int]] = [:]
        for sample in own {
            byHour[Int(sample.time.timeIntervalSince(start) / 3_600) + 1, default: []].append(sample.rssKilobytes)
        }
        self.process = process
        hourlyMeans = byHour.mapValues { Double($0.reduce(0, +)) / Double($0.count) }
        sampleCount = own.count
        if own.count < Self.minimumSamples {
            verdict = .inconclusive("\(own.count) samples, under \(Self.minimumSamples)")
        } else if let first = hourlyMeans[Self.firstHour], let last = hourlyMeans[Self.lastHour] {
            let growth = last / first - 1
            verdict = growth <= Self.allowedGrowth ? .pass(growth: growth) : .fail(growth: growth)
        } else {
            verdict = .inconclusive("no samples in hour \(hourlyMeans[Self.firstHour] == nil ? Self.firstHour : Self.lastHour)")
        }
    }
}

/// The soak's CSVs: plain comma-separated fields, no quoting (`soak.sh` writes none).
enum CSV {
    /// The rows after `header`, each split into its fields; blank lines skipped.
    static func rows(_ text: String, header: String) -> [[Substring]] {
        text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != header }
            .map { $0.split(separator: ",", omittingEmptySubsequences: false) }
    }
}
