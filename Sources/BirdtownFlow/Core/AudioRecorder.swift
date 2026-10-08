import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AudioRecorderError: LocalizedError, Sendable, Equatable {
    case noInputDevice
    case couldNotStart(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone is connected"
        case .couldNotStart: "Couldn't start the microphone"
        }
    }
}

/// One finished capture: 16 kHz mono Float32.
struct CapturedAudio: Sendable {
    var samples: [Float]
    /// Loudest ~33 ms window, on the meter's 0…1 scale. Used to drop silent recordings.
    var peakLevel: Float

    var duration: Double { Double(samples.count) / AudioRecorder.sampleRate }
}

/// Microphone capture: `AVAudioEngine` input tap → 16 kHz mono Float32, with a ~30 Hz level meter.
///
/// Every engine operation runs on one serial queue rather than the main thread. Starting an
/// input can take hundreds of milliseconds (a Bluetooth mic renegotiates its profile), and the
/// hotkey's event tap lives on the main run loop: a blocked main thread would stall every
/// keystroke on the system. Serializing start and stop on the same queue also means a key
/// released while the engine is still starting needs no special case — the stop simply runs
/// after the start.
///
/// `@unchecked Sendable` is sound because every mutable stored property is confined to
/// `queue`, except `handler`, which is guarded by `handlerLock`. The tap thread only touches
/// `CaptureSink`, which guards its own state.
final class AudioRecorder: @unchecked Sendable {
    enum Event: Sendable {
        /// A meter reading, 0…1 (≈ −50…0 dBFS), about 30 times a second.
        case level(Float, generation: Int)
        /// Capture ended by itself. What was captured is kept; call `stop()` to collect it.
        case interrupted(Interruption, generation: Int)
        /// The microphone couldn't be started.
        case failed(AudioRecorderError, generation: Int)
    }

    enum Interruption: Sendable {
        /// The input device went away or changed format (AirPods connected, mic unplugged).
        case deviceChanged
        /// The recording reached `maxDuration`.
        case timeLimit
    }

    static let sampleRate: Double = 16_000
    /// Hard cap per recording. A forgotten hands-free session stops here and is processed.
    static let maxDuration: Double = 600

    private let queue = DispatchQueue(label: "com.birdtownlabs.flow.audio", qos: .userInteractive)

    // Confined to `queue`.
    private var engine: AVAudioEngine?
    private var engineDevice: AudioDeviceID?
    private var configObserver: (any NSObjectProtocol)?
    private var sink: CaptureSink?
    /// The device setting from the last `prewarm` or `start`, so an idle rebuild picks the same one.
    private var lastDeviceUID: String?

    private let handlerLock = NSLock()
    private var handler: (@Sendable (Event) -> Void)?

    /// Events arrive on an arbitrary thread; the receiver hops to wherever it needs to be.
    func setEventHandler(_ handler: @escaping @Sendable (Event) -> Void) {
        handlerLock.withLock { self.handler = handler }
    }

    /// Builds the engine and instantiates the input unit ahead of time, so the first key-down
    /// doesn't pay for it. Doesn't open the device (no microphone indicator). Only call once
    /// microphone access is granted.
    func prewarm(deviceUID: String?) {
        queue.async {
            self.lastDeviceUID = deviceUID
            guard self.sink == nil else { return }
            _ = self.preparedEngine(for: AudioDevices.resolveInputDevice(uid: deviceUID))
        }
    }

    /// Opens the microphone and starts accumulating. Failures arrive as `.failed`.
    func start(deviceUID: String?, generation: Int) {
        queue.async { self.startOnQueue(deviceUID: deviceUID, generation: generation) }
    }

