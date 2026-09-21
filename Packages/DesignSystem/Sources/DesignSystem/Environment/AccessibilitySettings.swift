import SwiftUI

/// The accessibility settings a component adapts to. Components read these
/// through `@Accessibility`, never the system environment values directly, so
/// the Gallery can override them for one page without touching System Settings.
public nonisolated struct AccessibilitySettings: Equatable, Sendable {
    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var increaseContrast: Bool
    /// 1 everywhere except the Gallery's slow-motion switch.
    public var motionSpeed: Double

    public init(
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false,
        motionSpeed: Double = 1
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.motionSpeed = motionSpeed
    }

    /// The animation to run for a pointer-driven change: the crossfade under
    /// Reduce Motion, `animation` otherwise.
    public func animation(_ animation: Animation) -> Animation {
        let resolved = Motion.resolve(animation, reduceMotion: reduceMotion)
        return motionSpeed == 1 ? resolved : resolved.speed(motionSpeed)
    }

    /// The entrance delay for the item at `index` of a staggered group.
    public func staggerDelay(forIndex index: Int) -> TimeInterval {
        Stagger.delay(forIndex: index, reduceMotion: reduceMotion) / motionSpeed
    }

    /// The entrance delay for a group of an onboarding card.
    public func staggerDelay(forOnboardingGroup group: Int) -> TimeInterval {
        Stagger.delay(forOnboardingGroup: group, reduceMotion: reduceMotion) / motionSpeed
    }

    public var contrast: ColorSchemeContrast {
        increaseContrast ? .increased : .standard
    }
}

/// Replaces individual system settings for a subtree. `nil` follows the system.
public nonisolated struct AccessibilityOverrides: Equatable, Sendable {
    public var reduceMotion: Bool?
    public var reduceTransparency: Bool?
    public var increaseContrast: Bool?
    public var motionSpeed: Double?

    public init(
        reduceMotion: Bool? = nil,
        reduceTransparency: Bool? = nil,
        increaseContrast: Bool? = nil,
        motionSpeed: Double? = nil
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.motionSpeed = motionSpeed
    }
}

extension EnvironmentValues {
    @Entry public var accessibilityOverrides = AccessibilityOverrides()
}

/// The accessibility settings in effect for this view: the system's, with any
/// `accessibilityOverrides` applied on top.
@propertyWrapper
public struct Accessibility: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityOverrides) private var overrides

    public init() {}

    public var wrappedValue: AccessibilitySettings {
        AccessibilitySettings(
            reduceMotion: overrides.reduceMotion ?? reduceMotion,
            reduceTransparency: overrides.reduceTransparency ?? reduceTransparency,
            increaseContrast: overrides.increaseContrast ?? (contrast == .increased),
            motionSpeed: overrides.motionSpeed ?? 1
        )
    }
}
