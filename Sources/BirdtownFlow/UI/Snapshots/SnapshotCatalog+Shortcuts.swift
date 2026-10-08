import AppKit
import Foundation
import MurmurKit
import SwiftUI

// Owned by the custom-shortcuts work: recorded shortcuts in Settings and onboarding.
extension SnapshotCatalog {
    static var shortcuts: [SnapshotRenderer.Shot] {
        let chordPushToTalk = KeyShortcut.keys(KeyChord(keyCode: KeyCode.d, modifiers: [.control, .option]))
        let custom = AppModel.setupPreview { settings in
            settings.pushToTalkKey = chordPushToTalk
            settings.handsFreeChord = KeyChord(keyCode: KeyCode.space, modifiers: [.control, .shift])
            settings.handsFreeShortcut = .controlOption
            settings.pasteLastShortcut = KeyChord(keyCode: KeyCode.p, modifiers: [.control, .option])
        }
        let standard = AppModel.setupPreview()

        func settingsShot(_ name: String, model: AppModel, pane: GeneralSettingsPane) -> SnapshotRenderer.Shot {
            SnapshotRenderer.Shot(
                "setup-settings-\(name)",
                size: CGSize(width: Layout.settingsWidth, height: Layout.Setup.settingsHeight)
            ) {
                pane
                    .environment(model)
                    .environment(\.setupPreview, SetupPreview())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.canvas)
            }
        }

        // The rules' own words, so the snapshot shows exactly what users read.
        let spotlight = ShortcutRules.check(
            .keys(KeyChord(keyCode: KeyCode.space, modifiers: [.command])),
            for: .pushToTalk,
            inUse: standard.settings.shortcutsInUse
        )
        let duplicate = ShortcutRules.check(
            .keys(.pasteLastDefault),
            for: .handsFree,
            inUse: standard.settings.shortcutsInUse
        )
        let leftCommand = ShortcutRules.check(.modifier(.leftCommand), for: .pushToTalk)

        var onboardingFacts = SetupPreview()
        onboardingFacts.modelState = .downloading(progress: 0.42)

        return [
            // Recorded shortcuts for all three actions; paste-last offers its reset.
            settingsShot("general-custom-shortcuts", model: custom, pane: GeneralSettingsPane()),
            // Listening for hands-free, ⌃⇧ held so far.
            settingsShot(
                "general-recording-shortcut",
                model: standard,
                pane: GeneralSettingsPane(previewRecording: (role: .handsFree, held: ["⌃", "⇧"]))
            ),
            // A refused system shortcut and a duplicate, each explained under its row.
            settingsShot(
                "general-shortcut-refused",
                model: standard,
                pane: GeneralSettingsPane(shortcutNotices: [.pushToTalk: spotlight, .handsFree: duplicate])
            ),
            settingsShot(
                "general-shortcut-caution",
                model: AppModel.setupPreview { $0.pushToTalkKey = .modifier(.leftCommand) },
                pane: GeneralSettingsPane(shortcutNotices: [.pushToTalk: leftCommand])
            ),
            // Onboarding with a recorded chord: none of the four tiles is selected, so the
            // chord shows below them.
            SnapshotRenderer.Shot("setup-onboarding-5-shortcut-custom", size: Layout.onboardingSize) {
                OnboardingView(initialStep: .shortcut)
                    .environment(custom)
                    .environment(\.setupPreview, onboardingFacts)
            },
        ]
    }
}
