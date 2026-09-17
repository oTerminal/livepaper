import Foundation
import Testing
@testable import DesignSystem

struct MotionTests {
    @Test(arguments: [
        Motion.Duration.hover,
        Motion.Duration.press,
        Motion.Duration.tooltip,
        Motion.Duration.popover,
        Motion.Duration.menu,
        Motion.Duration.panel,
    ])
    func `UI motion stays under 300 ms`(duration: TimeInterval) {
        #expect(duration < 0.3)
    }

    @Test func `sheets stay within 500 ms`() {
        #expect(Motion.Duration.sheet <= 0.5)
    }

    @Test func `exits are quicker than enters`() {
        let enter = Motion.Duration.popover

        #expect(Motion.Duration.exit(for: enter) < enter)
    }
}
