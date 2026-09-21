import SwiftUI

/// The hairline drawn inside the edge of every image, so posters keep a
/// consistent edge on any background.
public nonisolated enum Outline {
    /// Pure black or pure white only: a tinted neutral picks up the surface
    /// colour beneath it and reads as dirt on the image edge.
    public struct Stroke: Equatable, Sendable {
        public let white: Double
        public let opacity: Double

        public var color: Color {
            Color(white: white, opacity: opacity)
        }
    }

    public static let width: CGFloat = 1

    public static func stroke(scheme: ColorScheme, contrast: ColorSchemeContrast) -> Stroke {
        Stroke(
            white: scheme == .dark ? 1 : 0,
            opacity: contrast == .increased ? 0.35 : 0.10
        )
    }
}

extension View {
    /// Draws the image outline inside `shape`, without changing the layout.
    public func imageOutline(_ shape: some InsettableShape) -> some View {
        modifier(ImageOutline(shape: shape))
    }
}

private struct ImageOutline<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Accessibility private var accessibility
    let shape: S

    func body(content: Content) -> some View {
        content.overlay {
            shape
                .strokeBorder(Outline.stroke(scheme: scheme, contrast: accessibility.contrast).color, lineWidth: Outline.width)
                .allowsHitTesting(false)
        }
    }
}
