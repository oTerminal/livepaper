import Foundation

/// S2's energy budget for one display playing 4K60 HEVC with the desktop visible,
/// and M8's idle rows, each held to a measurement line by line.
public struct EnergyBudget: Sendable {
    public enum Check: String, CaseIterable, Sendable {
        case extensionCPU
        case extensionPower
        case decoderCPU
        case decoderPower
        case windowServerOverPaused
        case backWhenCovered
        case decoderKeptWhenCovered
        case backWhenAsleep
        case decoderGoneWhenAsleep
        case idleApp
        case idleExtension
        case watts
    }

    public enum Outcome: Equatable, Sendable {
        case pass
        case fail
        /// A number kept as a baseline, held to nothing.
        case recorded
        case notMeasured
        case inconclusive(String)
    }

    public struct Line: Equatable, Sendable {
        public var check: Check
        public var name: String
        public var measured: String
        public var limit: String
        public var outcome: Outcome
    }

    public static let extensionProcess = "WallpaperExtension"
    public static let decoderProcess = "VTDecoderXPCService"
    public static let windowServer = "WindowServer"
    public static let appProcess = "Livepaper"

    public var extensionCPU: Double
    public var extensionPower: Double
    public var decoderCPU: Double
    public var decoderPower: Double
    public var windowServerOverPaused: Double
    public var returnSeconds: Int
    public var idleMeanCPU: Double
    public var idlePeakCPU: Double
    public var idleSamples: Int

    /// Spikes/results/S2.md's numbers, and M8's reading of the roadmap's "about 0 %".
    public static let s2 = EnergyBudget(
        extensionCPU: 4, extensionPower: 5, decoderCPU: 5, decoderPower: 5, windowServerOverPaused: 25, returnSeconds: 5,
        idleMeanCPU: 0.1, idlePeakCPU: 1, idleSamples: 60
    )

    public func judge(_ measurement: EnergyMeasurement) -> [Line] {
        typealias Phase = EnergyMeasurement.Phase
        let playingExtension = measurement.mean(Self.extensionProcess, in: Phase.playing)
        let playingDecoder = measurement.mean(Self.decoderProcess, in: Phase.playing)
        var lines = [
            ceiling(.extensionCPU, "Extension CPU", playingExtension?.cpu, extensionCPU, unit: " %"),
            ceiling(.extensionPower, "Extension power", playingExtension?.power, extensionPower),
            ceiling(.decoderCPU, "VTDecoderXPCService CPU, summed", playingDecoder?.cpu, decoderCPU, unit: " %"),
            ceiling(.decoderPower, "VTDecoderXPCService power, summed", playingDecoder?.power, decoderPower),
        ]
        let overPaused = measurement.mean(Self.windowServer, in: Phase.playing).flatMap { playing in
            measurement.mean(Self.windowServer, in: Phase.paused).map { playing.power - $0.power }
        }
        lines.append(ceiling(.windowServerOverPaused, "WindowServer power over its paused score", overPaused, windowServerOverPaused))
        lines += returnLines(measurement, phase: Phase.covered, back: .backWhenCovered, decoder: .decoderKeptWhenCovered)
        lines += returnLines(measurement, phase: Phase.displayAsleep, back: .backWhenAsleep, decoder: .decoderGoneWhenAsleep)
        lines.append(idle(.idleApp, "The app idle, popover and window closed", measurement, process: Self.appProcess, phase: Phase.idleApp))
        lines.append(idle(
            .idleExtension, "The extension idle, every display covered", measurement,
            process: Self.extensionProcess, phase: Phase.idleExtension
        ))
        lines.append(watts(measurement))
        return lines
    }

    private func ceiling(_ check: Check, _ name: String, _ value: Double?, _ limit: Double, unit: String = "") -> Line {
        guard let value else {
            return Line(check: check, name: name, measured: "not measured", limit: "\(format(limit))\(unit)", outcome: .notMeasured)
        }
        return Line(
            check: check, name: name, measured: "\(format(value))\(unit)", limit: "at most \(format(limit))\(unit)",
            outcome: value <= limit ? .pass : .fail
        )
    }

