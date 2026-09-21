import CoreGraphics

/// How far an element follows a drag that has gone `offset` past an edge:
/// progressively less, and never as far as `limit`. A hard stop reads as frozen;
/// resistance reads as "nothing more here".
public nonisolated func rubberband(offset: CGFloat, limit: CGFloat) -> CGFloat {
    // Apple's constant, from the Designing Fluid Interfaces sample code.
    let constant: CGFloat = 0.55
    guard limit > 0 else { return 0 }
    return (offset * limit * constant) / (limit + constant * abs(offset))
}
