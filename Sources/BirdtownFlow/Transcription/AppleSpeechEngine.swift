import AVFoundation
import Foundation
import os
import Speech

/// On-device transcription with macOS 26's `SpeechAnalyzer` / `SpeechTranscriber`, used in
/// batch: the whole utterance in, final text out.
///
/// Nothing ships with the app. macOS downloads and manages the speech assets per locale, so
/// the first use of a locale may wait for `AssetInstallationRequest`; `prepare()` does that
/// ahead of time.
actor AppleSpeechEngine: TranscriptionEngine {
    nonisolated var displayName: String { "Apple Speech" }

    private let locale: Locale
    /// The supported locale `locale` resolved to, once its assets are known to be installed.
    private var resolvedLocale: Locale?
    /// The resolution in progress. Actor methods interleave at every `await`, so without this
    /// a dictation arriving during `prepare()` would start a second asset installation.
    private var resolving: Task<Locale, Error>?

    /// Speech has a natural ceiling of roughly realtime on the slowest Macs; anything well past
    /// that is a stuck analyzer, and the recording is kept for Retry either way.
    private static let baseTimeLimit: Double = 15
    private static let sampleRate: Double = 16_000

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Resolves the locale and installs its assets if macOS hasn't yet.
    func prepare() async throws {
        _ = try await resolve()
    }

    func transcribe(_ samples: [Float], vocabulary: [String]) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let locale = try await resolve()
        let seconds = Double(samples.count) / Self.sampleRate
        let limit = Duration.seconds(Self.baseTimeLimit + seconds * 2)
        do {
            return try await HardDeadline.run(within: limit) {
                try await Self.analyze(samples, locale: locale, vocabulary: vocabulary)
            }
        } catch is HardDeadline.Exceeded {
            throw AppleSpeechError.timedOut
        }
    }

    // MARK: - Analysis

    private static func analyze(_ samples: [Float], locale: Locale, vocabulary: [String]) async throws -> String {
        let transcriber = makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Bias toward the dictionary before any audio arrives. A nudge, not a guarantee: the
        // dictionary pass after recognition is what enforces spelling. The list arrives capped
        // (a long context list makes the model hallucinate its terms on quiet audio).
        let phrases = vocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !phrases.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = phrases
            try? await analyzer.setContext(context)
        }

        // SpeechAnalyzer insists on its own format (16-bit integer on some Macs), so the
        // recorder's Float32 is converted rather than assumed compatible.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioUnreadable
        }
        let buffer = try PCMConversion.buffer(from: samples, sampleRate: sampleRate, to: format)

        // Drain results concurrently: they're produced while the analyzer runs.
        let collector = Task { [transcriber] () throws -> String in
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        feed.yield(AnalyzerInput(buffer: buffer))
        feed.finish()

        do {
            try await analyzer.start(inputSequence: input)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        return try await withTaskCancellationHandler {
            try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        } onCancel: {
            collector.cancel()
        }
    }

    // MARK: - Setup

    private func resolve() async throws -> Locale {
        if let resolvedLocale { return resolvedLocale }
        if let resolving { return try await resolving.value }

        let locale = self.locale
        let task = Task { try await Self.resolveAndInstall(locale) }
        resolving = task
        do {
            let supported = try await task.value
            resolvedLocale = supported
            resolving = nil
            return supported
        } catch {
            // Not cached: the next dictation tries again (the network may be back).
            resolving = nil
            throw error
        }
    }

    private static func resolveAndInstall(_ locale: Locale) async throws -> Locale {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        else {
            throw TranscriptionError.localeUnsupported(locale)
        }
        try await ensureAssetsInstalled(for: makeTranscriber(locale: supported))
        Log.speech.info("Apple Speech ready for \(supported.identifier, privacy: .public)")
        return supported
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        // Finals only: batch has no use for volatile results.
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    private static func ensureAssetsInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let alreadyThere = transcriber.selectedLocales.allSatisfy { selected in
            installed.contains { $0.identifier(.bcp47) == selected.identifier(.bcp47) }
        }
        guard !alreadyThere else { return }

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Log.speech.info("installing Apple speech assets")
                try await request.downloadAndInstall()
                Log.speech.info("Apple speech assets installed")
            }
        } catch {
            throw TranscriptionError.modelInstallFailed(error.localizedDescription)
        }
    }
}

enum AppleSpeechError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut: "Apple Speech stopped responding. Your recording is saved, so you can retry it from History."
        }
    }
}

/// Float32 samples → an `AVAudioPCMBuffer` in whatever format a consumer demands.
enum PCMConversion {
    static func buffer(from samples: [Float], sampleRate: Double, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard !samples.isEmpty,
              let sourceFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = source.floatChannelData?[0]
        else {
            throw TranscriptionError.audioUnreadable
        }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }

        if sourceFormat.isEqual(target) { return source }

        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw TranscriptionError.audioUnreadable
        }
        let ratio = target.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw TranscriptionError.audioUnreadable
        }

        // The input block runs synchronously inside `convert`, on this thread, and is the only
        // reader of `input`; nothing else touches the buffer while it's being converted.
        nonisolated(unsafe) let input = source
        let handedOver = OSAllocatedUnfairLock(initialState: false)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            let alreadyHandedOver = handedOver.withLock { flag -> Bool in
                defer { flag = true }
                return flag
            }
            if alreadyHandedOver {
                // One-shot: end of stream flushes the resampler's tail into `output`.
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }

        guard status != .error, conversionError == nil, output.frameLength > 0 else {
            throw TranscriptionError.audioUnreadable
        }
        return output
    }
}
