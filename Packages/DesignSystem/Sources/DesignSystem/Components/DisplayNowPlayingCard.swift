import SwiftUI

/// What one display is showing, in the menu-bar popover, with the caller's
/// controls on the trailing side. The popover is already glass, so the card is
/// a plain fill: glass here would be glass on glass.
public struct DisplayNowPlayingCard<Accessory: View>: View {
    @Accessibility private var accessibility

    private let displayName: String
    private let title: String?
    private let poster: Image?
    private let status: String?
    private let isActive: Bool
    private let accessory: Accessory

    /// - Parameters:
    ///   - title: `nil` when nothing is assigned to the display.
    ///   - status: Why the display is not playing, such as "Paused: on battery".
    ///   - isActive: Whether the wallpaper is playing. An inactive poster is muted.
    public init(
        displayName: String,
        title: String?,
        poster: Image? = nil,
        status: String? = nil,
        isActive: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.displayName = displayName
        self.title = title
        self.poster = poster
        self.status = status
        self.isActive = isActive
        self.accessory = accessory()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        HStack(spacing: Spacing.medium) {
            HStack(spacing: Spacing.medium) {
                thumbnail
                text
            }
            .accessibilityElement(children: .ignore)
            // Display first, then the wallpaper and status, as one label: VoiceOver
            // speaks a value before the label, which would put the display last.
            .accessibilityLabel(Text(verbatim: "\(displayName), \(spokenValue)"))

            Spacer(minLength: 0)
            accessory
                .fixedSize()
        }
        .padding(Spacing.small)
        .background(.quaternary.opacity(Metrics.fillOpacity), in: shape)
        .containerShape(shape)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let title {
                Text(title)
                    .font(.callout.weight(.medium))
            } else {
                Text("No wallpaper", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // Always laid out, so the card keeps its height when a status comes
            // and goes: pausing must not move the button under the pointer.
            Text(status ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(status == nil ? 0 : 1)
        }
        .lineLimit(1)
    }

    private var thumbnail: some View {
        // Takes its radius from the card's container shape, less the padding between them.
        let shape = ConcentricRectangle(corners: .concentric, isUniform: true)
        return Color.clear
            .frame(width: Metrics.thumbnailSize.width, height: Metrics.thumbnailSize.height)
            .overlay {
                if let poster, title != nil {
                    poster
                        .resizable()
                        .scaledToFill()
                        .saturation(isActive ? 1 : Metrics.inactiveSaturation)
                        .opacity(isActive ? 1 : Metrics.inactiveOpacity)
                        .animation(accessibility.fade(Motion.Spring.ui), value: isActive)
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "photo")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(shape)
            .imageOutline(shape)
    }

    private var spokenValue: String {
        [title ?? String(localized: "No wallpaper", bundle: .module), status]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

extension DisplayNowPlayingCard where Accessory == EmptyView {
    /// A card with no controls.
    public init(displayName: String, title: String?, poster: Image? = nil, status: String? = nil, isActive: Bool = true) {
        self.init(displayName: displayName, title: title, poster: poster, status: status, isActive: isActive) { EmptyView() }
    }
}

private nonisolated enum Metrics {
    /// 16:10, as tall as the accessory's hit area so the row has one height.
    static let thumbnailSize = CGSize(width: 64, height: Spacing.minimumHitArea)
    static let fillOpacity = 0.6
    static let inactiveSaturation = 0.3
    static let inactiveOpacity = 0.7
}
