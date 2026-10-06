import Foundation

/// Where Birdtown Flow keeps its files.
///
///     ~/Library/Application Support/Birdtown Flow/
///         dictionary.txt     the dictionary, plain text, hand-editable
///         snippets.json
///         history/history.json
///         history/recordings/<id>.wav
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Birdtown Flow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static var history: URL { support.appendingPathComponent("history", isDirectory: true) }
    static var snippets: URL { support.appendingPathComponent("snippets.json") }
}
