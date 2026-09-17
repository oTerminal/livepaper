import DesignSystem
import SwiftUI

/// Shows every design-system component in isolation, in every state, for review.
/// Components arrive in M3 (docs/roadmap.md).
@main
struct GalleryApp: App {
    var body: some Scene {
        WindowGroup("Livepaper Gallery") {
            ContentUnavailableView(
                "No components yet",
                systemImage: "square.on.square.dashed",
                description: Text("Design-system components appear here as they are built.")
            )
            .frame(minWidth: 640, minHeight: 420)
        }
    }
}
