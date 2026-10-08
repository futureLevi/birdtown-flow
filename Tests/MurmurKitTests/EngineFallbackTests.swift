import Testing
@testable import MurmurKit

@Suite("EngineFallback")
struct EngineFallbackTests {
    @Test("No stand-in once the selected engine is ready")
    func ready() {
        #expect(EngineFallback.standIn(
            selected: "Parakeet Ultra", selectedIsDownloadable: true, selectedReady: true, loaded: "Parakeet Ultra"
        ) == nil)
    }

    @Test("Apple Speech stands in while Parakeet downloads")
    func appleWhileDownloading() {
        #expect(EngineFallback.standIn(
            selected: "Parakeet Ultra", selectedIsDownloadable: true, selectedReady: false, loaded: nil
        ) == "Apple Speech")
    }

    @Test("The previously loaded model stands in after a switch")
    func previousModel() {
        #expect(EngineFallback.standIn(
            selected: "Parakeet Ultra", selectedIsDownloadable: true, selectedReady: false, loaded: "Parakeet v3"
        ) == "Parakeet v3")
        // Switching to Apple Speech while it prepares: the Parakeet still loaded fills in.
        #expect(EngineFallback.standIn(
            selected: "Apple Speech", selectedIsDownloadable: false, selectedReady: false, loaded: "Parakeet Ultra"
        ) == "Parakeet Ultra")
    }

    @Test("Apple Speech can't stand in for itself")
    func appleSelected() {
        #expect(EngineFallback.standIn(
            selected: "Apple Speech", selectedIsDownloadable: false, selectedReady: false, loaded: nil
        ) == nil)
    }

    @Test("The note names both engines, and the progress when known")
    func note() {
        #expect(EngineFallback.note(standIn: "Apple Speech", selected: "Parakeet Ultra")
            == "Using Apple Speech until Parakeet Ultra is ready")
        #expect(EngineFallback.note(standIn: "Apple Speech", selected: "Parakeet Ultra", progress: "42%")
            == "Using Apple Speech until Parakeet Ultra is ready · 42%")
    }

    @Test("A record names a stand-in only when another engine ran")
    func ranOnStandIn() {
        #expect(EngineFallback.ranOnStandIn(recordEngine: "Apple Speech", selected: "Parakeet Ultra"))
        #expect(!EngineFallback.ranOnStandIn(recordEngine: "Parakeet Ultra", selected: "Parakeet Ultra"))
        #expect(!EngineFallback.ranOnStandIn(recordEngine: "Parakeet v2", selected: "Parakeet v2 (English)"))
        #expect(!EngineFallback.ranOnStandIn(recordEngine: "", selected: "Parakeet Ultra"))
    }
}
