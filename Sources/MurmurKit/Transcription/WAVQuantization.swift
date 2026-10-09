import Foundation

/// How a recording's samples change on their way through its 16-bit WAV.
///
/// The one place the Float → PCM16 conversion lives: `AudioRecorder.writeWAV` and the live
/// WAV writer both use `pcm16`, and reading the file back divides by 32,768
/// (`AudioRecorder.readSamples`). `roundTrip` is that whole trip, so audio quantized live is
/// bit-identical to what a Retry reads from disk, and both cut and decode the same windows.
///
/// `roundTrip` is not idempotent (32,767 in, 32,768 out): never apply it to samples that were
/// read from a WAV.
public enum WAVQuantization {
    /// The sample as written to the WAV: clamped to [-1, 1], scaled by 32,767, rounded.
    public static func pcm16(_ x: Float) -> Int16 {
        let clamped = max(-1, min(1, x))
        return Int16((clamped * Float(Int16.max)).rounded())
    }

    /// The sample as read back from the WAV.
    public static func roundTrip(_ x: Float) -> Float {
        Float(pcm16(x)) / 32_768
    }

    public static func roundTrip(_ xs: ArraySlice<Float>) -> [Float] {
        xs.map { roundTrip($0) }
    }
}
