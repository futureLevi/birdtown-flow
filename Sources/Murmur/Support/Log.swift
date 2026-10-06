import OSLog

enum Log {
    static let audio = Logger(subsystem: "io.github.futurelevi.murmur", category: "audio")
    static let speech = Logger(subsystem: "io.github.futurelevi.murmur", category: "speech")
    static let hotkey = Logger(subsystem: "io.github.futurelevi.murmur", category: "hotkey")
    static let inject = Logger(subsystem: "io.github.futurelevi.murmur", category: "inject")
    static let app = Logger(subsystem: "io.github.futurelevi.murmur", category: "app")
}

extension Log {
    static let ui = Logger(subsystem: "io.github.futurelevi.murmur", category: "ui")
    static let polish = Logger(subsystem: "io.github.futurelevi.murmur", category: "polish")
    static let history = Logger(subsystem: "io.github.futurelevi.murmur", category: "history")
}
