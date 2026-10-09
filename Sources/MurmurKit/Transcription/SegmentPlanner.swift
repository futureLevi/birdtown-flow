import Foundation

/// Where a long recording is cut into windows that are transcribed one at a time: at the
/// longest pause in each stretch of 6 to 12 seconds.
///
/// Each window carries audio on both sides of the stretch it keeps (2 s before, 0.96 s after),
/// so the model hears every kept word in context and punctuates and capitalises it as it
/// would mid-recording. At most 239,360 samples, a window is always one encoder pass
/// (FluidAudio's single-window limit is 240,000).
///
/// Deterministic on purpose: a cut is a pure function of the samples around it, on an
/// absolute 20 ms frame grid, so a live recording planned a second at a time and a Retry
/// planned from the saved WAV cut in exactly the same places.
public struct SegmentPlanner: Sendable {
    public struct Config: Sendable, Equatable {
        public var sampleRate = 16_000
        /// 20 ms analysis frames.
        public var frameSamples = 320
        /// Audio decoded before a window's kept stretch: 2.0 s.
        public var leftContext = 32_000
        /// Audio decoded after it: 0.96 s, 12 encoder frames.
        public var rightContext = 15_360
        /// No cut sooner than 6 s after the last one…
        public var minSegment = 96_000
        /// …and none later than 12 s.
        public var maxSegment = 192_000
        /// A pause this long (0.30 s) is a sentence or clause break.
        public var preferredPauseFrames = 15
        /// The shortest pause worth cutting at (0.16 s), when there's no longer one.
        public var minimumPauseFrames = 8
        /// With no pause at all, the cut goes in the quietest stretch this long.
        public var forcedWindowFrames = 8

        public init() {}
    }

