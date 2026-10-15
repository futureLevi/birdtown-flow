import AppKit
import MurmurKit
import SwiftUI

/// Settings › About › Send feedback: where notes said with the feedback shortcut go (a private
/// GitHub repository and a token), and what's still waiting to be sent.
struct FeedbackSettingsGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.setupPreview) private var preview
    @State private var tokenDraft = ""
    @State private var tokenSaved = false
    @State private var sending = false

    var body: some View {
        @Bindable var settings = model.settings
        let feedback = model.feedback
        SettingsGroup(
            title: "Send feedback",
            footnote: "Press \(settings.feedbackShortcut.displayName) anywhere, say what to fix, and press it again. Nothing is typed: the note, the app you were in and your last few dictations go to the repository above as a GitHub issue."
        ) {
            SettingsRow(title: "Repository", detail: repositoryDetail(settings.feedbackRepository)) {
                TextField("owner/name", text: $settings.feedbackRepository)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.callout)
                    .frame(width: Layout.sidebarWidth)
            }
            SettingsDivider()
            SettingsRow(
                title: "GitHub token",
                detail: tokenSaved
                    ? "Stored in your Keychain, never shown again."
                    : "A token that can open issues there. scripts/setup-feedback.sh copies one."
            ) {
                tokenControl
            }
            SettingsDivider()
            SettingsRow(title: "Include recent dictations", detail: "Your last few dictations from the past hour, so a note about one can be acted on.") {
                SettingsSwitch(label: "Include recent dictations", isOn: $settings.feedbackIncludesDictations)
            }
            SettingsDivider()
            SettingsRow(title: "Notes", detail: statusDetail(feedback)) {
                HStack(spacing: Spacing.m) {
                    if !feedback.outbox.pending.isEmpty {
                        Button {
                            sendNow()
                        } label: {
                            if sending {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Send Now")
                            }
                        }
                        .settingsButton()
                        .disabled(sending || !feedback.isSetUp)
                    }
                    Button("Show in Finder") {
                        guard preview == nil else { return }
                        _ = NSWorkspace.shared.open(feedback.outbox.directory)
                    }
                    .settingsButton()
                }
            }
        }
        .onAppear(perform: refreshToken)
    }

    @ViewBuilder
    private var tokenControl: some View {
        if tokenSaved {
            HStack(spacing: Spacing.m) {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(Typography.callout.weight(.medium))
                    .foregroundStyle(Palette.success)
                Button("Remove") {
                    guard preview == nil else { return }
                    Keychain.set(nil, for: .githubFeedback)
                    refreshToken()
                }
                .settingsButton()
            }
        } else {
            HStack(spacing: Spacing.s) {
                SecureField("GitHub token", text: $tokenDraft, prompt: Text("Paste a token"))
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.callout)
                    .frame(width: Layout.sidebarWidth - Spacing.huge)
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .settingsButton()
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func repositoryDetail(_ text: String) -> String {
        guard GitHubRepository(text) != nil else { return "Type it as owner/name." }
        return "Keep it private: notes carry the text of your dictations."
    }

    private func statusDetail(_ feedback: FeedbackCenter) -> String {
        let notes = feedback.outbox.notes
        let waiting = feedback.outbox.pending.count
        let untranscribed = notes.filter { !$0.hasWords }.count
        var parts: [String] = []
        if notes.isEmpty {
            parts.append("None yet.")
        } else if waiting == 0 {
            parts.append(notes.count == 1 ? "1 note, sent." : "\(notes.count) notes, all sent.")
        } else {
            parts.append(waiting == 1 ? "1 note waiting to send." : "\(waiting) notes waiting to send.")
            if let error = feedback.outbox.pending.last?.delivery.lastError {
                parts.append(error + ".")
            }
        }
        if untranscribed > 0 {
            parts.append(untranscribed == 1
                ? "1 recording couldn't be transcribed; its audio is in the folder."
                : "\(untranscribed) recordings couldn't be transcribed; their audio is in the folder.")
        }
        return parts.joined(separator: " ")
    }

    private func saveToken() {
        guard preview == nil else { return }
        Keychain.set(tokenDraft, for: .githubFeedback)
        tokenDraft = ""
        refreshToken()
        // Notes said before the token was there go now.
        sendNow()
    }

    private func sendNow() {
        guard preview == nil, !sending else { return }
        sending = true
        Task {
            await model.feedback.sendPending()
            sending = false
        }
    }

    private func refreshToken() {
        if let preview {
            tokenSaved = preview.keySaved
            return
        }
        tokenSaved = Keychain.hasValue(for: .githubFeedback)
    }
}
