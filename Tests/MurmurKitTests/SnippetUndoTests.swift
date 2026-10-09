import Foundation
import Testing
@testable import MurmurKit

@Suite("Snippet deletes with undo")
@MainActor
struct SnippetUndoTests {
    private func temporaryFile() -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, directory.appendingPathComponent("snippets.json"))
    }

    @Test("A delete hides the snippet, stops it expanding, and Undo brings it back")
    func undo() {
        let snippet = Snippet(trigger: "my address", expansion: "1 Main St")
        let store = SnippetStore(preview: [snippet])
        store.delete(ids: [snippet.id], undoWindow: .seconds(60))
        #expect(store.visible.isEmpty)
        #expect(store.enabled.isEmpty)
        #expect(store.snippets == [snippet])
        store.undoDeletion()
        #expect(store.visible == [snippet])
        #expect(store.enabled == [snippet])
    }

    @Test("Committing removes it for good, and saves")
    func commit() {
        let (directory, file) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(fileURL: file)
        let snippet = Snippet(trigger: "zoom link", expansion: "https://zoom.us/j/1")
        store.add(snippet)
        store.delete(ids: [snippet.id], undoWindow: .seconds(60))
        store.commitDeletion()
        #expect(store.snippets.isEmpty)
        #expect(SnippetStore(fileURL: file).snippets.isEmpty)
    }

    @Test("The undo window closing commits the delete")
    func windowCloses() async throws {
        let snippet = Snippet(trigger: "sign off", expansion: "Thanks")
        let store = SnippetStore(preview: [snippet])
        store.delete(ids: [snippet.id], undoWindow: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.snippets.isEmpty)
        #expect(store.deletion.pending.isEmpty)
    }

    @Test("A second delete makes the first final; Undo brings back only the last")
    func secondDelete() {
        let a = Snippet(trigger: "a one", expansion: "A")
        let b = Snippet(trigger: "b two", expansion: "B")
        let store = SnippetStore(preview: [a, b])
        store.delete(ids: [a.id], undoWindow: .seconds(60))
        store.delete(ids: [b.id], undoWindow: .seconds(60))
        #expect(store.snippets == [b])
        store.undoDeletion()
        #expect(store.visible == [b])
    }

    @Test("A deleted snippet's trigger is free to reuse, and reusing it makes the delete final")
    func reuseTrigger() {
        let old = Snippet(trigger: "zoom link", expansion: "old")
        let store = SnippetStore(preview: [old])
        store.delete(ids: [old.id], undoWindow: .seconds(60))
        #expect(!store.hasConflict(trigger: "Zoom Link"))
        let replacement = Snippet(trigger: "zoom link", expansion: "new")
        store.add(replacement)
        #expect(store.snippets == [replacement])
        store.undoDeletion()
        #expect(store.snippets == [replacement])
    }

    @Test("Editing a trigger remembers the old one, on disk too")
    func renameIsRemembered() {
        let (directory, file) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnippetStore(fileURL: file)
        var snippet = Snippet(trigger: "My Link", expansion: "https://x")
        store.add(snippet)
        snippet.trigger = "calendly link"
        store.update(snippet)
        #expect(store.aliases.formerKeys(of: snippet.id.uuidString) == ["my link"])
        #expect(SnippetStore(fileURL: file).aliases == store.aliases)

        // Only the expansion changing isn't a rename.
        snippet.expansion = "https://y"
        store.update(snippet)
        #expect(store.aliases.formerKeys(of: snippet.id.uuidString) == ["my link"])

        store.delete(ids: [snippet.id])
        #expect(store.aliases.former.isEmpty)
    }
}
