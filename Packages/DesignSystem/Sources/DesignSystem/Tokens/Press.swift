import SwiftUI

/// Press feedback: a control shrinks slightly on pointer down, so the response
/// lands before the action does.
public nonisolated enum Press {
    /// Always 0.96. Anything under 0.95 reads as exaggerated.
    public static let pressedScale: CGFloat = 0.96

    /// The scale of a control. `isStatic` opts out where movement would distract.
    public static func scale(isPressed: Bool, isStatic: Bool = false) -> CGFloat {
        isPressed && !isStatic ? pressedScale : 1
    }
}

/// Applies `Press` to any button label. The press lands at once and the release
/// eases out, so a quick click still shows.
public struct PressButtonStyle: ButtonStyle {
    private let isStatic: Bool

    public init(isStatic: Bool = false) {
        self.isStatic = isStatic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(Press.scale(isPressed: configuration.isPressed, isStatic: isStatic))
            .animation(
                configuration.isPressed ? nil : Motion.exit(Motion.Duration.press),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressButtonStyle {
    /// Scale 0.96 on pointer down.
    public static var press: PressButtonStyle { PressButtonStyle() }
}
