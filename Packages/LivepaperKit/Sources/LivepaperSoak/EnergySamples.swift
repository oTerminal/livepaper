import Foundation

/// One process in one `top` sample of `energy.sh`: a row of `energy.csv`,
/// `phase,second,process,pid,cpu,power,mem_kb`. `power` is top's unitless
/// energy-impact score, `mem_kb` its memory footprint.
public struct EnergySample: Equatable, Sendable {
    public var phase: String
    /// Seconds since the phase began: for `covered` and `displayAsleep`, since the event.
    public var second: Int
    public var process: String
    public var pid: Int
    public var cpu: Double
    public var power: Double
    public var memoryKilobytes: Int

    public init(phase: String, second: Int, process: String, pid: Int, cpu: Double, power: Double, memoryKilobytes: Int = 0) {
        self.phase = phase
        self.second = second
        self.process = process
        self.pid = pid
        self.cpu = cpu
        self.power = power
        self.memoryKilobytes = memoryKilobytes
    }

    public static func read(csv: String) -> (samples: [EnergySample], unreadRows: Int) {
        var samples: [EnergySample] = []
        var unread = 0
        for row in CSV.rows(csv, header: "phase,second,process,pid,cpu,power,mem_kb") {
            guard row.count == 7, !row[0].isEmpty, let second = Int(row[1]), !row[2].isEmpty, let pid = Int(row[3]),
                  let cpu = Double(row[4]), let power = Double(row[5]), let memory = Int(row[6]) else {
                unread += 1
                continue
            }
            samples.append(EnergySample(
                phase: String(row[0]), second: second, process: String(row[2]), pid: pid, cpu: cpu, power: power, memoryKilobytes: memory
            ))
        }
        return (samples, unread)
    }
}

/// One `powermetrics` sample, taken with `sudo`: a row of `watts.csv`, `phase,second,combined_mw,gpu_mw`.
public struct WattSample: Equatable, Sendable {
    public var phase: String
    public var second: Int
    public var combinedMilliwatts: Double
    public var gpuMilliwatts: Double

    public init(phase: String, second: Int, combinedMilliwatts: Double, gpuMilliwatts: Double) {
        self.phase = phase
        self.second = second
        self.combinedMilliwatts = combinedMilliwatts
        self.gpuMilliwatts = gpuMilliwatts
    }

    public static func read(csv: String) -> (samples: [WattSample], unreadRows: Int) {
        var samples: [WattSample] = []
        var unread = 0
        for row in CSV.rows(csv, header: "phase,second,combined_mw,gpu_mw") {
            guard row.count == 4, !row[0].isEmpty, let second = Int(row[1]), let combined = Double(row[2]), let gpu = Double(row[3]) else {
                unread += 1
                continue
            }
            samples.append(WattSample(phase: String(row[0]), second: second, combinedMilliwatts: combined, gpuMilliwatts: gpu))
        }
        return (samples, unread)
    }
}

/// An `energy.sh` run: its samples by phase, each process's instances summed per sample.
public struct EnergyMeasurement: Equatable, Sendable {
    public enum Phase {
        public static let paused = "paused"
        public static let playing = "playing"
        public static let covered = "covered"
        public static let displayAsleep = "displayAsleep"
        public static let idleApp = "idleApp"
        public static let idleExtension = "idleExtension"
    }

    public struct Reading: Equatable, Sendable {
        public var cpu: Double
        public var power: Double
        public var memoryKilobytes: Double

        public init(cpu: Double, power: Double, memoryKilobytes: Double = 0) {
            self.cpu = cpu
            self.power = power
            self.memoryKilobytes = memoryKilobytes
        }
    }

    public var samples: [EnergySample]
    /// Nil when `powermetrics` did not run: it "must be invoked as the superuser".
    public var watts: [WattSample]?

    public init(samples: [EnergySample], watts: [WattSample]?) {
        self.samples = samples
        self.watts = watts
    }

    public var phases: [String] {
        var seen: [String] = []
        for sample in samples where !seen.contains(sample.phase) { seen.append(sample.phase) }
        return seen
    }

    /// The seconds a phase was sampled at, whichever processes were running.
    public func seconds(in phase: String) -> [Int] {
        Set(samples.filter { $0.phase == phase }.map(\.second)).sorted()
    }

    /// The process at each second of the phase, every instance summed; a second it was not running at has none.
    /// top's clock is whole seconds, so two samples can share one: an instance's are averaged, then the instances summed.
    public func readings(_ process: String, in phase: String) -> [Int: Reading] {
        var instances: [Int: [Int: [EnergySample]]] = [:]
        for sample in samples where sample.phase == phase && sample.process == process {
            instances[sample.second, default: [:]][sample.pid, default: []].append(sample)
        }
        return instances.mapValues { byPID in
            byPID.values.reduce(Reading(cpu: 0, power: 0)) { sum, own in
                let count = Double(own.count)
                return Reading(
                    cpu: sum.cpu + own.map(\.cpu).reduce(0, +) / count,
                    power: sum.power + own.map(\.power).reduce(0, +) / count,
                    memoryKilobytes: sum.memoryKilobytes + Double(own.map(\.memoryKilobytes).reduce(0, +)) / count
                )
            }
        }
    }

    /// The mean over every second of the phase, a second the process was not running at counting as 0.
    public func mean(_ process: String, in phase: String) -> Reading? {
        let seconds = seconds(in: phase)
        guard !seconds.isEmpty else { return nil }
        let readings = readings(process, in: phase)
        let count = Double(seconds.count)
        return Reading(
            cpu: seconds.map { readings[$0]?.cpu ?? 0 }.reduce(0, +) / count,
            power: seconds.map { readings[$0]?.power ?? 0 }.reduce(0, +) / count,
            memoryKilobytes: seconds.map { readings[$0]?.memoryKilobytes ?? 0 }.reduce(0, +) / count
        )
    }
}
