import SwiftUI

/// A poster in the grid. After the pointer rests on it for 200 ms it shows the
/// live preview the caller hands in; the package never plays video itself.
/// Tiles are content, not the functional layer, so they are never glass.
public struct WallpaperTile<ID: Hashable, LivePreview: View>: View {
    @Environment(LivePreviewCoordinator.self) private var coordinator: LivePreviewCoordinator?
    @Accessibility private var accessibility
    @State private var isHovered = false

    private let id: ID
    private let poster: Image
    private let title: String
    private let isSelected: Bool
    private let isFavourite: Bool
    private let action: () -> Void
    private let livePreview: () -> LivePreview

    public init(
        id: ID,
        poster: Image,
        title: String,
        isSelected: Bool = false,
        isFavourite: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder livePreview: @escaping () -> LivePreview
    ) {
        self.id = id
        self.poster = poster
        self.title = title
        self.isSelected = isSelected
        self.isFavourite = isFavourite
        self.action = action
        self.livePreview = livePreview
    }

    private var isLive: Bool {
        coordinator?.live == AnyHashable(id)
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                picture
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, Spacing.tight)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                coordinator?.pointerEntered(AnyHashable(id))
            } else {
                coordinator?.pointerExited(AnyHashable(id))
            }
        }
        .onDisappear { coordinator?.pointerExited(AnyHashable(id)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isFavourite ? Text("Favourite", bundle: .module) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        return Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                poster
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                if isLive {
                    livePreview()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFavourite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .padding(Spacing.small)
                }
            }
            .clipShape(shape)
            .imageOutline(shape)
            // Selection is state, so it is a border; elevation below is a shadow.
            .overlay {
                RoundedRectangle(cornerRadius: Radius.outer(inner: Radius.tile, padding: SelectionRing.outset), style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: SelectionRing.width)
                    .padding(-SelectionRing.outset)
                    .opacity(isSelected ? 1 : 0)
            }
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 10 : 4, y: isHovered ? 5 : 2)
            .animation(accessibility.animation(Motion.enter(Motion.Duration.hover)), value: isHovered)
            .animation(accessibility.animation(Motion.enter(Motion.Duration.panel)), value: isLive)
    }
}

/// The accent ring around a selected tile: concentric with the tile, one gap out.
private nonisolated enum SelectionRing {
    static let gap: CGFloat = 2
    static let width: CGFloat = 3
    static let outset = gap + width
}
