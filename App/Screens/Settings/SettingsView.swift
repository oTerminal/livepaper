import DesignSystem
import LivepaperCore
import LivepaperTestSupport
import SwiftUI

/// Settings, in two panes: General (opening at login, the pause rules, the Steam
/// account the Workshop uses, leaving Livepaper) and Shortcuts. The pause rules
/// are the app state's; the Steam account is the Workshop model's; the rest talk
/// to `SystemServices` through the model.
struct SettingsView: View {
    enum Pane: String {
        case general
        case shortcuts
    }

    /// The pane shown last opens again, as in System Settings. A launch argument
    /// sets it for one run: `-SettingsPane shortcuts`.
    @AppStorage("SettingsPane") private var pane = Pane.general

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralPane()
            }
            Tab("Shortcuts", systemImage: "keyboard", value: .shortcuts) {
                SettingsPane { ShortcutsSection() }
            }
        }
        .steamSignInSheet(on: .settings)
    }
}

private struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingLeave = false

    var body: some View {
        SettingsPane {
            Section {
                LoginItemRow(state: model.loginItem.loginItemState, appName: "Livepaper") { isOn in
                    model.setOpenAtLogin(isOn)
                } onOpenSystemSettings: {
                    model.openLoginItemsSettings()
                }
            }
            PauseRulesSection()
            SteamAccountSection()
            Section {
                Button("Stop Using Livepaper as Wallpaper…", role: .destructive) {
                    isConfirmingLeave = true
                }
            } footer: {
                Text("Your previous wallpaper comes back, and Livepaper quits. The library is kept.")
            }
        }
        .confirmationDialog("Stop using Livepaper as wallpaper?", isPresented: $isConfirmingLeave) {
            Button("Stop Using Livepaper", role: .destructive) {
                model.leaveLivepaper()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The wallpaper you had before Livepaper is put back, and Livepaper quits. Your library stays where it is.")
        }
    }
}

/// A grouped form as tall as what it holds, so the window fits each pane.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: SettingsMetrics.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The four pause rules, in `CONTEXT.md`'s words, at Core's defaults until changed.
private struct PauseRulesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Every change is refused while the library could not be read, so the rules wait too.
        let canChange = model.libraryProblem == nil
        Section {
            PauseRuleToggle(
                title: "Desktop fully covered",
                detail: "Pause a display’s wallpaper while windows cover the whole of its desktop.",
                systemImage: "macwindow.on.rectangle",
                isOn: rule(\.whenDesktopCovered)
            )
            PauseRuleToggle(
                title: "Display asleep or locked",
                detail: "Pause while a display sleeps, or while the Mac is locked.",
                systemImage: "moon.zzz",
                isOn: rule(\.whenDisplayAsleepOrLocked)
            )
            PauseRuleToggle(
                title: "Low Power Mode",
                detail: "Pause every display while Low Power Mode is on.",
                systemImage: "bolt.circle",
                isOn: rule(\.inLowPowerMode)
            )
            PauseRuleToggle(
                title: "On battery",
                detail: "Pause every display while the Mac is not plugged in.",
                systemImage: "battery.50percent",
                isOn: rule(\.onBattery)
            )
        } header: {
            Text("Pause Rules")
        } footer: {
            if canChange {
                Text("Playback stops under these rules to save energy, and starts again when they no longer apply.")
            } else {
                Text("The library could not be read, so these cannot be changed.")
            }
        }
        .disabled(!canChange)
    }

    /// Switched by a click on the words (animated, as the switch's own is) or by Space on the switch (not).
    private func rule(_ rule: WritableKeyPath<PauseRules, Bool>) -> Binding<Bool> {
        Binding {
            model.pauseRules[keyPath: rule]
        } set: { isOn in
            withoutAnimationIfKeyPress { model.setPauseRule(rule, isOn) }
        }
    }
}

/// A recorder for each hotkey action. They ship unassigned; a combination macOS
/// or another action already has is shown as a conflict, and recording goes on.
private struct ShortcutsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                // On the field's baseline: the recorder's caption line sits below both.
                HStack(alignment: .firstTextBaseline) {
                    Text(action.title)
                    Spacer()
                    HotkeyRecorder(action.title, hotkey: hotkey(for: action)) { hotkey in
                        model.hotkeyOwner(of: KeyCombination(hotkey), for: action)
                    }
                }
            }
        } footer: {
            Text("None is set until you record one. They work in any app.")
        }
    }

    private func hotkey(for action: HotkeyAction) -> Binding<Hotkey?> {
        Binding {
            model.hotkey(for: action)?.hotkey
        } set: { hotkey in
            model.assignHotkey(hotkey.map(KeyCombination.init), to: action)
        }
    }
}

private enum SettingsMetrics {
    /// Room for a rule's detail on two lines, and a recorder beside its action's name.
    static let width: CGFloat = 520
}

#Preview("Settings") {
    SettingsView()
        .environment(AppModel.preview())
        .environment(WorkshopModel.preview())
}

#Preview("Settings, signed in to Steam") {
    SettingsView()
        .environment(AppModel.preview())
        .environment(WorkshopModel.preview(account: "someone"))
}

#Preview("Settings, the login item needing approval") {
    SettingsView()
        .environment(AppModel.preview().previewing { $0.previewLoginItem(.needsApproval) })
        .environment(WorkshopModel.preview())
}

#Preview("Settings, the login item not found") {
    SettingsView()
        .environment(AppModel.preview().previewing { $0.previewLoginItem(.notFound) })
        .environment(WorkshopModel.preview())
}

extension AppModel {
    /// The fakes' login item in a given state, for the previews.
    func previewLoginItem(_ status: LoginItemStatus) {
        (systemServices as? FakeSystemServices)?.loginItem = status
    }
}

#Preview("A shortcut in conflict") {
    // A recorder started in the conflict phase is a picture of it: ⌘Q, which macOS
    // keeps, in the words `hotkeyOwner` gives. The product never starts one so.
    let tried = KeyCombination(keyCode: 12, modifiers: .command, keyLabel: "Q")
    let owner = HotkeyAvailability.takenElsewhere.owner ?? ""
    SettingsPane {
        HStack(alignment: .firstTextBaseline) {
            Text(HotkeyAction.nextWallpaper.title)
            Spacer()
            HotkeyRecorder(
                HotkeyAction.nextWallpaper.title,
                hotkey: .constant(nil),
                phase: .conflict(tried.hotkey, with: owner)
            ) { _ in nil }
        }
    }
}
