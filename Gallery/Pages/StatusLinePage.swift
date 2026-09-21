import DesignSystem
import SwiftUI

struct StatusLinePage: View {
    @State private var step = 0
    @State private var restarts = 0

    private let cycle: [StatusLineStatus] = [
        .idle("42 wallpapers"),
        .working("Importing 1 of 5"),
        .working("Importing 2 of 5"),
        .working("Importing 3 of 5"),
        .serviceNotResponding,
    ]

    var body: some View {
        StateSection(title: "Idle") {
            FakeWindow { StatusLine(status: .idle("42 wallpapers"), onRestart: {}) }
        }
        StateSection(title: "Working", note: "A small spinner and words. Digits are monospaced, so the count does not shift the line.") {
            FakeWindow { StatusLine(status: .working("Importing 2 of 5"), onRestart: {}) }
        }
        StateSection(
            title: "Service not responding",
            note: "A static symbol and words, never colour or motion alone. Restart's hit area is the full height of the line."
        ) {
            FakeWindow { StatusLine(status: .serviceNotResponding, onRestart: { restarts += 1 }) }
            Text("Restarted \(restarts) times")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        StateSection(
            title: "Interactive",
            note: """
            A change of kind crossfades; the count inside “Importing” swaps in place. The line keeps its height throughout. \
            VoiceOver announces the service failing.
            """
        ) {
            FakeWindow { StatusLine(status: cycle[step], onRestart: { step = 0 }) }
            Button("Next status") { step = (step + 1) % cycle.count }
        }
    }
}

/// A window's content with the status line in a bar along its bottom edge.
private struct FakeWindow<Line: View>: View {
    @ViewBuilder let line: Line

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(spacing: 0) {
            Color(nsColor: .windowBackgroundColor)
                .frame(height: 120)
            Divider()
            line
                .padding(.horizontal, Spacing.large)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 1) }
        .frame(maxWidth: 560)
    }
}
