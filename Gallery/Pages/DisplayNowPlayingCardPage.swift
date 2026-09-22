import DesignSystem
import SwiftUI

struct DisplayNowPlayingCardPage: View {
    @State private var isPlaying = true
    private let posters = (0..<3).map { SamplePicture.image(seed: $0 + 10) }

    var body: some View {
        StateSection(title: "Playing") {
            DisplayNowPlayingCard(displayName: "Built-in Display", title: "Harbour at Dusk", poster: posters[0]) {
                TransportCluster(isPlaying: true, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(title: "Paused, with a status", note: "The poster is muted, and the status says why: colour is never the only cue.") {
            DisplayNowPlayingCard(
                displayName: "Studio Display",
                title: "Slow Rain",
                poster: posters[1],
                status: "Paused: on battery",
                isActive: false
            ) {
                TransportCluster(isPlaying: false, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(title: "Nothing assigned") {
            DisplayNowPlayingCard(displayName: "LG UltraFine", title: nil)
                .frame(width: Layout.cardWidth)
        }

        StateSection(title: "Long names", note: "Both lines truncate; the controls keep their size.") {
            DisplayNowPlayingCard(
                displayName: "Conference Room Projector (HDMI via Thunderbolt Dock)",
                title: "A wallpaper title far too long to fit beside three buttons",
                poster: posters[2],
                status: "Paused: another app is full screen on this display"
            ) {
                TransportCluster(isPlaying: true, canSkip: false, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(
            title: "In a GlassPopover",
            note: """
            Two cards in the popover they ship in, with 4 pt of padding so the corners are concentric: 20 = 16 + 4, and \
            16 = 8 + 8 for the poster. The panel is the glass; the cards are plain fills. Pause: the card keeps its height.
            """
        ) {
            GlassPopover(contentPadding: Spacing.tight) {
                VStack(spacing: Spacing.tight) {
                    DisplayNowPlayingCard(
                        displayName: "Built-in Display",
                        title: "Harbour at Dusk",
                        poster: posters[0],
                        status: isPlaying ? nil : "Paused",
                        isActive: isPlaying
                    ) {
                        TransportCluster(isPlaying: isPlaying, onPrevious: {}, onPlayPause: { isPlaying.toggle() }, onNext: {})
                    }
                    DisplayNowPlayingCard(displayName: "Studio Display", title: nil)
                }
                .frame(width: Layout.cardWidth)
            }
        }
    }
}

private enum Layout {
    static let cardWidth: CGFloat = 340
}
