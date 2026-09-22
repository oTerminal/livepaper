import DesignSystem
import SwiftUI

struct OnboardingCardPage: View {
    @State private var replay = 0
    @State private var step = 0

    private let steps: [(title: String, message: String)] = [
        ("Welcome to Livepaper", "Put a video on your desktop. It pauses by itself when you would not see it."),
        ("Choose a video", "Drop any video into the library, or pick one from your Mac."),
        ("Save your battery", "Wallpapers pause on battery, in Low Power Mode and when a window covers the desktop."),
        ("You are set", "Livepaper lives in the menu bar. Open it there at any time."),
    ]

    var body: some View {
        StateSection(
            title: "Step 1 of 4",
            note: """
            Illustration, text and buttons enter 0.10 s apart, once. With Reduce Motion: opacity only, together. \
            Try 0.1x, then Replay.
            """
        ) {
            VStack(alignment: .leading, spacing: Spacing.large) {
                OnboardingCard(
                    title: steps[0].title,
                    message: steps[0].message,
                    stepIndex: 0,
                    stepCount: steps.count,
                    primaryTitle: "Continue",
                    onPrimary: {},
                    secondaryTitle: "Skip",
                    onSecondary: {},
                    illustration: { SamplePicture(seed: 3) }
                )
                .id(replay)
                Button("Replay entrance") { replay += 1 }
            }
        }

        StateSection(
            title: "Stepping through",
            note: """
            The card keeps its identity, so moving between steps re-enters nothing. A click crossfades the picture, \
            words and dots and the height snaps; Return presses Continue with no animation.
            """
        ) {
            OnboardingCard(
                title: steps[step].title,
                message: steps[step].message,
                stepIndex: step,
                stepCount: steps.count,
                primaryTitle: step == steps.count - 1 ? "Done" : "Continue",
                onPrimary: { step = (step + 1) % steps.count },
                secondaryTitle: step == 0 ? nil : "Back",
                onSecondary: { step = max(step - 1, 0) },
                illustration: { SamplePicture(seed: 10 + step) }
            )
        }

        StateSection(title: "Last step", note: "“Done”, and no secondary button.") {
            OnboardingCard(
                title: steps[3].title,
                message: steps[3].message,
                stepIndex: 3,
                stepCount: steps.count,
                primaryTitle: "Done",
                onPrimary: {},
                illustration: { SamplePicture(seed: 5) }
            )
        }

        StateSection(title: "Long text") {
            OnboardingCard(
                title: "Let Livepaper open when you log in, so your wallpaper is there before you are",
                message: """
                Livepaper can open by itself when you log in. macOS will ask you to allow this in System Settings the first \
                time. You can change your mind later in Settings, under General, and nothing else about the app changes.
                """,
                stepIndex: 1,
                stepCount: steps.count,
                primaryTitle: "Open at Login",
                onPrimary: {},
                secondaryTitle: "Not Now",
                onSecondary: {},
                illustration: { SamplePicture(seed: 8) }
            )
        }
    }
}
