import AppKit
import Foundation
import MurmurKit
import SwiftUI

// Owned by the ui-setup agent: onboarding steps, settings tabs, menu bar window.
extension SnapshotCatalog {
    static var setup: [SnapshotRenderer.Shot] {
        onboardingShots + settingsShots + menuBarShots
    }

    private static var onboardingShots: [SnapshotRenderer.Shot] {
        let model = AppModel.setupPreview()
        func shot(_ name: String, _ step: OnboardingStep, _ facts: SetupPreview) -> SnapshotRenderer.Shot {
            SnapshotRenderer.Shot("setup-onboarding-\(name)", size: Layout.onboardingSize) {
                OnboardingView(initialStep: step)
                    .environment(model)
                    .environment(\.setupPreview, facts)
            }
        }
        var fresh = SetupPreview()
        fresh.microphone = .notDetermined
        fresh.accessibility = false
        fresh.hotkeyActive = false
        fresh.modelState = .notDownloaded

        var micGranted = fresh
        micGranted.microphone = .granted

        var micDenied = fresh
        micDenied.microphone = .denied

        var micDeniedWaiting = micDenied
        micDeniedWaiting.openedSettings = true

        var accessibilityWaiting = micGranted
        accessibilityWaiting.openedSettings = true

        var relaunch = micGranted
        relaunch.accessibility = true

        // What customers get from the app bundle: Relaunch and Later.
        var relaunchBundled = relaunch
        relaunchBundled.canRelaunch = true

        var downloading = relaunch
        downloading.hotkeyActive = true
        downloading.modelState = .downloading(progress: 0.42)

        var modelFailed = downloading
        modelFailed.modelState = .failed("The Internet connection appears to be offline.")

        var shortcut = downloading
        shortcut.fnHasSystemAction = true

        // Both warnings at once: Wispr Flow listens on fn too.
        var shortcutWispr = shortcut
        shortcutWispr.wisprRunning = true

        // Trying before the download finishes: Apple Speech stands in, so the try isn't held up.
        let practiceWaiting = shortcut
        var practiceFailed = shortcut
        practiceFailed.phase = .failed(DictationFeedback.noWordsMessage(audioSaved: true))

        var listening = shortcut
        listening.modelState = .ready
        listening.phase = .listening

        var done = listening
        done.phase = .idle
        done.practiceSucceeded = true
        done.practiceText = "Birdtown Flow is my new favourite way to write."

        // The try worked while Parakeet was still downloading: Apple Speech wrote it.
        var doneStandIn = done
        doneStandIn.modelState = .downloading(progress: 0.42)
        doneStandIn.practiceEngine = "Apple Speech"

        return [
            shot("1-welcome", .welcome, fresh),
            shot("2-microphone", .microphone, fresh),
            shot("2-microphone-granted", .microphone, micGranted),
            shot("2-microphone-denied", .microphone, micDenied),
            shot("2-microphone-denied-waiting", .microphone, micDeniedWaiting),
            shot("3-accessibility", .accessibility, micGranted),
            shot("3-accessibility-waiting", .accessibility, accessibilityWaiting),
            shot("3-accessibility-relaunch", .accessibility, relaunch),
            shot("3-accessibility-relaunch-bundled", .accessibility, relaunchBundled),
            shot("4-model-downloading", .model, downloading),
            shot("4-model-failed", .model, modelFailed),
            shot("5-shortcut", .shortcut, shortcut),
            shot("5-shortcut-wispr", .shortcut, shortcutWispr),
            shot("6-practice-model-downloading", .practice, practiceWaiting),
            shot("6-practice-failed", .practice, practiceFailed),
            shot("6-practice-listening", .practice, listening),
            shot("6-practice-done", .practice, done),
            shot("6-practice-done-stand-in", .practice, doneStandIn),
        ]
    }

    private static var settingsShots: [SnapshotRenderer.Shot] {
        func shot<V: View>(_ name: String, height: CGFloat, model: AppModel, facts: SetupPreview, @ViewBuilder _ view: () -> V) -> SnapshotRenderer.Shot {
            let pane = view()
            return SnapshotRenderer.Shot("setup-settings-\(name)", size: CGSize(width: Layout.settingsWidth, height: height)) {
                pane
                    .environment(model)
                    .environment(\.setupPreview, facts)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.canvas)
            }
        }
        let general = AppModel.setupPreview()
        let audio = AppModel.setupPreview()
        var audioFacts = SetupPreview()
        audioFacts.modelState = .downloading(progress: 0.42)
        audioFacts.downloaded = [.parakeetV2, .apple]
        let text = AppModel.setupPreview { $0.polishProvider = .anthropic }
        var textFacts = SetupPreview()
        textFacts.keySaved = true
        let claudeCode = AppModel.setupPreview { $0.polishProvider = .claudeCode }

