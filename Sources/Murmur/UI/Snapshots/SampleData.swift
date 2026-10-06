import Foundation
import MurmurDictionary
import MurmurKit

/// Realistic sample content for snapshots and previews: a week of dictations across the
/// apps people actually dictate into, with a couple of failures, dictionary corrections and
/// polish — plus snippets and a dictionary. Dates are relative to `now`, so "Today" and
/// "Yesterday" always read correctly.
@MainActor
enum SampleData {
    static let dictionary: [DictionaryEntry] = [
        .correction(hear: "cloud code", write: "Claude Code"),
        .correction(hear: "whisper flow", write: "Wispr Flow"),
        .correction(hear: "a sink let", write: "async let"),
        .correction(hear: "get hub", write: "GitHub"),
        .correction(hear: "post gress", write: "Postgres"),
        DictionaryEntry(kind: .correction, write: "Claude", hear: "cloud", isEnabled: false),
        .term("Anthropic"),
        .term("Parakeet"),
        .term("Figma"),
        .term("Kubernetes"),
    ]

    static let snippets: [Snippet] = [
        Snippet(trigger: "my calendly link", expansion: "https://calendly.com/levi/30min"),
        Snippet(trigger: "my address", expansion: "2301 SE Division St, Portland, OR 97202"),
        Snippet(trigger: "standup template", expansion: "Yesterday:\nToday:\nBlockers:"),
        Snippet(trigger: "email sign off", expansion: "Thanks so much,\nLevi"),
        Snippet(trigger: "zoom link", expansion: "https://zoom.us/j/4155550142"),
        Snippet(
            trigger: "bug report",
            expansion: "Steps to reproduce:\n1. \n\nExpected:\n\nActual:",
            isEnabled: false
        ),
    ]

