import Foundation

/// What a live recording's windows were decoded from, so the final buffer can be checked
/// against it before their text is used: each window's range, with its first and last 16
/// samples. A buffer that disagrees anywhere it was sampled (shifted, shorter, from another
/// recording) means the windows can't be trusted, and the recording is transcribed whole.
public struct SegmentLedger: Sendable, Equatable {
    private struct Entry: Sendable, Equatable {
        let range: Range<Int>
        let head: [Float]
        let tail: [Float]
    }

    /// Samples fingerprinted at each end of a range.
    public static let fingerprintLength = 16

    private var entries: [Entry] = []

    public init() {}

    /// The end of the furthest range committed, or 0.
    public var committedEnd: Int {
        entries.map(\.range.upperBound).max() ?? 0
    }

    /// Records that `samples` (exactly `range.count` of them, WAV-equivalent) were decoded
    /// as absolute samples `range`.
    public mutating func commit(range: Range<Int>, samples: ArraySlice<Float>) {
        precondition(samples.count == range.count, "one sample per position in the range")
        entries.append(Entry(
            range: range,
            head: Array(samples.prefix(Self.fingerprintLength)),
            tail: Array(samples.suffix(Self.fingerprintLength))
        ))
    }

    /// Whether `full` (the whole recording, WAV-equivalent) holds the same samples at every
    /// fingerprint.
    public func matches<C: RandomAccessCollection>(_ full: C) -> Bool where C.Element == Float, C.Index == Int {
        entries.allSatisfy { entry in
            guard entry.range.lowerBound >= 0, full.count >= entry.range.upperBound else { return false }
            let base = full.startIndex
            let head = full[(base + entry.range.lowerBound)..<(base + entry.range.lowerBound + entry.head.count)]
            let tail = full[(base + entry.range.upperBound - entry.tail.count)..<(base + entry.range.upperBound)]
            return head.elementsEqual(entry.head) && tail.elementsEqual(entry.tail)
        }
    }
}