    /// Closes the microphone and returns everything captured since `start`.
    ///
    /// The samples are handed over before `engine.stop()`: stopping the device's I/O can take a
    /// while (longer on Bluetooth and USB inputs) and the captured audio doesn't depend on it.
    /// The stop still runs on `queue` right after, so a following `start` waits for it.
    func stop() async -> CapturedAudio {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let sink = self.sink else {
                    continuation.resume(returning: CapturedAudio(samples: [], peakLevel: 0))
                    return
                }
                self.sink = nil
                // Tap off before closing, so no trailing buffer is dropped between the two.
                self.engine?.inputNode.removeTap(onBus: 0)
                let audio = sink.close()
                continuation.resume(returning: audio)
                self.engine?.stop()
                Log.audio.info("capture stopped — \(audio.duration, format: .fixed(precision: 2))s")
            }
        }
    }

    /// Closes the microphone and throws the audio away.
    func cancel() {
        queue.async { _ = self.finishCapture() }
    }

    // MARK: - Queue

    private func startOnQueue(deviceUID: String?, generation: Int) {
        _ = finishCapture()
        lastDeviceUID = deviceUID

        let engine = preparedEngine(for: AudioDevices.resolveInputDevice(uid: deviceUID))
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        let tapFormat = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
              tapFormat.sampleRate > 0, tapFormat.channelCount > 0
        else {
            Log.audio.error("no usable input format (\(hardware.sampleRate)Hz × \(hardware.channelCount))")
            discardEngine()
            emit(.failed(.noInputDevice, generation: generation))
            return
        }

        let sink = CaptureSink(
            generation: generation,
            maxSamples: Int(Self.sampleRate * Self.maxDuration),
            emit: { [weak self] event in self?.emit(event) }
        )

        // `format: nil` taps in the bus's own format. Passing a format that disagrees with the
        // hardware raises an Objective-C exception, which Swift can't catch.
        input.installTap(onBus: 0, bufferSize: 1024, format: nil, block: sink.makeTapBlock())
        engine.prepare()
        do {
            try engine.start()
        } catch {
            Log.audio.error("engine start failed: \(error.localizedDescription, privacy: .public)")
            input.removeTap(onBus: 0)
            discardEngine()
            emit(.failed(.couldNotStart(error.localizedDescription), generation: generation))
            return
        }

        self.sink = sink
        Log.audio.info("capture started — \(tapFormat.sampleRate)Hz × \(tapFormat.channelCount) → 16kHz mono")
    }

    private func finishCapture() -> CapturedAudio {
        guard let sink else { return CapturedAudio(samples: [], peakLevel: 0) }
        self.sink = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        let audio = sink.close()
        Log.audio.info("capture stopped — \(audio.duration, format: .fixed(precision: 2))s")
        return audio
    }

    /// The engine for `device`, rebuilt when the device changed. A fresh engine per device
    /// avoids the input node reporting the previous device's cached format.
    private func preparedEngine(for device: AudioDeviceID?) -> AVAudioEngine {
        if let engine, engineDevice == device { return engine }
        discardEngine()

        let engine = AVAudioEngine()
        if let device, let unit = engine.inputNode.audioUnit {
            var deviceID = device
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                Log.audio.error("couldn't select input device \(device): OSStatus \(status)")
            }
        }
        // Touching the format instantiates the input unit now rather than on key-down.
        _ = engine.inputNode.inputFormat(forBus: 0)

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] note in
            guard let self, let object = note.object else { return }
            let id = ObjectIdentifier(object as AnyObject)
            self.queue.async { self.configurationChanged(source: id) }
        }

        self.engine = engine
        engineDevice = device
        return engine
    }

    private func discardEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.stop()
        engine = nil
        engineDevice = nil
    }

    /// The hardware changed under us. The engine has already stopped itself; keep what was
    /// captured and let the controller finish the dictation normally.
    private func configurationChanged(source: ObjectIdentifier) {
        guard let engine, ObjectIdentifier(engine) == source else { return }
        // The notification can also follow our own device selection while the engine keeps
        // running; only a stopped engine means capture actually ended.
        guard !engine.isRunning else { return }

        Log.audio.notice("audio configuration changed — rebuilding the engine")
        if let sink {
            engine.inputNode.removeTap(onBus: 0)
            sink.seal()
            emit(.interrupted(.deviceChanged, generation: sink.generation))
        }
        // The sink stays: `stop()` still collects its samples. Only the engine is rebuilt.
        let previousDevice = engineDevice
        discardEngine()
        if sink == nil { rebuildWhenSettled(replacing: previousDevice) }
    }

    /// While idle, re-prewarm for the device now in effect (AirPods became the default input),
    /// so the next key-down doesn't build an engine from cold. Waits briefly for the hardware to
    /// settle. Skipped when the device is unchanged: that notification may be our own device
    /// selection, and rebuilding for it could repeat forever; key-down builds lazily as before.
    private func rebuildWhenSettled(replacing previousDevice: AudioDeviceID?) {
        queue.asyncAfter(deadline: .now() + 0.5) {
            guard self.sink == nil, self.engine == nil else { return }
            let device = AudioDevices.resolveInputDevice(uid: self.lastDeviceUID)
            guard device != previousDevice else { return }
            Log.audio.info("input device changed while idle — prewarming the new one")
            _ = self.preparedEngine(for: device)
        }
    }

    private func emit(_ event: Event) {
        let handler = handlerLock.withLock { self.handler }
        handler?(event)
    }

    // MARK: - WAV

    /// Writes 16-bit PCM, 16 kHz, mono. Atomic: a crash mid-write never leaves a torn file.
    static func writeWAV(_ samples: [Float], to url: URL) throws {
        let rate = UInt32(sampleRate)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for index in samples.indices {
            let clamped = max(-1, min(1, samples[index]))
            pcm[index] = Int16((clamped * Float(Int16.max)).rounded())
        }
        let dataBytes = UInt32(pcm.count * MemoryLayout<Int16>.size)

        var data = Data(capacity: 44 + Int(dataBytes))
        data.append(contentsOf: Array("RIFF".utf8))
        appendLE(36 + dataBytes, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLE(UInt32(16), to: &data)
        appendLE(UInt16(1), to: &data)          // PCM
        appendLE(UInt16(1), to: &data)          // mono
        appendLE(rate, to: &data)
        appendLE(rate * 2, to: &data)           // byte rate
        appendLE(UInt16(2), to: &data)          // block align
        appendLE(UInt16(16), to: &data)         // bits per sample
        data.append(contentsOf: Array("data".utf8))
        appendLE(dataBytes, to: &data)
        // Apple hardware is little-endian, which is what WAV wants.
        pcm.withUnsafeBufferPointer { data.append($0) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Reads a WAV back as 16 kHz mono Float32, for Retry. Accepts 16-bit PCM and 32-bit
    /// float, any channel count (averaged) and any rate (linearly resampled).
    static func readSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try data.withUnsafeBytes { raw -> [Float] in
            guard raw.count >= 12,
                  String(decoding: raw[0..<4], as: UTF8.self) == "RIFF",
                  String(decoding: raw[8..<12], as: UTF8.self) == "WAVE"
            else { throw TranscriptionError.audioUnreadable }

            var formatTag: UInt16 = 0
            var channels = 0
            var rate = 0
            var bits = 0
            var payload: Range<Int>?

            var offset = 12
            while offset + 8 <= raw.count {
                let id = String(decoding: raw[offset..<offset + 4], as: UTF8.self)
                let size = Int(raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).littleEndian)
                let body = offset + 8
                let end = min(body + size, raw.count)
                if id == "fmt ", end - body >= 16 {
                    formatTag = raw.loadUnaligned(fromByteOffset: body, as: UInt16.self).littleEndian
                    channels = Int(raw.loadUnaligned(fromByteOffset: body + 2, as: UInt16.self).littleEndian)
                    rate = Int(raw.loadUnaligned(fromByteOffset: body + 4, as: UInt32.self).littleEndian)
                    bits = Int(raw.loadUnaligned(fromByteOffset: body + 14, as: UInt16.self).littleEndian)
                } else if id == "data" {
                    payload = body..<end
                }
                offset = body + size + (size & 1)
            }

            guard let payload, channels > 0, rate > 0 else { throw TranscriptionError.audioUnreadable }
            let isFloat = formatTag == 3 || (formatTag == 0xFFFE && bits == 32)
            let bytesPerSample = bits / 8
            guard (isFloat && bits == 32) || (!isFloat && bits == 16) else {
                throw TranscriptionError.audioUnreadable
            }

            let frameBytes = bytesPerSample * channels
            let frames = payload.count / frameBytes
            var samples = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    let at = payload.lowerBound + frame * frameBytes + channel * bytesPerSample
                    if isFloat {
                        sum += Float(bitPattern: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian)
                    } else {
                        sum += Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: Int16.self))) / 32_768
                    }
                }
                samples[frame] = sum / Float(channels)
            }
            return rate == Int(sampleRate) ? samples : resample(samples, from: Double(rate))
        }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Linear resampling to 16 kHz. Only for foreign files; our own recordings are 16 kHz.
    private static func resample(_ samples: [Float], from rate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let step = rate / sampleRate
        let count = Int(Double(samples.count) / step)
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let position = Double(index) * step
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            output[index] = samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
        return output
    }
}

