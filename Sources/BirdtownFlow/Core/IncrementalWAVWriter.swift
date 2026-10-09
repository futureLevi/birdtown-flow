import Foundation
import MurmurKit

/// Writes a long recording's WAV while it's still going, window by window, so each window's
/// audio is on disk before that window is decoded (rule 2).
///
/// The file is a valid WAV after every append: samples go first, then the header's two sizes
/// are patched, so a crash at any point leaves a file `AudioRecorder.readSamples` can read.
/// At key-up `DictationController.process` writes the whole recording to the same URL in one
/// atomic piece, which replaces this file.
///
/// Samples are converted exactly as `AudioRecorder.writeWAV` does (`WAVQuantization.pcm16`).
actor IncrementalWAVWriter {
    enum Failure: Error {
        /// `close()` or `discard()` already ran.
        case closed
        /// Samples would start after the end of what's on disk, leaving a hole.
        case gap
    }

    let url: URL
    /// Samples on disk: the absolute index the next new sample goes at.
    private(set) var written = 0
    private var handle: FileHandle?
    private var isClosed = false

    init(url: URL) {
        self.url = url
    }

    /// Writes `samples[i]` as absolute sample `offset + i`, up to (not including) absolute
    /// sample `end`. What's already on disk is skipped, so overlapping copies (a window's
    /// left context) are never written twice.
    func append(_ samples: [Float], from offset: Int, upTo end: Int) throws {
        guard !isClosed else { throw Failure.closed }
        guard offset <= written else { throw Failure.gap }
        let first = written - offset
        let last = min(end - offset, samples.count)
        guard last > first else { return }

        let handle = try openedHandle()
        let pcm = samples[first..<last].map(WAVQuantization.pcm16)
        var data = Data(capacity: pcm.count * MemoryLayout<Int16>.size)
        pcm.withUnsafeBufferPointer { data.append($0) }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        written += pcm.count

        let dataBytes = UInt32(written * MemoryLayout<Int16>.size)
        try patch(handle, at: AudioRecorder.wavRIFFSizeOffset, with: 36 + dataBytes)
        try patch(handle, at: AudioRecorder.wavDataSizeOffset, with: dataBytes)
    }

    /// Done appending. The file stays.
    func close() {
        isClosed = true
        try? handle?.close()
        handle = nil
    }

    /// Done, and the file goes too (Esc while recording).
    func discard() {
        close()
        try? FileManager.default.removeItem(at: url)
    }

    private func openedHandle() throws -> FileHandle {
        if let handle { return handle }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AudioRecorder.wavHeader(dataBytes: 0).write(to: url)
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        return opened
    }

    private func patch(_ handle: FileHandle, at offset: UInt64, with value: UInt32) throws {
        var bytes = Data()
        AudioRecorder.appendLE(value, to: &bytes)
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: bytes)
    }
}
