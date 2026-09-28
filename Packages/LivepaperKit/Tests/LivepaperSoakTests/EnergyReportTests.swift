import Foundation
import LivepaperSoak
import Testing

struct EnergyReportTests {
    @Test
    func `a video run is held to the budget line by line`() {
        let report = EnergyReport(measurement: EnergyMeasurement(samples: EnergyBudgetTests.s2Run, watts: nil), kind: .video)

        #expect(report.markdown.contains("| Extension CPU | 2.7 % | at most 4.0 % | pass |"))
        #expect(report.markdown.contains("| WindowServer power over its paused score | 21.6 | at most 25.0 | pass |"))
        #expect(report.markdown.contains(
            "| Watts, from powermetrics | none: powermetrics must be run as the superuser | recorded | not measured |"
        ))
    }

    @Test
    func `a scene run is a baseline, first measured here`() {
        let report = EnergyReport(measurement: EnergyMeasurement(samples: EnergyBudgetTests.s2Run, watts: nil), kind: .scene)

        #expect(report.markdown.contains("| Extension CPU | 2.7 % | baseline | recorded |"))
        #expect(!report.markdown.contains("| pass |"))
    }

    @Test
    func `each phase's means, per process`() {
        let report = EnergyReport(measurement: EnergyMeasurement(samples: EnergyBudgetTests.s2Run, watts: nil), kind: .video)

        #expect(report.markdown.contains("| playing | 2.7 % / 3.6 | 3.5 % / 3.6 | 45.1 % / 56.5 |  |"))
    }
}
