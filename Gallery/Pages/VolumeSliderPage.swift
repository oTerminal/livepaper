import DesignSystem
import SwiftUI

struct VolumeSliderPage: View {
    var body: some View {
        StateSection(
            title: "Levels",
            note: """
            The symbol follows the level and swaps with a symbol replace. The speaker and the readout sit in fixed slots, \
            so the slider never changes length. Every slider here is live.
            """
        ) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Sample(title: "0%", volume: 0)
                Sample(title: "35%", volume: 0.35)
                Sample(title: "100%", volume: 1)
            }
        }

        StateSection(title: "Muted", note: "Dimmed but usable: drag it and it unmutes.") {
            Sample(title: "Muted", volume: 0.6, isMuted: true)
        }

        StateSection(title: "Disabled") {
            Sample(title: "Disabled", volume: 0.5)
                .disabled(true)
        }
    }
}

private struct Sample: View {
    let title: String
    @State var volume: Double
    @State var isMuted = false

    var body: some View {
        HStack(spacing: Spacing.large) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            VolumeSlider(volume: $volume, isMuted: $isMuted)
                .frame(width: 280)
        }
    }
}