    /// After covering or display sleep: the second from which each of the three
    /// processes stays at or under its highest paused sample, and the decoder kept or gone.
    private func returnLines(_ measurement: EnergyMeasurement, phase: String, back: Check, decoder: Check) -> [Line] {
        let isCovered = phase == EnergyMeasurement.Phase.covered
        let backName = isCovered ? "All three at paused levels after covering" : "All three at paused levels after display sleep"
        let decoderName = isCovered ? "VTDecoderXPCService kept while covered" : "VTDecoderXPCService gone while the display sleeps"
        let seconds = measurement.seconds(in: phase)
        guard !seconds.isEmpty else {
            return [
                Line(check: back, name: backName, measured: "not measured", limit: "within \(returnSeconds) s", outcome: .notMeasured),
                Line(
                    check: decoder, name: decoderName, measured: "not measured",
                    limit: isCovered ? "kept" : "gone within \(returnSeconds) s", outcome: .notMeasured
                ),
            ]
        }
        let processes = [Self.extensionProcess, Self.decoderProcess, Self.windowServer]
        let returns = processes.map { process -> Int? in
            let paused = measurement.readings(process, in: EnergyMeasurement.Phase.paused).values
            let ceiling = EnergyMeasurement.Reading(cpu: paused.map(\.cpu).max() ?? 0, power: paused.map(\.power).max() ?? 0)
            let readings = measurement.readings(process, in: phase)
            return settled(seconds) { second in
                let reading = readings[second] ?? EnergyMeasurement.Reading(cpu: 0, power: 0)
                return reading.cpu <= ceiling.cpu && reading.power <= ceiling.power
            }
        }
        let slowest = returns.contains(nil) ? nil : returns.compactMap(\.self).max()
        let backLine = Line(
            check: back, name: backName, measured: slowest.map { "\($0) s" } ?? "not back in \(seconds.last ?? 0) s",
            limit: "within \(returnSeconds) s", outcome: slowest.map { $0 <= returnSeconds } == true ? .pass : .fail
        )
        let decoders = measurement.readings(Self.decoderProcess, in: phase)
        let decoderLine: Line
        if isCovered {
            let kept = seconds.allSatisfy { decoders[$0] != nil }
            decoderLine = Line(
                check: decoder, name: decoderName, measured: kept ? "kept" : "released", limit: "kept", outcome: kept ? .pass : .fail
            )
        } else {
            decoderLine = released(decoders, seconds: seconds, measurement: measurement, check: decoder, name: decoderName)
        }
        return [backLine, decoderLine]
    }

    /// The decoder's session released when the display sleeps. M5-engine.md found the
    /// `VTDecoderXPCService` process never exits, so "gone" is no session and no buffers:
    /// a service that exits is judged by when, and one still running is recorded with its
    /// footprint against its footprint while playing, for a person to read.
    private func released(
        _ decoders: [Int: EnergyMeasurement.Reading], seconds: [Int], measurement: EnergyMeasurement, check: Check, name: String
    ) -> Line {
        let limit = "no session and no buffers within \(returnSeconds) s"
        if let gone = settled(seconds, { decoders[$0] == nil }) {
            let outcome: Outcome = gone <= returnSeconds ? .pass : .fail
            return Line(check: check, name: name, measured: "exited at \(gone) s", limit: limit, outcome: outcome)
        }
        let last = seconds.last.flatMap { decoders[$0] }?.memoryKilobytes ?? 0
        let playing = measurement.mean(Self.decoderProcess, in: EnergyMeasurement.Phase.playing)?.memoryKilobytes
        let measured = "running, \(megabytes(last)) at the end" + (playing.map { ", \(megabytes($0)) playing" } ?? "")
        return Line(check: check, name: name, measured: measured, limit: limit, outcome: .recorded)
    }

    private func megabytes(_ kilobytes: Double) -> String {
        "\(format(kilobytes / 1_024)) MB"
    }

    /// The first second from which `holds` is true to the phase's end, or nil.
    private func settled(_ seconds: [Int], _ holds: (Int) -> Bool) -> Int? {
        var first: Int?
        for second in seconds {
            if holds(second) {
                first = first ?? second
            } else {
                first = nil
            }
        }
        return first
    }

    private func idle(_ check: Check, _ name: String, _ measurement: EnergyMeasurement, process: String, phase: String) -> Line {
        let limit = "mean at most \(format(idleMeanCPU)) %, no sample over \(format(idlePeakCPU)) %"
        let seconds = measurement.seconds(in: phase)
        guard !seconds.isEmpty else { return Line(check: check, name: name, measured: "not measured", limit: limit, outcome: .notMeasured) }
        let readings = measurement.readings(process, in: phase)
        let cpu = seconds.map { readings[$0]?.cpu ?? 0 }
        let mean = cpu.reduce(0, +) / Double(cpu.count)
        let peak = cpu.max() ?? 0
        let measured = "mean \(format(mean, digits: 2)) %, peak \(format(peak)) %, \(cpu.count) samples"
        guard cpu.count >= idleSamples else {
            return Line(
                check: check, name: name, measured: measured, limit: limit, outcome: .inconclusive("\(cpu.count) samples of \(idleSamples)")
            )
        }
        return Line(
            check: check, name: name, measured: measured, limit: limit, outcome: mean <= idleMeanCPU && peak <= idlePeakCPU ? .pass : .fail
        )
    }

    private func watts(_ measurement: EnergyMeasurement) -> Line {
        let name = "Watts, from powermetrics"
        guard let watts = measurement.watts, !watts.isEmpty else {
            return Line(
                check: .watts, name: name, measured: "none: powermetrics must be run as the superuser",
                limit: "recorded", outcome: .notMeasured
            )
        }
        var phases: [String] = []
        for sample in watts where !phases.contains(sample.phase) { phases.append(sample.phase) }
        let measured = phases.map { phase in
            let own = watts.filter { $0.phase == phase }
            let combined = own.map(\.combinedMilliwatts).reduce(0, +) / Double(own.count) / 1_000
            let gpu = own.map(\.gpuMilliwatts).reduce(0, +) / Double(own.count) / 1_000
            return "\(phase): \(format(combined, digits: 2)) W, GPU \(format(gpu, digits: 2)) W"
        }
        return Line(check: .watts, name: name, measured: measured.joined(separator: "; "), limit: "recorded", outcome: .recorded)
    }

    private func format(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }
}
