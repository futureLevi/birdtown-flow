import AVFoundation
import Foundation
import Observation

/// Plays one history recording at a time and reports progress for the row's ring.
///
/// One instance per page, so starting a second recording stops the first — two voices at
/// once is never what anyone wants.
@MainActor
@Observable
final class AudioPlayback {
    private(set) var playingID: UUID?
    /// 0…1 through the current recording.
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func isPlaying(_ id: UUID) -> Bool { playingID == id }

    /// Plays `url` for record `id`, or stops if that record is already playing.
    func toggle(_ id: UUID, url: URL?) {
        if playingID == id {
            stop()
            return
        }
        stop()
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        guard player.play() else { return }
        self.player = player
        playingID = id
        progress = 0
        // AVAudioPlayer has no progress callback; a light poll only while playing is the
        // simplest thing that can't leak — it ends itself when playback ends.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let player = self.player else { return }
                guard player.isPlaying else {
                    self.stop()
                    return
                }
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        playingID = nil
        progress = 0
    }
}
