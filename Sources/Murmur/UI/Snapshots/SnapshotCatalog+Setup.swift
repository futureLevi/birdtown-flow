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

        var relaunch = micGranted
        relaunch.accessibility = true

        var downloading = relaunch
        downloading.hotkeyActive = true
        downloading.modelState = .downloading(progress: 0.42)

        var shortcut = downloading
        shortcut.fnHasSystemAction = true

        var listening = shortcut
        listening.modelState = .ready
        listening.phase = .listening

        var done = listening
        done.phase = .idle
        done.practiceSucceeded = true
        done.practiceText = "Murmur is my new favourite way to write."

        return [
            shot("1-welcome", .welcome, fresh),
            shot("2-microphone", .microphone, fresh),
            shot("2-microphone-granted", .microphone, micGranted),
            shot("2-microphone-denied", .microphone, micDenied),
            shot("3-accessibility", .accessibility, micGranted),
            shot("3-accessibility-relaunch", .accessibility, relaunch),
            shot("4-model-downloading", .model, downloading),
            shot("5-shortcut", .shortcut, shortcut),
            shot("6-practice-listening", .practice, listening),
            shot("6-practice-done", .practice, done),
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

        return [
            shot("general", height: 560, model: general, facts: SetupPreview()) { GeneralSettingsPane() },
            shot("audio", height: 640, model: audio, facts: audioFacts) { AudioSettingsPane() },
            shot("text", height: 820, model: text, facts: textFacts) { TextSettingsPane() },
            shot("privacy", height: 560, model: general, facts: SetupPreview()) { PrivacySettingsPane() },
            shot("about", height: 520, model: general, facts: SetupPreview()) { AboutSettingsPane() },
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
        func shot(_ name: String, _ facts: SetupPreview) -> SnapshotRenderer.Shot {
            SnapshotRenderer.Shot("setup-menubar-\(name)", size: size) {
                MenuBarContent()
                    .environment(model)
                    .environment(\.setupPreview, facts)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.canvas)
            }
        }
        return [
            shot("ready", SetupPreview()),
            shot("downloading", downloading),
            shot("listening", listening),
        ]
    }
}

extension AppModel {
    /// An in-memory model for snapshots: throwaway defaults, sample history, no files touched.
    static func setupPreview(_ configure: (Settings) -> Void = { _ in }) -> AppModel {
        let suite = "murmur.snapshots.setup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = Settings(defaults: defaults)
        configure(settings)
        return AppModel(
            settings: settings,
            history: HistoryStore(previewRecords: setupSampleHistory),
            snippets: SnippetStore(preview: [])
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
