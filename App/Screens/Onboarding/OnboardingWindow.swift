import AppKit
import DesignSystem
import LivepaperCore
import LivepaperSystem
import SwiftUI

/// Onboarding's window (M7): one `OnboardingCard` whose values follow the step,
/// so moving on crossfades the picture and the words and nothing re-enters. The
/// whole window takes a drop on the first card. It closes when the cards end,
/// and closing it ends them.
struct OnboardingWindow: View {
    @Environment(Onboarding.self) private var onboarding
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isDropTargeted: Bool

    /// A preview can show it under a drop.
    init(isDropTargeted: Bool = false) {
        _isDropTargeted = State(initialValue: isDropTargeted)
    }

    var body: some View {
        let page = OnboardingPage(onboarding)
        OnboardingCard(
            title: page.title,
            message: page.message,
            stepIndex: onboarding.stepIndex,
            stepCount: max(onboarding.steps.count, 1),
            primaryTitle: page.primary.title,
            onPrimary: page.primary.run,
            secondaryTitle: page.secondary?.title,
            onSecondary: page.secondary?.run
        ) {
            OnboardingIllustration(picture: page.picture)
        } accessory: {
            if page.offersSamples {
                SampleTiles()
            }
        }
        // While an import or the selection runs, nothing on the card can start another.
        .disabled(page.isBusy)
        .padding(Spacing.section)
        .fixedSize()
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard onboarding.takesDrops, !files.isEmpty else { return false }
            onboarding.addWallpaper(from: files)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .dropZoneOverlay(
            isTargeted: isDropTargeted && onboarding.takesDrops,
            title: "Drop to Import",
            message: "It becomes your wallpaper, on every display."
        )
        .onChange(of: onboarding.hasEnded) { _, hasEnded in
            if hasEnded { dismissWindow(id: AppWindows.onboardingID) }
        }
        .onDisappear { onboarding.windowClosed() }
    }
}

/// What the card says and offers, from where onboarding has got to. The words
/// follow `DECISIONS.md`: sentence case for the title, title case for buttons.
struct OnboardingPage {
    struct Action {
        let title: String
        let run: () -> Void
    }

    var title: String
    var message: String
    var primary: Action
    var secondary: Action?
    var picture: OnboardingPicture
    var offersSamples = false
    var isBusy = false

    init(_ onboarding: Onboarding) {
        switch onboarding.plan {
        case .moveToApplications:
            self.init(moving: onboarding)
        case .steps, .nothing:
            switch onboarding.step {
            case .addWallpaper: self.init(adding: onboarding)
            case .openAtLogin: self.init(login: onboarding)
            case .selectLivepaper, nil: self.init(selecting: onboarding)
            }
        }
    }

    private init(title: String, message: String, primary: Action, secondary: Action? = nil, picture: OnboardingPicture) {
        self.title = title
        self.message = message
        self.primary = primary
        self.secondary = secondary
        self.picture = picture
    }

    // MARK: Translocated

    private init(moving onboarding: Onboarding) {
        self.init(
            title: "Move Livepaper to Applications",
            message: "Livepaper is running from where it was downloaded, so it cannot open at login or become your wallpaper. "
                + "Quit it, drag it into the Applications folder, and open it from there.",
            primary: Action(title: "Quit Livepaper") {
                onboarding.end()
                NSApp.terminate(nil)
            },
            secondary: Action(title: "Show Applications Folder") { onboarding.showApplicationsFolder() },
            picture: .move
        )
    }

    // MARK: 1, a wallpaper

    private init(adding onboarding: Onboarding) {
        let hasSamples = !onboarding.samples.isEmpty
        let choosing = hasSamples
            ? "Drop a file on this card, or start with one of these. It plays on every display."
            : "Drop a file on this card, or choose one. It plays on every display."
        let again = hasSamples ? "Drop another file, choose one, or start with one of these." : "Drop another file, or choose one."
        let message = switch onboarding.firstWallpaper {
        case .choosing, .set: choosing
        // As long as the words it replaces, so that the card keeps its height while the import runs.
        case .importing(let name, let words): "Importing “\(name)”: \(words ?? "Checking")… Once it is in, it plays on every display."
        case .failed(let why): "\(why) \(again)"
        }
        self.init(
            title: "Add a wallpaper",
            message: message,
            primary: Action(title: "Choose File…") { onboarding.chooseFile() },
            picture: .dropWell
        )
        offersSamples = hasSamples
        if case .importing = onboarding.firstWallpaper { isBusy = true }
    }

    // MARK: 2, the login item

    private init(login onboarding: Onboarding) {
        let next = Action(title: "Continue") { onboarding.next() }
        let picture = OnboardingPicture.login(onboarding.wallpaper)
        switch onboarding.loginPhase {
        case .asking:
            self.init(
                title: "Open at login",
                message: "Livepaper can open when you log in, so your wallpaper is there from the start.",
                primary: Action(title: "Open at Login") { onboarding.turnOnOpenAtLogin() },
                secondary: Action(title: "Not Now") { onboarding.next() },
                picture: picture
            )
        case .alreadyOn, .turnedOn:
            self.init(title: "Open at login", message: "Livepaper opens when you log in.", primary: next, picture: picture)
        case .needsApproval:
            self.init(
                title: "Open at login",
                message: "Allow Livepaper in System Settings, under Login Items, to finish turning this on.",
                primary: Action(title: "Open System Settings…") { onboarding.openLoginItems() },
                secondary: next,
                picture: picture
            )
        case .notFound:
            self.init(
                title: "Open at login",
                message: "Login item not found. Move Livepaper to the Applications folder, then turn this on in Settings.",
                primary: next,
                picture: picture
            )
        case .notRegistered:
            self.init(
                title: "Open at login",
                message: "Livepaper could not be added to your login items. You can try again in Settings.",
                primary: next,
                picture: picture
            )
        }
    }

