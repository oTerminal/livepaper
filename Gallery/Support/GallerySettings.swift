import DesignSystem
import SwiftUI

/// The toolbar's switches. They override the environment for the page; they do
/// not change System Settings.
@Observable
final class GallerySettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: Self { self }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var slowMotion = false
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false
    var busyBackdrop = false
    var appearance = Appearance.system

    /// Switches can be preset from the command line, such as `-busyBackdrop YES -appearance Dark`.
    init(defaults: UserDefaults = .standard) {
        slowMotion = defaults.bool(forKey: "slowMotion")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        reduceTransparency = defaults.bool(forKey: "reduceTransparency")
        increaseContrast = defaults.bool(forKey: "increaseContrast")
        busyBackdrop = defaults.bool(forKey: "busyBackdrop")
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .system
    }

    /// Only the switches that are on override anything; the rest follow the system.
    var overrides: AccessibilityOverrides {
        AccessibilityOverrides(
            reduceMotion: reduceMotion ? true : nil,
            reduceTransparency: reduceTransparency ? true : nil,
            increaseContrast: increaseContrast ? true : nil,
            motionSpeed: slowMotion ? 0.1 : nil
        )
    }
}