// MARK: - Tap thread

/// Receives tap buffers on AVAudioEngine's tap thread, converts them to 16 kHz mono and
/// accumulates them, metering as it goes.
///
/// `@unchecked Sendable` is sound because every mutable stored property is read and written
/// only while holding `lock`; the immutable ones are set in `init`.
private final class CaptureSink: @unchecked Sendable {
    let generation: Int

    private let lock = NSLock()
    private let maxSamples: Int
    private let emit: @Sendable (AudioRecorder.Event) -> Void
    private let outputFormat: AVAudioFormat?

    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var isOpen = true
    private var peak: Float = 0
    private var windowSum: Float = 0
    private var windowCount = 0

    /// 1/30 s at 16 kHz: one meter reading per window, however the hardware sizes its buffers.
    private static let meterWindow = Int(AudioRecorder.sampleRate / 30)

    init(generation: Int, maxSamples: Int, emit: @escaping @Sendable (AudioRecorder.Event) -> Void) {
        self.generation = generation
        self.maxSamples = maxSamples
        self.emit = emit
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioRecorder.sampleRate,
            channels: 1,
            interleaved: false
        )
        samples.reserveCapacity(Int(AudioRecorder.sampleRate) * 30)
    }

    /// Built here, in a nonisolated context, so the closure carries no actor isolation: it
    /// runs on the audio tap thread, and a main-actor closure would trap there.
    func makeTapBlock() -> AVAudioNodeTapBlock {
        { [self] buffer, _ in self.ingest(buffer) }
    }

    /// Stops accepting audio (device change) without discarding what's been captured.
    func seal() {
        lock.withLock { isOpen = false }
    }

    func close() -> CapturedAudio {
        lock.withLock {
            isOpen = false
            if windowCount > 0 {
                peak = max(peak, Self.level(rms: (windowSum / Float(windowCount)).squareRoot()))
                windowSum = 0
                windowCount = 0
            }
            let audio = CapturedAudio(samples: samples, peakLevel: peak)
            samples = []
            return audio
        }
    }

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard isOpen, let chunk = convert(buffer), !chunk.isEmpty else { return }

            let room = maxSamples - samples.count
            let accepted = chunk.count > room ? Array(chunk.prefix(room)) : chunk
            samples.append(contentsOf: accepted)
            meter(accepted)

            if samples.count >= maxSamples {
                isOpen = false
                emit(.interrupted(.timeLimit, generation: generation))
            }
        }
    }

    /// Converts into a fresh buffer we own. AVAudioEngine reuses the tap's buffer as soon as
    /// the block returns, so it must never be retained.
    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let outputFormat, buffer.frameLength > 0 else { return nil }
        let inputFormat = buffer.format
        if converter == nil || converter?.inputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            // Mix every input channel into the mono output. At its default the converter keeps
            // only the first channel, so a mic on input 2 of an audio interface would record
            // silence and every dictation would be dropped as silent.
            converter?.downmix = true
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        // The input block runs synchronously inside `convert`, on this thread. `.noDataNow`
        // (not end-of-stream) keeps the resampler's filter state across buffers.
        nonisolated(unsafe) let input = buffer
        let consumed = Latch()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed.take() {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, output.frameLength > 0,
              let channel = output.floatChannelData?[0]
        else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private func meter(_ chunk: [Float]) {
        for sample in chunk {
            windowSum += sample * sample
            windowCount += 1
            if windowCount == Self.meterWindow {
                let level = Self.level(rms: (windowSum / Float(windowCount)).squareRoot())
                peak = max(peak, level)
                emit(.level(level, generation: generation))
                windowSum = 0
                windowCount = 0
            }
        }
    }

    /// RMS → dBFS, with −50…0 dB mapped onto 0…1 so quiet speech still moves the meter.
    static func level(rms: Float) -> Float {
        let decibels = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (decibels + 50) / 50))
    }
}

/// One-shot flag for the converter's input block.
///
/// `@unchecked Sendable`: only touched on the tap thread, inside one synchronous `convert` call.
private final class Latch: @unchecked Sendable {
    private var fired = false

    /// - Returns: the value *before* this call, then latches to `true`.
    func take() -> Bool {
        defer { fired = true }
        return fired
    }
}