    // MARK: 3, Livepaper as the wallpaper

    private init(selecting onboarding: Onboarding) {
        let picture = OnboardingPicture.desktop(onboarding.wallpaper)
        let done = Action(title: "Done") { onboarding.end() }
        let notNow = Action(title: "Not Now") { onboarding.end() }
        let outcome = onboarding.selection
        switch outcome {
        case .idle, .left, .chooseAnotherInPane, .failed(_, leaving: true):
            self.init(
                title: "Make Livepaper your wallpaper",
                message: "Livepaper becomes the wallpaper in System Settings, on every display and Space.",
                primary: Action(title: "Set as Wallpaper") { onboarding.selectLivepaper() },
                secondary: notNow,
                picture: picture
            )
        case .working:
            self.init(
                title: "Make Livepaper your wallpaper",
                message: "Making Livepaper the wallpaper on every display and Space. This takes a moment…",
                primary: Action(title: "Set as Wallpaper") {},
                secondary: notNow,
                picture: picture
            )
            isBusy = true
        case .selected:
            self.init(
                title: "Livepaper is your wallpaper",
                message: "It lives in the menu bar: open it there to change wallpapers, pause them, or import more.",
                primary: done,
                picture: picture
            )
        case .chooseInPane, .failed(_, leaving: false):
            self.init(
                title: "Make Livepaper your wallpaper",
                message: (outcome.words ?? "") + " This card finishes when you have.",
                primary: Action(title: "Open Wallpaper Settings") { onboarding.openWallpaperPane() },
                secondary: notNow,
                picture: picture
            )
        }
    }
}

/// The first card's samples, as tiles like the library's: each plays when the
/// pointer rests on it, and a click imports it and sets it on every display.
struct SampleTiles: View {
    @Environment(Onboarding.self) private var onboarding

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            ForEach(onboarding.samples) { sample in
                WallpaperTile(
                    id: sample.id,
                    poster: onboarding.samplePosters[sample.id].map { Image(decorative: $0, scale: 2) } ?? .posterLoading,
                    title: sample.title,
                    isSelected: isImporting(sample)
                ) {
                    onboarding.pickSample(sample)
                } livePreview: {
                    // Clear: the poster shows until the first frame is up.
                    PreviewPlayerView(url: sample.url, presentation: Presentation(), backgroundColor: .clear)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .livePreviewScope()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Samples")
        .onAppear { onboarding.loadSamplePosters() }
    }

    private func isImporting(_ sample: SampleWallpaper) -> Bool {
        if case .importing(let name, _) = onboarding.firstWallpaper { return name == sample.title }
        return false
    }
}

// MARK: Previews

#Preview("Add a wallpaper") {
    OnboardingPreview(.fresh)
}

#Preview("Add a wallpaper, under a drop") {
    OnboardingPreview(.fresh, isDropTargeted: true)
}

#Preview("Open at login") {
    OnboardingPreview(.fresh) { onboarding, _ in onboarding.next() }
}

#Preview("Open at login, needing approval") {
    OnboardingPreview(.fresh) { onboarding, fakes in
        onboarding.next()
        fakes.systemServices.answerToTurningOn = .needsApproval
        onboarding.turnOnOpenAtLogin()
    }
}

#Preview("Make Livepaper your wallpaper") {
    OnboardingPreview(.fresh) { onboarding, _ in
        onboarding.next()
        onboarding.next()
    }
}

#Preview("Make Livepaper your wallpaper, in System Settings") {
    OnboardingPreview(.fresh) { onboarding, fakes in
        onboarding.next()
        onboarding.next()
        fakes.selectionWorld.store.isReadable = false
        onboarding.selectLivepaper()
    }
}

#Preview("After leaving") {
    OnboardingPreview(.afterLeaving)
}

#Preview("Translocated") {
    OnboardingPreview(.translocated)
}

/// Onboarding's window on the fakes, as a scenario of `-onboarding` starts it.
private struct OnboardingPreview: View {
    let onboarding: Onboarding
    let model: AppModel
    var isDropTargeted = false

    init(_ scenario: FakeOnboarding, isDropTargeted: Bool = false, _ change: (Onboarding, Fakes) -> Void = { _, _ in }) {
        let fakes = Fakes(library: .seeded, onboarding: scenario)
        model = AppModel(services: fakes.makeServices())
        model.prepareForPreview(displays: fakes.connectedDisplays, hostStatus: .notSelected)
        onboarding = Onboarding(model: model)
        self.isDropTargeted = isDropTargeted
        change(onboarding, fakes)
    }

    var body: some View {
        OnboardingWindow(isDropTargeted: isDropTargeted)
            .environment(onboarding)
            .environment(model)
    }
}