    /// Where one window's kept stretch ends.
    public struct Cut: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// In the middle of a pause this many frames long.
            case pause(frames: Int)
            /// No pause long enough: in the quietest stretch.
            case forced
        }

        /// Absolute sample index.
        public let sample: Int
        public let kind: Kind

        public init(sample: Int, kind: Kind) {
            self.sample = sample
            self.kind = kind
        }
    }

    public let config: Config

    public init(config: Config = .init()) {
        self.config = config
    }

    /// The most samples a window can hold: left context, the longest kept stretch, right context.
    public var maximumWindowSamples: Int {
        config.leftContext + config.maxSegment + config.rightContext
    }

    /// The first sample the next cut after `lastCut` depends on.
    public func analysisStart(after lastCut: Int) -> Int {
        max(0, lastCut - config.leftContext)
    }

    /// How much audio must exist before the next cut after `lastCut` can be placed: the
    /// longest kept stretch and its right context.
    public func analysisEnd(after lastCut: Int) -> Int {
        lastCut + config.maxSegment + config.rightContext
    }

    /// The next cut after `lastCut`, or `nil` until enough audio exists to place it.
    ///
    /// - Parameters:
    ///   - audio: WAV-equivalent samples (`WAVQuantization.roundTrip` of live audio, or as
    ///     read from the WAV), starting at absolute sample `offset`. Anything outside
    ///     `analysisStart(after:) ..< analysisEnd(after:)` is ignored, so the answer doesn't
    ///     depend on how much audio was passed.
    ///   - lastCut: the previous cut, or 0. A multiple of `frameSamples`, as every cut is.
    public func nextCut(after lastCut: Int, audio: ArraySlice<Float>, offset: Int) -> Cut? {
        let frame = config.frameSamples
        let start = analysisStart(after: lastCut)
        let end = analysisEnd(after: lastCut)
        guard offset <= start, offset + audio.count >= end else { return nil }

        // Loudness of every whole frame in the analysis range, on the absolute grid.
        let firstFrame = (start + frame - 1) / frame
        let endFrame = end / frame
        var decibels = [Double](repeating: 0, count: max(0, endFrame - firstFrame))
        for index in decibels.indices {
            let from = audio.startIndex + (firstFrame + index) * frame - offset
            var sum = 0.0
            for sample in audio[from..<from + frame] {
                sum += Double(sample) * Double(sample)
            }
            let rms = (sum / Double(frame)).squareRoot()
            decibels[index] = 20 * log10(max(rms, 1e-7))
        }
        guard !decibels.isEmpty else { return nil }

        // Quiet is relative to this stretch of the recording: a noisy room has a high floor.
        let sorted = decibels.sorted()
        let noiseFloor = sorted[Int(Double(sorted.count - 1) * 0.10)]
        let peak = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let threshold = min(peak - 10, max(noiseFloor + 6, noiseFloor + 0.25 * (peak - noiseFloor)))
        func isQuiet(_ db: Double) -> Bool { db <= threshold || db < -55 }

        // Where the cut may go: 6 to 12 s after the last one.
        let searchFrom = (lastCut + config.minSegment) / frame - firstFrame
        let searchTo = (lastCut + config.maxSegment) / frame - firstFrame

        // Runs of quiet frames inside the search range, in order.
        var runs: [(start: Int, length: Int)] = []
        var runStart: Int?
        for index in searchFrom..<searchTo {
            if isQuiet(decibels[index]) {
                if runStart == nil { runStart = index }
            } else if let open = runStart {
                runs.append((start: open, length: index - open))
                runStart = nil
            }
        }
        if let open = runStart { runs.append((start: open, length: searchTo - open)) }

        for minimum in [config.preferredPauseFrames, config.minimumPauseFrames] {
            // The longest pause; a later one wins a tie, for the longer window.
            var best: (start: Int, length: Int)?
            for run in runs where run.length >= minimum && run.length >= (best?.length ?? 0) {
                best = run
            }
            if let best {
                let middle = firstFrame + best.start + best.length / 2
                return Cut(sample: middle * frame, kind: .pause(frames: best.length))
            }
        }

        // No pause: the quietest stretch, again preferring the later of equals.
        let width = config.forcedWindowFrames
        var quietest: (start: Int, mean: Double)?
        if searchTo - searchFrom >= width {
            var sum = decibels[searchFrom..<searchFrom + width].reduce(0, +)
            for first in searchFrom...(searchTo - width) {
                if first > searchFrom {
                    sum += decibels[first + width - 1] - decibels[first - 1]
                }
                let mean = sum / Double(width)
                if mean <= (quietest?.mean ?? .infinity) { quietest = (start: first, mean: mean) }
            }
        }
        let middle = firstFrame + (quietest?.start ?? searchFrom) + width / 2
        return Cut(sample: middle * frame, kind: .forced)
    }

    /// Every cut in a finished recording: `nextCut` from the start, as a live recording
    /// would have made them.
    public func plan(_ samples: [Float]) -> [Cut] {
        var cuts: [Cut] = []
        var lastCut = 0
        while let cut = nextCut(after: lastCut, audio: samples[...], offset: 0) {
            cuts.append(cut)
            lastCut = cut.sample
        }
        return cuts
    }

    /// The window that keeps `lastCut ..< cut`, or everything from `lastCut` on when `cut` is
    /// `nil` (the tail), in a recording of `total` samples.
    public func window(from lastCut: Int, to cut: Int?, total: Int) -> SegmentWindow {
        let rate = Double(config.sampleRate)
        let end = cut.map { min(total, $0 + config.rightContext) } ?? total
        return SegmentWindow(
            audio: analysisStart(after: lastCut)..<max(analysisStart(after: lastCut), end),
            keep: Double(lastCut) / rate..<(cut.map { Double($0) / rate } ?? .infinity)
        )
    }
}

/// One window of a long recording: the audio decoded, and the stretch of it whose words are
/// kept (the rest is context, kept by the neighbouring windows).
public struct SegmentWindow: Sendable, Equatable {
    /// Absolute samples.
    public let audio: Range<Int>
    /// Seconds from the start of the recording. Open-ended for the tail.
    public let keep: Range<Double>

    public init(audio: Range<Int>, keep: Range<Double>) {
        self.audio = audio
        self.keep = keep
    }
}
