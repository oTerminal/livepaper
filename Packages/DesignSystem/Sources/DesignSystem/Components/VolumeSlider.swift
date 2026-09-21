import SwiftUI

/// A mute button, a slider and a percent readout. Muting dims the slider but
/// leaves it usable, and moving it unmutes: the user who drags a muted slider
/// wants sound. The symbol and the readout sit in fixed slots so nothing shifts
/// as the level changes.
public struct VolumeSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @Accessibility private var accessibility

    @Binding private var volume: Double
    @Binding private var isMuted: Bool

    public init(volume: Binding<Double>, isMuted: Binding<Bool>) {
        _volume = volume
        _isMuted = isMuted
    }

    public var body: some View {
        HStack(spacing: Spacing.tight) {
            muteButton
            Slider(value: level, in: 0...1) {
                Text("Volume", bundle: .module)
            }
            .labelsHidden()
            .opacity(isMuted ? Metrics.mutedOpacity : 1)
            // The dimming is visual only, so say it.
            .accessibilityValue(isMuted ? Text("Muted, \(percent)", bundle: .module) : Text(percent))
            readout
        }
    }

    private var muteButton: some View {
        Button {
            // Only the click animates the symbol. Waves changing under a dragged
            // slider, and a mute from the keyboard, swap at once.
            withoutAnimationIfKeyPress {
                withAnimation(accessibility.animation(Motion.Spring.ui)) { isMuted.toggle() }
            }
        } label: {
            Image(systemName: Self.symbol(volume: volume, isMuted: isMuted))
                .contentTransition(accessibility.symbolReplace)
                // Leading, so the speaker stays put while the waves come and go.
                .frame(width: Metrics.symbolSlot, alignment: .leading)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        .accessibilityLabel(isMuted ? Text("Unmute", bundle: .module) : Text("Mute", bundle: .module))
    }

    /// As wide as its widest value, so the slider never changes length.
    private var readout: some View {
        Text(1.0, format: Self.percentFormat)
            .hidden()
            .overlay(alignment: .trailing) {
                Text(percent)
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(isEnabled && !isMuted ? .secondary : .tertiary)
            // The slider already carries the value.
            .accessibilityHidden(true)
    }

    private var level: Binding<Double> {
        Binding {
            min(max(volume, 0), 1)
        } set: { newValue in
            volume = newValue
            if isMuted {
                isMuted = false
            }
        }
    }

    private var percent: String {
        min(max(volume, 0), 1).formatted(Self.percentFormat)
    }

    private static var percentFormat: FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0))
    }

    nonisolated static func symbol(volume: Double, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        switch volume {
        case ...0: return "speaker.fill"
        case ..<(1.0 / 3): return "speaker.wave.1.fill"
        case ..<(2.0 / 3): return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

private nonisolated enum Metrics {
    /// Fits `speaker.wave.3.fill`, the widest of the five symbols, at body size.
    static let symbolSlot: CGFloat = 24
    static let mutedOpacity = 0.45
}
