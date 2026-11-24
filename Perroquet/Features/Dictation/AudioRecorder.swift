import AVFoundation
import CoreAudio
import Synchronization

/// Records the chosen microphone, or the system default, as 16 kHz mono Float32 samples.
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
    private let selectedUID: () -> String?

    /// `selectedUID` returns the UID of the chosen microphone; nil or an unplugged device means the system default.
    init(selectedUID: @escaping () -> String? = { nil }) {
        self.selectedUID = selectedUID
    }

    /// Starts capturing, asking for microphone access when needed.
    func start() async throws {
        guard await Self.requestMicrophoneAccess() else { throw RecorderError.microphoneDenied }
        buffer.reset()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        useSelectedDevice(on: input)
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }
        input.installTap(
            onBus: 0, bufferSize: 4096, format: inputFormat,
            block: Self.makeTap(converter: converter, input: inputFormat, target: targetFormat, buffer: buffer))
        try engine.start()
        self.engine = engine
    }

    /// Stops capturing and returns the samples recorded since `start`.
    func stop() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        return buffer.take()
    }

    private func useSelectedDevice(on input: AVAudioInputNode) {
        guard let uid = selectedUID(), var device = InputDevices.deviceID(forUID: uid), let unit = input.audioUnit else {
            return
        }
        AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
            UInt32(MemoryLayout<AudioDeviceID>.size))
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
