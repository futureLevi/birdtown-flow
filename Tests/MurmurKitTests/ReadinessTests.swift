import Testing
@testable import MurmurKit

@Suite("ReadinessIssue")
struct ReadinessTests {
    @Test("Nothing to fix when every piece is in place, or the model is still on its way")
    func ready() {
        #expect(ReadinessIssue.first(microphone: true, accessibility: true, hotkeyActive: true, model: .ready) == nil)
        #expect(ReadinessIssue.first(microphone: true, accessibility: true, hotkeyActive: true, model: .preparing) == nil)
    }

    @Test("Permissions come first, then the shortcut, then the model")
    func order() {
        #expect(ReadinessIssue.first(microphone: false, accessibility: false, hotkeyActive: false, model: .failed)
            == .microphone)
        // Without Accessibility there can be no shortcut, so the grant is the thing to fix.
        #expect(ReadinessIssue.first(microphone: true, accessibility: false, hotkeyActive: false, model: .failed)
            == .accessibility)
        #expect(ReadinessIssue.first(microphone: true, accessibility: true, hotkeyActive: false, model: .notDownloaded)
            == .shortcutInactive)
        #expect(ReadinessIssue.first(microphone: true, accessibility: true, hotkeyActive: true, model: .failed)
            == .modelFailed)
        #expect(ReadinessIssue.first(microphone: true, accessibility: true, hotkeyActive: true, model: .notDownloaded)
            == .modelNotDownloaded)
    }

    @Test("Only a broken model reads as a failure")
    func severity() {
        #expect(ReadinessIssue.modelFailed.isFailure)
        #expect(!ReadinessIssue.microphone.isFailure)
        #expect(!ReadinessIssue.shortcutInactive.isFailure)
        #expect(ReadinessIssue.shortcutInactive.status == "Shortcut not active")
    }
}
