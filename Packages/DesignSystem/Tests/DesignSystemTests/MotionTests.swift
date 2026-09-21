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

struct ReducedMotionTests {
    @Test func `the Reduce Motion crossfade lasts 200 ms`() {
        #expect(Motion.Duration.reducedCrossfade == 0.2)
    }

    @Test func `with Reduce Motion the crossfade replaces a bouncy spring`() {
        #expect(Motion.resolve(Motion.Spring.momentum, reduceMotion: true) == Motion.reducedCrossfade)
    }

    @Test func `without Reduce Motion the animation is unchanged`() {
        #expect(Motion.resolve(Motion.Spring.momentum, reduceMotion: false) == Motion.Spring.momentum)
    }
}
