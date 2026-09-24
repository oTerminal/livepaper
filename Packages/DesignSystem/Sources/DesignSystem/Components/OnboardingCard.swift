import SwiftUI

/// One step of first-run onboarding: an illustration, a title, a sentence, a
/// page indicator and one or two buttons, on an opaque card in the content layer.
///
/// Its three groups (illustration, text, buttons) enter once, 0.10 s apart, when
/// the card first appears, and never again. To move between steps, change the
/// card's values and keep its identity: the picture and the words crossfade and
/// nothing re-enters. The card tells a click from a key press itself: Return
/// presses the primary button too, and then the step changes with no animation.
/// Give the card a new `.id` only to replay the entrance.
///
/// An accessory, when a step needs controls of its own (onboarding's samples to
/// choose from), sits under the words and enters with them. Unlike the
/// illustration, which is a picture and hidden from VoiceOver, it is read and
/// can be pressed. A card alone (`stepCount` 1) shows no page dots.
public struct OnboardingCard<Illustration: View, Accessory: View>: View {
    @Accessibility private var accessibility
    @Environment(\.colorScheme) private var scheme
    @State private var hasEntered = false

    private let title: String
    private let message: String
    private let stepIndex: Int
    private let stepCount: Int
    private let primaryTitle: String
    private let onPrimary: () -> Void
    private let secondaryTitle: String?
    private let onSecondary: (() -> Void)?
    private let illustration: Illustration
    private let accessory: Accessory

    /// - Parameter stepIndex: Zero-based; VoiceOver reads it one-based ("Step 2 of 4").
    public init(
        title: String,
        message: String,
        stepIndex: Int,
        stepCount: Int,
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder illustration: () -> Illustration,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.message = message
        self.stepIndex = stepIndex
        self.stepCount = stepCount
        self.primaryTitle = primaryTitle
        self.onPrimary = onPrimary
        self.secondaryTitle = secondaryTitle
        self.onSecondary = onSecondary
        self.illustration = illustration()
        self.accessory = accessory()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.large) {
            picture
                .entering(group: 0, hasEntered: hasEntered)

            VStack(alignment: .leading, spacing: Spacing.large) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .contentTransition(.opacity)
                .animation(stepAnimation, value: stepIndex)
                .fixedSize(horizontal: false, vertical: true)

                // Comes and goes with its step and never animates: the card's height
                // snaps, and a fading accessory would be drawn over the buttons that
                // moved into its place. None, or a step with none, takes no room.
                accessory
            }
            .padding(.horizontal, Spacing.small)
            .entering(group: 1, hasEntered: hasEntered)

