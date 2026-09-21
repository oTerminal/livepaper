import SwiftUI

/// What the status line is saying.
public nonisolated enum StatusLineStatus: Hashable, Sendable {
    /// Nothing happening, such as "42 wallpapers".
    case idle(String)
    /// Work in progress, such as "Importing 2 of 5".
    case working(String)
    /// The wallpaper service has stopped answering. The words are the package's.
    case serviceNotResponding

    fileprivate enum Kind: Hashable {
        case idle, working, serviceNotResponding
    }

    fileprivate var kind: Kind {
        switch self {
        case .idle: .idle
        case .working: .working
        case .serviceNotResponding: .serviceNotResponding
        }
    }
}

/// The single line at the bottom of the window, and the one place a wallpaper
/// service that has stopped responding is reported. The line keeps one height in
/// every status, and only a change of kind crossfades: a count ticking up inside
/// `.working` swaps in place, because it changes many times a second.
public struct StatusLine: View {
    @Accessibility private var accessibility

    private let status: StatusLineStatus
    private let onRestart: () -> Void

    public init(status: StatusLineStatus, onRestart: @escaping () -> Void) {
        self.status = status
        self.onRestart = onRestart
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            content
                .id(status.kind)
                .transition(.opacity)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        // Tall enough for the Restart button's hit area, always, so the window's
        // content never shifts when the service goes away.
        .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitArea, alignment: .leading)
        // One scoped animation: a crossfade, so Reduce Motion leaves it alone and a
        // caller's `withoutAnimation` still silences it.
        .animation(accessibility.fade(Motion.enter(Motion.Duration.hover)), value: status.kind)
        .onChange(of: status.kind) { _, kind in
            guard kind == .serviceNotResponding else { return }
            AccessibilityNotification.Announcement(String(localized: "Wallpaper service not responding.", bundle: .module)).post()
        }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .idle(let text):
            Text(text)
        case .working(let text):
            HStack(spacing: Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(text)
            }
            .accessibilityElement(children: .combine)
        case .serviceNotResponding:
            HStack(spacing: Spacing.small) {
                // A static symbol and words: never colour or motion alone.
                Label {
                    Text("Wallpaper service not responding.", bundle: .module)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel(Text("Warning", bundle: .module))
                }
                .accessibilityElement(children: .combine)
                RestartButton(action: onRestart)
            }
        }
    }
}

/// Looks like a small bordered button; its hit area is the full height of the line.
private struct RestartButton: View {
    @Accessibility private var accessibility
    @State private var isHovered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Restart", bundle: .module)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, Spacing.small + Spacing.hairline)
                .padding(.vertical, Spacing.hairline)
                .background(Color.primary.opacity(isHovered ? 0.14 : 0.08), in: .capsule)
                .contentShape(.focusEffect, .capsule)
                .overlay {
                    if accessibility.increaseContrast {
                        Capsule().strokeBorder(.secondary, lineWidth: 1)
                    }
                }
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        // The one way out of a degraded state never truncates; the message gives way instead.
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(
            accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
            value: isHovered
        )
    }
}
