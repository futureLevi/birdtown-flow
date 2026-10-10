import Foundation
import Testing
@testable import MurmurKit

/// A WAV laid out as the app writes one: the 44-byte header, then `samples` silent 16-bit
/// samples. `declared` is the sample count the header claims, when it isn't `samples`.
private func appWAV(samples: Int, declared: Int? = nil, rate: UInt32 = 16_000, bits: UInt16 = 16) -> Data {
    func appendLE<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }
    let blockAlign = bits / 8
    let dataBytes = UInt32((declared ?? samples) * Int(blockAlign))
    var bytes: [UInt8] = []
    bytes.append(contentsOf: Array("RIFF".utf8))
    appendLE(36 + dataBytes, to: &bytes)
    bytes.append(contentsOf: Array("WAVE".utf8))
    bytes.append(contentsOf: Array("fmt ".utf8))
    appendLE(UInt32(16), to: &bytes)
    appendLE(UInt16(1), to: &bytes)
    appendLE(UInt16(1), to: &bytes)
    appendLE(rate, to: &bytes)
    appendLE(rate * UInt32(blockAlign), to: &bytes)
    appendLE(blockAlign, to: &bytes)
    appendLE(bits, to: &bytes)
    bytes.append(contentsOf: Array("data".utf8))
    appendLE(dataBytes, to: &bytes)
    bytes.append(contentsOf: [UInt8](repeating: 0, count: samples * Int(blockAlign)))
    return Data(bytes)
}

private func scratchDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmurkit-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("RecordingLength")
@MainActor
struct RecordingLengthTests {
    func seconds(_ wav: Data) -> Double? {
        RecordingLength.seconds(header: wav, fileSize: wav.count)
    }

    @Test("A WAV the app wrote is as long as its samples")
    func appFile() {
        #expect(seconds(appWAV(samples: 48_000)) == 3)
        #expect(seconds(appWAV(samples: 8_000)) == 0.5)
        #expect(seconds(appWAV(samples: 0)) == 0)
        // A torn last sample isn't a sample.
        var torn = appWAV(samples: 16_000)
        torn.append(UInt8(0))
        #expect(seconds(torn) == 1)
    }

    @Test("Only samples both declared and on disk count, as Retry reads them")
    func declaredAndOnDisk() {
        // A crash between appending samples and patching the header.
        #expect(seconds(appWAV(samples: 32_000, declared: 16_000)) == 1)
        // A file cut short of what its header says.
        #expect(seconds(appWAV(samples: 16_000, declared: 32_000)) == 1)
    }

    @Test("Any other file isn't guessed at")
    func foreignFiles() {
        #expect(seconds(appWAV(samples: 16_000, rate: 44_100)) == nil)
        #expect(seconds(appWAV(samples: 16_000, bits: 32)) == nil)
        #expect(seconds(Data([1])) == nil)
        #expect(seconds(Data()) == nil)
        var notWAV = appWAV(samples: 16_000)
        notWAV[8] = UInt8(ascii: "X")
        #expect(seconds(notWAV) == nil)
    }

    @Test("Read from a file on disk")
    func fromFile() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a.wav")
        try appWAV(samples: 24_000).write(to: url)
        #expect(RecordingLength.seconds(ofFileAt: url) == 1.5)
        #expect(RecordingLength.seconds(ofFileAt: directory.appendingPathComponent("missing.wav")) == nil)
    }

    @Test("A row a crash left without a length gets it back from its WAV when History loads")
    func interruptedRowLength() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func row(_ outcome: DictationOutcome, samples: Int?, duration: Double = 0, minutesAgo: Double) throws -> HistoryRecord {
            let id = UUID()
            var name: String?
            if let samples {
                let audio = store.newRecordingURL(for: id)
                try appWAV(samples: samples).write(to: audio)
                name = audio.lastPathComponent
            }
            return HistoryRecord(id: id, createdAt: now.addingTimeInterval(-minutesAgo * 60),
                                 audioFileName: name, audioDuration: duration, outcome: outcome,
                                 errorMessage: outcome == .failed ? "Interrupted" : nil)
        }
        let interrupted = try row(.failed, samples: 16_000 * 12, minutesAgo: 1)
        let timed = try row(.failed, samples: 16_000 * 4, duration: 4.2, minutesAgo: 2)
        let inserted = try row(.inserted, samples: 16_000 * 3, minutesAgo: 3)
        let noAudio = try row(.failed, samples: nil, minutesAgo: 4)
        for record in [interrupted, timed, inserted, noAudio] { store.add(record) }
        store.flush()

        let reloaded = HistoryStore(directory: directory)
        #expect(reloaded.record(id: interrupted.id)?.audioDuration == 12)
        // Rows that know their length, or aren't failed, or have no audio, are left as they are.
        #expect(reloaded.record(id: timed.id)?.audioDuration == 4.2)
        #expect(reloaded.record(id: inserted.id)?.audioDuration == 0)
        #expect(reloaded.record(id: noAudio.id)?.audioDuration == 0)
    }
}
