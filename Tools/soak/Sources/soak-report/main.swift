import Foundation
import LivepaperSoak

// Reads a soak's files and prints its report as Markdown (M8-hardening.md):
//
//   soak-report soak --log log.txt --samples samples.csv --events events.csv
//   soak-report energy --samples energy.csv [--watts watts.csv] [--scene]
//
// Exit status: 0 printed, 2 usage, 3 a file could not be read.

let usage = """
    usage: soak-report soak --log FILE --samples FILE --events FILE
           soak-report energy --samples FILE [--watts FILE] [--scene]
    """

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("soak-report: \(message)\n".utf8))
    exit(status)
}

/// `--name value` pairs and bare `--flag`s after the command.
struct Options {
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ arguments: ArraySlice<String>, flags known: Set<String>) {
        var arguments = arguments
        while let argument = arguments.popFirst() {
            guard argument.hasPrefix("--") else { fail("unexpected \(argument)\n\(usage)", status: 2) }
            let name = String(argument.dropFirst(2))
            if known.contains(name) {
                flags.insert(name)
            } else if let value = arguments.popFirst() {
                values[name] = value
            } else {
                fail("--\(name) needs a value\n\(usage)", status: 2)
            }
        }
    }

    func required(_ name: String) -> String {
        guard let value = values[name] else { fail("--\(name) is required\n\(usage)", status: 2) }
        return value
    }
}

func contents(of path: String) -> String {
    do {
        return try String(contentsOf: URL(filePath: path), encoding: .utf8)
    } catch {
        fail("cannot read \(path): \(error.localizedDescription)", status: 3)
    }
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "soak":
    let options = Options(arguments.dropFirst(), flags: [])
    let log = SoakLog(text: contents(of: options.required("log")))
    let samples = ResourceSample.read(csv: contents(of: options.required("samples")))
    let markers = SoakMarker.read(csv: contents(of: options.required("events")))
    let report = SoakReport(
        log: log, samples: samples.samples, markers: markers.markers,
        unreadSampleRows: samples.unreadRows, unreadMarkerRows: markers.unreadRows, timeZone: .current
    )
    print(report.markdown, terminator: "")
case "energy":
    let options = Options(arguments.dropFirst(), flags: ["scene"])
    let samples = EnergySample.read(csv: contents(of: options.required("samples")))
    let watts = options.values["watts"].map { WattSample.read(csv: contents(of: $0)).samples }
    let report = EnergyReport(
        measurement: EnergyMeasurement(samples: samples.samples, watts: watts),
        kind: options.flags.contains("scene") ? .scene : .video, unreadRows: samples.unreadRows
    )
    print(report.markdown, terminator: "")
default:
    fail(usage, status: 2)
}
