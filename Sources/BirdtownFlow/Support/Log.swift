import OSLog

enum Log {
    static let audio = Logger(subsystem: "com.birdtownlabs.flow", category: "audio")
    static let speech = Logger(subsystem: "com.birdtownlabs.flow", category: "speech")
    static let hotkey = Logger(subsystem: "com.birdtownlabs.flow", category: "hotkey")
    static let inject = Logger(subsystem: "com.birdtownlabs.flow", category: "inject")
    static let app = Logger(subsystem: "com.birdtownlabs.flow", category: "app")
}

extension Log {
    static let ui = Logger(subsystem: "com.birdtownlabs.flow", category: "ui")
    static let polish = Logger(subsystem: "com.birdtownlabs.flow", category: "polish")
    static let history = Logger(subsystem: "com.birdtownlabs.flow", category: "history")
    /// One summary line per dictation and per Retry (`TimingLine`), at `.notice` so it persists.
    static let timing = Logger(subsystem: "com.birdtownlabs.flow", category: "timing")
}