    private enum App {
        static let slack = AppContext(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", category: .work)
        static let messages = AppContext(bundleID: "com.apple.MobileSMS", appName: "Messages", category: .personal)
        static let mail = AppContext(bundleID: "com.apple.mail", appName: "Mail", category: .email)
        static let cursor = AppContext(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor", category: .other)
        static let notes = AppContext(bundleID: "com.apple.Notes", appName: "Notes", category: .other)
        static let terminal = AppContext(bundleID: "com.apple.Terminal", appName: "Terminal", category: .other)
        static let gmail = AppContext(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            windowTitle: "Inbox (4) - Gmail",
            category: .email
        )
    }

    private struct Spec {
        var day: Int
        /// Position within the day: 0 is the start, 1 is now (today) or late evening.
        var at: Double
        var app: AppContext
        var style: WritingStyle
        var raw: String
        var text: String
        var polish: PolishProvider?
        var wpm: Double = 150
        var engine = "Parakeet Ultra"
        var snippets: [String] = []
        var error: String?
        /// A polish fallback note on a dictation that still went through.
        var note: String?
    }

    private static let specs: [Spec] = [
        // Today
        Spec(day: 0, at: 0.97, app: App.slack, style: .casual,
             raw: "pushed the fix for the onboarding crash can someone on the ios side sanity check it before we cut the build",
             text: "Pushed the fix for the onboarding crash. Can someone on the iOS side sanity-check it before we cut the build?",
             polish: .anthropic, wpm: 162),
        Spec(day: 0, at: 0.92, app: App.cursor, style: .formal,
             raw: "refactor this to use a sink let so both requests run in parallel and add a five second timeout",
             text: "Refactor this to use async let so both requests run in parallel, and add a five-second timeout.",
             wpm: 148),
        Spec(day: 0, at: 0.86, app: App.messages, style: .casual,
             raw: "running like ten minutes late grab us a table by the window if you can",
             text: "Running ten minutes late, grab us a table by the window if you can", wpm: 171,
             note: "Timed out after 4 s"),
        Spec(day: 0, at: 0.78, app: App.gmail, style: .formal,
             raw: "hi priya thanks for the intro to the team at northwind i'd love to find thirty minutes next week to walk through how we label manipulation data does tuesday or wednesday afternoon work",
             text: "Hi Priya,\n\nThanks for the intro to the team at Northwind. I'd love to find thirty minutes next week to walk through how we label manipulation data. Does Tuesday or Wednesday afternoon work?",
             polish: .anthropic, wpm: 156),
        Spec(day: 0, at: 0.64, app: App.notes, style: .formal, raw: "", text: "", wpm: 140,
             error: "The speech model wasn't ready yet, so this one wasn't transcribed."),
        Spec(day: 0, at: 0.52, app: App.terminal, style: .formal,
             raw: "check whether the post gress migration ran on staging before we deploy",
             text: "Check whether the Postgres migration ran on staging before we deploy.", wpm: 139),
        Spec(day: 0, at: 0.4, app: App.slack, style: .excited,
             raw: "honestly the new whisper flow comparison deck looks great ship it",
             text: "Honestly, the new Wispr Flow comparison deck looks great. Ship it!", wpm: 166),
        // Yesterday
        Spec(day: 1, at: 0.85, app: App.mail, style: .formal,
             raw: "hi marcus attaching the updated data license the only change is the retention clause in section four happy to jump on a call if anything looks off best levi",
             text: "Hi Marcus,\n\nAttaching the updated data license. The only change is the retention clause in section four. Happy to jump on a call if anything looks off.\n\nBest,\nLevi",
             polish: .appleIntelligence, wpm: 144),
        Spec(day: 1, at: 0.74, app: App.messages, style: .casual,
             raw: "can you pick up oat milk on the way home we're out",
             text: "Can you pick up oat milk on the way home? We're out", wpm: 158),
        Spec(day: 1, at: 0.6, app: App.cursor, style: .formal,
             raw: "add a test that the dictionary corrector never rewrites words inside a url",
             text: "Add a test that the dictionary corrector never rewrites words inside a URL.", wpm: 136),
        Spec(day: 1, at: 0.48, app: App.slack, style: .casual, raw: "", text: "", wpm: 150,
             error: "The microphone stopped sending audio after 3 seconds. Check your input in Settings › Audio."),
        Spec(day: 1, at: 0.3, app: App.notes, style: .formal,
             raw: "ideas for the launch video open on hands typing cut to someone talking to their laptop while cooking end on the waveform",
             text: "Ideas for the launch video: open on hands typing, cut to someone talking to their laptop while cooking, end on the waveform.",
             wpm: 141),
        // Two days ago
        Spec(day: 2, at: 0.8, app: App.slack, style: .casual,
             raw: "cloud code just refactored the whole hud module in about four minutes",
             text: "Claude Code just refactored the whole HUD module in about four minutes", wpm: 168),
        Spec(day: 2, at: 0.66, app: App.gmail, style: .formal,
             raw: "thanks dana thursday at two works i'll send an invite with the agenda",
             text: "Thanks, Dana. Thursday at 2 works. I'll send an invite with the agenda.",
             polish: .openAICompatible, wpm: 152),
        Spec(day: 2, at: 0.5, app: App.messages, style: .excited,
             raw: "happy birthday mom can't wait to see you saturday",
             text: "Happy birthday, Mom! Can't wait to see you Saturday!", wpm: 160),
        Spec(day: 2, at: 0.35, app: App.terminal, style: .formal,
             raw: "remind me to rotate the staging api keys before friday",
             text: "Remind me to rotate the staging API keys before Friday.", wpm: 133, engine: "Apple Speech"),
        // Three days ago
        Spec(day: 3, at: 0.7, app: App.mail, style: .formal,
             raw: "hi team quick reminder that the office is closed monday enjoy the long weekend",
             text: "Hi team,\n\nQuick reminder that the office is closed Monday. Enjoy the long weekend!",
             polish: .anthropic, wpm: 149),
        Spec(day: 3, at: 0.55, app: App.cursor, style: .formal,
             raw: "make the sidebar width match the design token and remove the hard coded padding",
             text: "Make the sidebar width match the design token and remove the hard-coded padding.", wpm: 143),
        Spec(day: 3, at: 0.4, app: App.slack, style: .casual,
             raw: "does anyone have the figma link for the new onboarding flow",
             text: "Does anyone have the Figma link for the new onboarding flow?", wpm: 155),
        // Four days ago
        Spec(day: 4, at: 0.75, app: App.notes, style: .formal,
             raw: "book flights for the robotics conference in boston and check if hotels near the venue are still available",
             text: "Book flights for the robotics conference in Boston, and check if hotels near the venue are still available.",
             wpm: 147),
        Spec(day: 4, at: 0.6, app: App.messages, style: .casual,
             raw: "on my way see you in fifteen", text: "On my way, see you in 15", wpm: 164),
        Spec(day: 4, at: 0.45, app: App.slack, style: .casual,
             raw: "can we move the kubernetes upgrade to next sprint",
             text: "Can we move the Kubernetes upgrade to next sprint?", wpm: 151),
        // Five days ago
        Spec(day: 5, at: 0.7, app: App.mail, style: .formal,
             raw: "hi jordan thanks for the thoughtful feedback on the proposal i've folded most of it in and flagged two open questions at the end",
             text: "Hi Jordan,\n\nThanks for the thoughtful feedback on the proposal. I've folded most of it in and flagged two open questions at the end.",
             polish: .anthropic, wpm: 146),
        Spec(day: 5, at: 0.55, app: App.cursor, style: .formal,
             raw: "write a migration that adds a non null created at column with a default of now",
             text: "Write a migration that adds a non-null created_at column with a default of now().", wpm: 131),
        Spec(day: 5, at: 0.4, app: App.messages, style: .excited,
             raw: "sounds good see you tonight my calendly link",
             text: "Sounds good! See you tonight https://calendly.com/levi/30min", wpm: 159,
             snippets: ["my calendly link"]),
    ]

    /// About 25 dictations over the last six days, newest first.
    static func records(now: Date = Date(), calendar: Calendar = .current) -> [HistoryRecord] {
        let corrector = DictionaryCorrector(entries: dictionary)
        let today = calendar.startOfDay(for: now)
        let elapsedToday = now.timeIntervalSince(today)
        return specs.map { spec in
            let createdAt: Date
            if spec.day == 0 {
                createdAt = today.addingTimeInterval(elapsedToday * spec.at)
            } else {
                let day = calendar.date(byAdding: .day, value: -spec.day, to: today) ?? today
                // Spread the day's dictations between 8 am and 10 pm.
                createdAt = day.addingTimeInterval((8 + 14 * spec.at) * 3600)
            }
            let id = UUID()
            let failed = spec.error != nil
            let words = Double(max(spec.text.split { $0.isWhitespace }.count, 1))
            let duration = (words / spec.wpm * 60 * 10).rounded() / 10
            let transcribe = 120 + Int(words * 3)
            let polish = spec.polish == nil ? 0 : 420 + Int(words * 9)
            return HistoryRecord(
                id: id,
                createdAt: createdAt,
                context: spec.app,
                style: spec.style,
                engine: spec.engine,
                rawText: spec.raw,
                finalText: spec.text,
                polishedBy: spec.polish,
                corrections: spec.raw.isEmpty ? [] : corrector.apply(to: spec.raw).applied,
                snippets: spec.snippets,
                audioFileName: "\(id.uuidString).wav",
                audioDuration: duration,
                timings: failed ? DictationTimings() : DictationTimings(
                    transcribeMs: transcribe,
                    polishMs: polish,
                    totalMs: transcribe + polish + 40
                ),
                outcome: failed ? .failed : .inserted,
                errorMessage: spec.error ?? spec.note
            )
        }
    }

    /// A healthy Mac: permissions granted, shortcut armed, model ready.
    static let readyStatus = SystemStatus(
        accessibility: true,
        microphone: true,
        hotkeyActive: true,
        model: .ready,
        isRecording: false,
        engineName: SpeechEngineChoice.parakeetUltra.displayName,
        engineDownloadSize: SpeechEngineChoice.parakeetUltra.downloadSize,
        pushToTalkKey: PushToTalkKey.fn.displayName
    )
}

extension AppModel {
    /// A fully in-memory model for snapshots and previews: sample stores, throwaway
    /// settings, and nothing armed — it never touches the user's files or defaults.
    static func preview(
        records: [HistoryRecord] = SampleData.records(),
        snippets: [Snippet] = SampleData.snippets,
        dictionary: [DictionaryEntry] = SampleData.dictionary
    ) -> AppModel {
        let suite = "Murmur.Preview"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = Settings(defaults: defaults)
        // Someone with history has been through setup; an empty store is a first launch.
        settings.hasCompletedOnboarding = !records.isEmpty
        return AppModel(
            settings: settings,
            history: HistoryStore(previewRecords: records),
            snippets: SnippetStore(preview: snippets),
            dictionary: DictionaryStore(preview: dictionary)
        )
    }
}
