import AppKit
import Foundation

// CONTRACT — owned by the hud agent (feedback design lives with the HUD).

/// Short, quiet interface sounds. Respects `Settings.soundEnabled`.
///
/// Every cue is synthesized once (a few thousand samples: well under a millisecond), wrapped
/// as an in-memory WAV and kept as an `NSSound`. `play` only starts an already-decoded
/// sound, so it never blocks the main thread or delays the microphone.
@MainActor
enum Sounds {
    enum Cue: Sendable, CaseIterable {
        /// Microphone opened.
        case start
        /// Hands-free locked on.
        case lock
        /// Recording stopped, processing.
        case stop
        /// Text inserted.
        case done
        /// Cancelled with Esc.
        case cancel
        case error
    }

    static func play(_ cue: Cue) {
        guard Settings.shared.soundEnabled, let sound = sound(for: cue) else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    /// Synthesizes every cue ahead of time so the first dictation's start cue is instant.
    static func prepare() {
        for cue in Cue.allCases { _ = sound(for: cue) }
    }

    private static var cache: [Cue: NSSound] = [:]

    private static func sound(for cue: Cue) -> NSSound? {
        if let cached = cache[cue] { return cached }
        let samples = Synth.render(Synth.notes(for: cue))
        guard let sound = NSSound(data: Synth.wav(samples)) else { return nil }
        cache[cue] = sound
        return sound
    }
}

/// Warm, soft tones: a sine with a little second and third harmonic, a fast attack and an
/// exponential decay — closer to a felt mallet than a beep.
private enum Synth {
    static let sampleRate = 48_000
    /// Peak level, ≈ −23 dBFS: present, never startling.
    static let peak: Float = 0.07

    struct Note {
        var frequency: Double
        var start: Double
        var duration: Double
        var gain: Double = 1
    }

    static func notes(for cue: Sounds.Cue) -> [Note] {
        switch cue {
        case .start:
            // Two quick rising notes (E5 → A5): "I'm listening".
            [Note(frequency: 659.3, start: 0, duration: 0.07),
             Note(frequency: 880.0, start: 0.055, duration: 0.09)]
        case .lock:
            // A soft double tick: latched.
            [Note(frequency: 1318.5, start: 0, duration: 0.035, gain: 0.8),
             Note(frequency: 1318.5, start: 0.07, duration: 0.04, gain: 0.8)]
        case .stop:
            // A single lower note: got it.
            [Note(frequency: 587.3, start: 0, duration: 0.1)]
        case .done:
            // A gentle high tick.
            [Note(frequency: 1760.0, start: 0, duration: 0.05, gain: 0.6)]
        case .cancel:
            // Falling pair (A5 → E5).
            [Note(frequency: 880.0, start: 0, duration: 0.06),
             Note(frequency: 659.3, start: 0.05, duration: 0.08)]
        case .error:
            // Low double blip, high enough to survive laptop speakers.
            [Note(frequency: 311.1, start: 0, duration: 0.07),
             Note(frequency: 311.1, start: 0.1, duration: 0.08)]
        }
    }

    static func render(_ notes: [Note]) -> [Float] {
        let end = notes.map { $0.start + $0.duration }.max() ?? 0
        let count = Int((end + 0.01) * Double(sampleRate))
        var buffer = [Float](repeating: 0, count: count)
        let attack = 0.004
        let release = 0.006
        for note in notes {
            let first = Int(note.start * Double(sampleRate))
            let length = Int(note.duration * Double(sampleRate))
            // Decays to about −40 dB by the end of the note.
            let tau = note.duration / 4.6
            for n in 0..<length where first + n < count {
                let t = Double(n) / Double(sampleRate)
                var envelope = exp(-t / tau)
                if t < attack { envelope *= t / attack }
                let remaining = note.duration - t
                if remaining < release { envelope *= max(0, remaining / release) }
                let phase = 2 * Double.pi * note.frequency * t
                let tone = sin(phase) + 0.16 * sin(2 * phase) + 0.05 * sin(3 * phase)
                buffer[first + n] += Float(tone * envelope * note.gain)
            }
        }
        let loudest = buffer.reduce(Float(0)) { max($0, abs($1)) }
        guard loudest > 0 else { return buffer }
        let scale = peak / loudest
        return buffer.map { $0 * scale }
    }

    /// 16-bit mono PCM WAV.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1) // PCM
        append16(1) // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(byteCount)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(clamped * Float(Int16.max))))
        }
        return data
    }
}
