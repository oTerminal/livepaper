import DesignSystem
import LivepaperCore
import SwiftUI

/// The popover's last rows: Mute and Pause All, which act on every display, the
/// ways into the library and Settings, and the status line under them.
struct PopoverFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(AppWindows.self) private var windows

    var body: some View {
        // Nothing can be saved while the library could not be read, and a Pause
        // All could not be resumed: both wait until it can.
        let canChange = model.libraryProblem == nil
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                mute
                    .disabled(!canChange)
                pauseAll
                    .disabled(!canChange)
                // Pause All and Resume All differ in width; the buttons after the gap stay put.
                Spacer(minLength: Spacing.small)
                FooterIconButton(title: "Open Library", systemImage: "square.grid.2x2") { windows.openLibrary() }
                FooterIconButton(title: "Settings", systemImage: "gearshape") { windows.openSettings() }
            }
            StatusLine(status: model.statusLine.statusLineStatus) { model.restartWallpaperService() }
                .padding(.horizontal, Spacing.small)
        }
    }

    /// A toggle: its words stay "Mute"; the slashed speaker and a fill behind it
    /// say it is on. Not the accent: the popover never makes the app active, so
    /// the accent would draw grey, and read as disabled.
    private var mute: some View {
        Button {
            withoutAnimationIfKeyPress { model.toggleMute() }
        } label: {
            FooterLabel(title: "Mute", systemImage: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isOn: model.isMuted)
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(model.isMuted ? "On" : "Off")
        .help(model.isMuted ? "Every display is muted" : "Mute every display")
    }

    private var pauseAll: some View {
        Button {
            withoutAnimationIfKeyPress { model.togglePauseAll() }
        } label: {
            if model.isPausedAll {
                FooterLabel(title: "Resume All", systemImage: "play.fill")
            } else {
                FooterLabel(title: "Pause All", systemImage: "pause.fill")
            }
        }
        .buttonStyle(.press)
        .help(model.isPausedAll ? "Play every display again" : "Pause every display")
    }
}

/// A symbol and words with a 40 pt target. The symbol has a fixed slot, so the
/// words do not move when it changes. On, a capsule of `primary` fills behind
/// them, as the fit mode picker's pill does; it never animates.
private struct FooterLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isOn = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: FooterMetrics.symbolSlot)
        }
        .font(.callout)
        // The symbol's side sits 2 pt closer to the edge than the words' side.
        .padding(.leading, Spacing.small - Spacing.hairline)
        .padding(.trailing, Spacing.small)
        .padding(.vertical, Spacing.tight)
        .background(.primary.opacity(isOn ? FooterMetrics.onFillOpacity : 0), in: .capsule)
        .frame(minHeight: Spacing.minimumHitArea)
        .contentShape(.rect)
    }
}

/// A symbol alone in a 40 pt square, its words the tooltip and the VoiceOver label.
private struct FooterIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            withoutAnimationIfKeyPress(action)
        } label: {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: Spacing.minimumHitArea, height: Spacing.minimumHitArea)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

private enum FooterMetrics {
    /// Fits the widest of the footer's symbols, the speaker with its waves.
    static let symbolSlot: CGFloat = 20
    /// The fit mode picker's selection pill.
    static let onFillOpacity = 0.14
}
