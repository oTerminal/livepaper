import AppKit
import DesignSystem
import LivepaperCore
import SwiftUI

/// What an onboarding card's picture shows. The cards after the first show
/// the wallpaper just set, so the user sees their own wallpaper throughout.
enum OnboardingPicture: Equatable {
    /// The first card: somewhere to drop a file.
    case dropWell
    /// The login card: a login screen over the wallpaper.
    case login(Wallpaper?)
    /// The last card: a desktop showing the wallpaper.
    case desktop(Wallpaper?)
    /// Translocated: Livepaper's icon going into the Applications folder.
    case move
}

/// An onboarding card's picture, drawn to fill the card's 16:10 frame. It is a
/// picture only: the card hides it from VoiceOver, and the words say it all.
struct OnboardingIllustration: View {
    let picture: OnboardingPicture

    var body: some View {
        switch picture {
        case .dropWell: DropWell()
        case .login(let wallpaper): LoginScreen(wallpaper: wallpaper)
        case .desktop(let wallpaper): Desktop(wallpaper: wallpaper)
        case .move: MoveToApplications()
        }
    }
}

/// A dashed well with the import symbol in it, where the drop overlay's border
/// and plate would appear.
private struct DropWell: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.quinary)
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10, 8]))
                .padding(Spacing.extraLarge)
            VStack(spacing: Spacing.small) {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle.weight(.semibold))
                Text("Drop a file here")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// The wallpaper, blurred as the login window blurs it, under an account's
/// picture and a password field.
private struct LoginScreen: View {
    let wallpaper: Wallpaper?

    var body: some View {
        ZStack {
            Poster(wallpaper: wallpaper)
                .blur(radius: 14, opaque: true)
                .overlay(Color.black.opacity(0.2))
            VStack(spacing: Spacing.medium) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 120, height: 22)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
    }
}

/// The wallpaper as a desktop: a menu bar along the top and a Dock at the bottom.
private struct Desktop: View {
    let wallpaper: Wallpaper?

    var body: some View {
        Poster(wallpaper: wallpaper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 12)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: Spacing.tight) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.control / 2, style: .continuous)
                            .fill(.white.opacity(0.7))
                            .frame(width: 18, height: 18)
                    }
                }
                .padding(Spacing.tight + Spacing.hairline)
                .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .padding(.bottom, Spacing.small)
            }
    }
}

/// Livepaper's own icon, an arrow, and the Applications folder's icon, as the
/// Finder draws them.
private struct MoveToApplications: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.quinary)
            HStack(spacing: Spacing.extraLarge) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Image(systemName: "arrow.right")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications"))
                    .resizable()
                    .frame(width: 96, height: 96)
            }
        }
    }
}

/// The wallpaper's poster filling the frame; a drawn picture when there is none yet.
private struct Poster: View {
    let wallpaper: Wallpaper?

    var body: some View {
        if let wallpaper {
            WallpaperPoster(wallpaper)
        } else {
            DrawnPoster(seed: 7)
        }
    }
}