            HStack(spacing: Spacing.small) {
                pageIndicator
                Spacer(minLength: Spacing.large)
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle) { withoutAnimationIfKeyPress(onSecondary) }
                        .buttonStyle(.bordered)
                        // A new title is a new button: the glass stays whole (see DECISIONS.md).
                        .id(secondaryTitle)
                }
                Button(primaryTitle) { withoutAnimationIfKeyPress(onPrimary) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .id(primaryTitle)
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], Spacing.small)
            .entering(group: 2, hasEntered: hasEntered)
        }
        .padding(Spacing.small)
        .frame(width: Metrics.width)
        .background(fill, in: shape)
        .overlay {
            // Only under Increase Contrast, where a shadow alone is too faint an edge.
            if accessibility.increaseContrast {
                shape.strokeBorder(.separator, lineWidth: 2)
            } else if scheme == .dark {
                // Black shadows vanish on a dark window; a faint pure-white ring keeps the edge.
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .containerShape(shape)
        .shadow(color: .black.opacity(0.06), radius: Metrics.contactShadowRadius, y: Metrics.contactShadowOffset)
        .shadow(color: .black.opacity(0.14), radius: Metrics.ambientShadowRadius, y: Metrics.ambientShadowOffset)
        .onAppear { hasEntered = true }
    }

    /// Opaque, and lighter than the window in both appearances, so the card
    /// reads as raised even in dark mode where shadows barely show.
    private var fill: Color {
        scheme == .dark ? Color(nsColor: .windowBackgroundColor).mix(with: .white, by: 0.06) : Color(nsColor: .controlBackgroundColor)
    }

    /// A step change by click crossfades the picture, the words and the dots, each
    /// with its own scoped animation and nothing on the card itself, so the card's
    /// height, if it changes, snaps. By key press nothing animates.
    private var stepAnimation: Animation {
        accessibility.fade(Motion.enter(Motion.Duration.menu))
    }

    private var picture: some View {
        Color.clear
            .aspectRatio(Metrics.illustrationAspectRatio, contentMode: .fit)
            .overlay {
                illustration
                    .id(stepIndex)
                    .transition(.opacity)
            }
            .animation(stepAnimation, value: stepIndex)
            .clipShape(ConcentricRectangle())
            .imageOutline(ConcentricRectangle())
            .accessibilityHidden(true)
    }

    /// Nothing for a card alone: one dot would only say "Step 1 of 1".
    @ViewBuilder private var pageIndicator: some View {
        if stepCount > 1 {
            dots
        }
    }

    private var dots: some View {
        HStack(spacing: Spacing.small) {
            ForEach(0..<max(stepCount, 0), id: \.self) { index in
                // Opacity rather than a style swap, so the change can crossfade.
                Circle()
                    .fill(.primary)
                    .opacity(index == stepIndex ? 1 : Metrics.restingDotOpacity)
                    .frame(width: Metrics.dot, height: Metrics.dot)
            }
        }
        .animation(stepAnimation, value: stepIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(stepIndex + 1) of \(stepCount)", bundle: .module))
    }
}

extension OnboardingCard where Accessory == EmptyView {
    /// A card whose only controls are its buttons.
    public init(
        title: String,
        message: String,
        stepIndex: Int,
        stepCount: Int,
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder illustration: () -> Illustration
    ) {
        self.init(
            title: title,
            message: message,
            stepIndex: stepIndex,
            stepCount: stepCount,
            primaryTitle: primaryTitle,
            onPrimary: onPrimary,
            secondaryTitle: secondaryTitle,
            onSecondary: onSecondary,
            illustration: illustration,
            accessory: { EmptyView() }
        )
    }
}

extension View {
    fileprivate func entering(group: Int, hasEntered: Bool) -> some View {
        modifier(GroupEntrance(group: group, hasEntered: hasEntered))
    }
}

/// Opacity, a small rise and a blur that clears. Under Reduce Motion the helper
/// returns no delay and only the opacity changes.
private struct GroupEntrance: ViewModifier {
    @Accessibility private var accessibility
    let group: Int
    let hasEntered: Bool

    func body(content: Content) -> some View {
        let moves = !hasEntered && !accessibility.reduceMotion
        content
            .opacity(hasEntered ? 1 : 0)
            .offset(y: moves ? Metrics.entranceRise : 0)
            .blur(radius: moves ? Metrics.entranceBlur : 0)
            .animation(
                accessibility.animation(Motion.enter(Motion.Duration.sheet))
                    .delay(accessibility.staggerDelay(forOnboardingGroup: group)),
                value: hasEntered
            )
    }
}

private nonisolated enum Metrics {
    /// Wide enough for two buttons and the indicator on one line; narrow enough that the message wraps short.
    static let width: CGFloat = 440
    static let illustrationAspectRatio: CGFloat = 16 / 10
    static let dot: CGFloat = 6
    static let restingDotOpacity = 0.25
    /// A small fixed rise, not a slide: the card is already where it belongs.
    static let entranceRise: CGFloat = 8
    static let entranceBlur: CGFloat = 4
    static let contactShadowRadius: CGFloat = 2
    static let contactShadowOffset: CGFloat = 1
    static let ambientShadowRadius: CGFloat = 24
    static let ambientShadowOffset: CGFloat = 12
}
