import AVFoundation
import CoreAudio
import os
import Synchronization

/// Records the chosen microphone, or the system default, as 16 kHz mono Float32 samples.
///
/// Between dictations it keeps an engine prepared for the next one (device opened, I/O not started, so no
/// microphone indicator), which saves the cold start of creating and initializing the input unit.
@MainActor
final class AudioRecorder: AudioRecording {
    /// Reasons recording cannot start.
    enum RecorderError: LocalizedError {
        /// Microphone access was refused.
        case microphoneDenied
        /// No converter exists from the microphone format to 16 kHz mono.
        case unsupportedFormat

        /// Message shown to the user.
        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Microphone access is denied."
            case .unsupportedFormat: "The microphone format is not supported."
            }
        }
    }

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(DatasetStore.sampleRate), channels: 1, interleaved: false)!
    private let buffer = SampleBuffer()
    private var engine: AVAudioEngine?
    /// Engine ready for the next `start`, with the device it was prepared for.
    private var prepared: (engine: AVAudioEngine, device: AudioDeviceID)?
    private let selectedUID: () -> String?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Perroquet", category: "recorder")

    /// `selectedUID` returns the UID of the chosen microphone; nil or an unplugged device means the system default.
    init(selectedUID: @escaping () -> String? = { nil }) {
        self.selectedUID = selectedUID
    }

    /// Prepares an engine for the next `start` when microphone access is granted and none is ready yet.
    func prepare() {
        guard engine == nil, prepared == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            let device = targetDevice()
        else { return }
        let clock = ContinuousClock()
        let begin = clock.now
        let engine = makeEngine(device: device)
        engine.prepare()
        // No `AVAudioEngineConfigurationChange` observer: preparing posts one itself, and re-preparing on it
        // loops. `start` instead reuses this engine only while the target device is unchanged.
        prepared = (engine, device)
        logger.notice("Prepared audio engine in \(Self.milliseconds(begin.duration(to: clock.now))) ms")
    }

    /// Starts capturing, asking for microphone access when needed.
    func start() async throws {
        guard await Self.requestMicrophoneAccess() else { throw RecorderError.microphoneDenied }
        buffer.reset()

        let clock = ContinuousClock()
        let begin = clock.now
        let device = targetDevice()
        let ready = prepared.flatMap { $0.device == device ? $0.engine : nil }
        let reused = ready != nil
        let engine = ready ?? makeEngine(device: device)
        prepared = nil
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }
        input.installTap(
            onBus: 0, bufferSize: 4096, format: inputFormat,
            block: Self.makeTap(converter: converter, input: inputFormat, target: targetFormat, buffer: buffer))
        try engine.start()
        self.engine = engine
        logger.notice(
            "Started recording in \(Self.milliseconds(begin.duration(to: clock.now))) ms (prepared engine: \(reused))")
    }

    /// Stops capturing and returns the samples recorded since `start`; the next engine is prepared afterwards,
    /// so that preparing never delays the transcription of these samples.
    func stop() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        Task { [weak self] in self?.prepare() }
        return buffer.take()
    }

    /// The chosen microphone when connected, else the system default input.
    private func targetDevice() -> AudioDeviceID? {
        selectedUID().flatMap(InputDevices.deviceID(forUID:)) ?? InputDevices.defaultInputID()
    }

    private func makeEngine(device: AudioDeviceID?) -> AVAudioEngine {
        let engine = AVAudioEngine()
        if var device, let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
                UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        return engine
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private nonisolated static func makeTap(
        converter: AVAudioConverter, input: AVAudioFormat, target: AVAudioFormat, buffer: SampleBuffer
    ) -> AVAudioNodeTapBlock {
        { pcm, _ in
            let ratio = target.sampleRate / input.sampleRate
            let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return pcm
            }
            guard error == nil, let channel = out.floatChannelData?[0] else { return }
            buffer.append(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}

/// Thread-safe sample accumulator filled from the audio thread.
private final class SampleBuffer: Sendable {
    private let samples = Mutex<[Float]>([])

    func reset() {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
    }

    func append(_ chunk: UnsafeBufferPointer<Float>) {
        samples.withLock { $0.append(contentsOf: chunk) }
    }

    func take() -> [Float] {
        samples.withLock {
            defer { $0 = [] }
            return $0
        }
    }
}
