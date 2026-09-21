import SwiftUI

struct GalleryPage: Identifiable {
    let title: String
    let systemImage: String
    let content: () -> AnyView

    var id: String { title }

    init(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> some View) {
        self.title = title
        self.systemImage = systemImage
        self.content = { AnyView(content()) }
    }

    /// One page per component, in the order of docs/specs/M3-design-system.md.
    static let all: [GalleryPage] = [
        GalleryPage("WallpaperTile", systemImage: "photo.on.rectangle") { WallpaperTilePage() },
    ]
}
