import SwiftUI

/// Motion tokens. Every animation in the app is built from these; raw durations,
/// curves and springs outside this package are a lint error.
///
/// Values come from the design skills (docs/design/skill-mapping.md): UI motion
/// stays under 300 ms, enters and exits ease out, nothing eases in, and exits
/// are quicker than enters.
public nonisolated enum Motion {
    /// How long an element takes to enter, in seconds.
    public enum Duration {
        public static let hover: TimeInterval = 0.12
        public static let press: TimeInterval = 0.14
        public static let tooltip: TimeInterval = 0.15
        public static let popover: TimeInterval = 0.18
        public static let menu: TimeInterval = 0.20
        public static let panel: TimeInterval = 0.25
        /// Sheets and onboarding cards travel further, so they alone may exceed 300 ms.
        public static let sheet: TimeInterval = 0.35

        /// Exits run faster than enters: the user has already decided.
        public static func exit(for enter: TimeInterval) -> TimeInterval {
            enter * 0.7
        }
    }

    public enum Curve {
        /// Enters and exits.
        public static let easeOut = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.23, y: 1),
            endControlPoint: UnitPoint(x: 0.32, y: 1)
        )
        /// Movement of something already on screen.
        public static let easeInOut = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.77, y: 0),
            endControlPoint: UnitPoint(x: 0.175, y: 1)
        )
        /// Sheets and drawers.
        public static let drawer = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.32, y: 0.72),
            endControlPoint: UnitPoint(x: 0, y: 1)
        )
    }

    public enum Spring {
        /// State changes in controls.
        public static let ui = Animation.spring(duration: 0.3, bounce: 0)
        /// Elements changing position.
        public static let move = Animation.spring(duration: 0.4, bounce: 0)
        /// Only after a gesture that carried velocity.
        public static let momentum = Animation.spring(duration: 0.4, bounce: 0.2)
    }

    /// An ease-out animation for an entering element.
    public static func enter(_ duration: TimeInterval) -> Animation {
        .timingCurve(Curve.easeOut, duration: duration)
    }

    /// An ease-out animation for a leaving element, quicker than its enter.
    public static func exit(_ enterDuration: TimeInterval) -> Animation {
        .timingCurve(Curve.easeOut, duration: Duration.exit(for: enterDuration))
    }
}