        return [
            shot("general", height: Layout.Setup.settingsHeight, model: general, facts: SetupPreview()) { GeneralSettingsPane() },
            shot("audio", height: Layout.Setup.settingsHeight, model: audio, facts: audioFacts) { AudioSettingsPane() },
            shot("text", height: Layout.Setup.settingsHeight, model: text, facts: textFacts) { TextSettingsPane() },
            // Taller than the window, to show the provider's settings below the cards.
            shot("text-claude-code", height: Layout.Setup.settingsHeight + 360, model: claudeCode, facts: textFacts) {
                TextSettingsPane()
            },
            shot("privacy", height: Layout.Setup.settingsHeight, model: general, facts: SetupPreview()) { PrivacySettingsPane() },
            shot("about", height: Layout.Setup.settingsHeight, model: general, facts: SetupPreview()) { AboutSettingsPane() },
        ]
    }

    private static var menuBarShots: [SnapshotRenderer.Shot] {
        // Taller than the brief's 420 pt: with two-line recent dictations the real window
        // sizes to about 470 pt, and a clipped snapshot would hide the bottom rows.
        let size = CGSize(width: Layout.Setup.menuBarWidth, height: 480)
        let model = AppModel.setupPreview { $0.hasCompletedOnboarding = true }
        var listening = SetupPreview()
        listening.phase = .listening
        var downloading = SetupPreview()
        downloading.modelState = .downloading(progress: 0.42)
        var transcribing = SetupPreview()
        transcribing.phase = .transcribing
        // Setup not finished: shows the "Finish Setup…" call to action.
        let unfinished = AppModel.setupPreview()
        func shot(_ name: String, _ facts: SetupPreview, model: AppModel) -> SnapshotRenderer.Shot {
            SnapshotRenderer.Shot("setup-menubar-\(name)", size: size) {
                MenuBarContent()
                    .environment(model)
                    .environment(\.setupPreview, facts)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.canvas)
            }
        }
        return [
            shot("ready", SetupPreview(), model: model),
            shot("downloading", downloading, model: model),
            shot("listening", listening, model: model),
            shot("transcribing", transcribing, model: model),
            shot("finish-setup", SetupPreview(), model: unfinished),
            SnapshotRenderer.Shot("setup-menubar-icon", size: CGSize(width: Layout.Setup.menuBarWidth, height: 120)) {
                MenuBarIconSheet()
            },
        ]
    }
}

/// The menu bar icon, idle and listening, at its real size and magnified, so the tiny
/// spectrum disc can be judged in review.
private struct MenuBarIconSheet: View {
    /// Magnification for the enlarged pair. Review-only, never shipped UI.
    private let magnified: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xxl) {
            glyph(MenuBarGlyph.idle, scale: 1)
            glyph(MenuBarGlyph.active, scale: 1)
            glyph(MenuBarGlyph.idle, scale: magnified)
            glyph(MenuBarGlyph.active, scale: magnified)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }

    private func glyph(_ image: NSImage, scale: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .foregroundStyle(Palette.ink)
    }
}

extension AppModel {
    /// An in-memory model for snapshots: throwaway defaults, sample history, no files touched.
    static func setupPreview(_ configure: (Settings) -> Void = { _ in }) -> AppModel {
        let suite = "birdtownflow.snapshots.setup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = Settings(defaults: defaults)
        configure(settings)
        return AppModel(
            settings: settings,
            history: HistoryStore(previewRecords: setupSampleHistory),
            snippets: SnippetStore(preview: []),
            lab: PolishLabStore(preview: PolishLabState(configurations: PolishConfiguration.starters()))
        )
    }

    private static var setupSampleHistory: [HistoryRecord] {
        let now = Date()
        func record(_ minutesAgo: Double, _ app: String, _ category: AppCategory, _ text: String) -> HistoryRecord {
            HistoryRecord(
                createdAt: now.addingTimeInterval(-minutesAgo * 60),
                context: AppContext(bundleID: nil, appName: app, category: category),
                engine: "Parakeet Ultra",
                rawText: text,
                finalText: text,
                audioDuration: 6,
                outcome: .inserted
            )
        }
        return [
            record(2, "Slack", .work, "Sounds good. Let's ship the onboarding tonight and look at the snapshots together tomorrow."),
            record(14, "Mail", .email, "Hi Sam, thanks for the notes. I've attached the revised timeline and moved the review to Thursday."),
            record(52, "Notes", .other, "Ideas for the weekend: farmers market, finish the bookshelf, call Mum."),
            record(90, "Messages", .personal, "On my way, ten minutes out."),
        ]
    }
}
