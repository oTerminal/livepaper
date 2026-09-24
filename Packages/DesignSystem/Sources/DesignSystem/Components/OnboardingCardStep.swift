import SwiftUI

/// What one step of an `OnboardingCard` says and offers. The card takes every
/// step's, so that it can be as tall as the tallest before any is shown.
public struct OnboardingCardStep: Hashable, Sendable {
    public var title: String
    public var message: String
    public var primaryTitle: String
    public var secondaryTitle: String?
    /// Whether the card's accessory belongs to this step.
    public var showsAccessory: Bool

    public init(title: String, message: String, primaryTitle: String, secondaryTitle: String? = nil, showsAccessory: Bool = false) {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.showsAccessory = showsAccessory
    }
}

/// What the last step change's transaction said, read when the focus moves. A
/// reference, since a transaction is read while the view updates, where state
/// may not change.
final class OnboardingCardStepChange {
    var crossfades = false
}

/// Lays out an `OnboardingCard`'s showing page and its unseen sizing pages on
/// top of one another, as tall as the tallest, and gives every page that height:
/// the showing page's dots and buttons sit at its bottom, where the tallest step
/// has them.
struct OnboardingCardPageLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(
            width: proposal.width ?? sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
