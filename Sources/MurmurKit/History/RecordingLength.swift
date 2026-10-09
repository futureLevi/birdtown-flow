import Foundation

/// How long a saved recording is, read back from its WAV.
///
/// A long recording's History row is saved while it's still going (`LiveDictation`), before
/// anyone knows its length. After a crash or a quit the row stays as "Interrupted" with a
/// partial WAV that plays, so `HistoryStore` reads the length from the file at launch.
///
/// Every WAV Birdtown Flow writes (`AudioRecorder.writeWAV`, `IncrementalWAVWriter`) is the
/// same 44-byte header, 16-bit PCM at 16 kHz mono, then the samples. Any other file is left
/// alone rather than guessed at.
public enum RecordingLength {
    /// Bytes before the samples.
    public static let headerSize = 44
    static let sampleRate = 16_000
    /// 16-bit mono.
    static let bytesPerSample = 2

    /// Seconds of audio in a file of `fileSize` bytes that starts with `header`, or `nil` when
    /// the header isn't one the app writes.
    ///
    /// Counts the samples the header declares that the file really holds. A crash between
    /// writing samples and patching the header leaves a few more than declared; reading the
    /// file back (`AudioRecorder.readSamples`, Retry) ignores those too.
    public static func seconds(header: Data, fileSize: Int) -> Double? {
        let bytes = [UInt8](header.prefix(headerSize))
        guard bytes.count == headerSize, fileSize >= headerSize else { return nil }
        func tag(at offset: Int) -> String {
            String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
        }
        func uint16(at offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func uint32(at offset: Int) -> Int {
            uint16(at: offset) | uint16(at: offset + 2) << 16
        }
        guard tag(at: 0) == "RIFF", tag(at: 8) == "WAVE", tag(at: 12) == "fmt ",
              uint32(at: 16) == 16,
              uint16(at: 20) == 1,                              // PCM
              uint16(at: 22) == 1,                              // mono
              uint32(at: 24) == sampleRate,
              uint32(at: 28) == sampleRate * bytesPerSample,    // byte rate
              uint16(at: 32) == bytesPerSample,                 // block align
              uint16(at: 34) == bytesPerSample * 8,             // bits per sample
              tag(at: 36) == "data"
        else { return nil }
        let dataBytes = min(uint32(at: 40), fileSize - headerSize)
        return Double(dataBytes / bytesPerSample) / Double(sampleRate)
    }

    /// The same for the file at `url`; `nil` when it can't be read.
    public static func seconds(ofFileAt url: URL) -> Double? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: headerSize),
              let size = try? handle.seekToEnd()
        else { return nil }
        return seconds(header: header, fileSize: Int(size))
    }
}
