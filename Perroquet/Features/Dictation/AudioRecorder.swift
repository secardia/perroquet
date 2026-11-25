import AVFoundation
import CoreAudio
import os
import Synchronization

/// Records the chosen microphone, or the system default, as 16 kHz mono Float32 samples.
///
/// One engine is kept for the chosen device and only paused between dictations: its input unit stays initialized
/// but the hardware I/O is stopped, so nothing is captured and no microphone indicator shows, while the next
/// `start` skips the cold start of creating and initializing the unit. Bluetooth microphones are the exception: an
/// engine on them switches the headset to its low-quality call profile, so none is kept between dictations.
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
            case .microphoneDenied: String(localized: "Microphone access is denied.")
            case .unsupportedFormat: String(localized: "The microphone format is not supported.")
            }
        }
    }

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(DatasetStore.sampleRate), channels: 1, interleaved: false)!
    private let buffer = SampleBuffer()
    /// Engine kept between dictations, with the device it was made for.
    private var current: (engine: AVAudioEngine, device: AudioDeviceID?)?
    private var isRecording = false
    /// Times the running engine was restarted after a configuration change during this dictation.
    private var restarts = 0
    private let selectedUID: () -> String?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Perroquet", category: "recorder")

    /// `selectedUID` returns the UID of the chosen microphone; nil or an unplugged device means the system default,
    /// or the built-in microphone when the default is a Bluetooth headset.
    init(selectedUID: @escaping () -> String? = { nil }) {
        self.selectedUID = selectedUID
        // The engine stops itself when its device changes format mid-recording, as a Bluetooth headset does when it
        // switches to its call profile right after the engine starts. Notifications posted outside a recording,
        // such as the one preparing posts, are ignored.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] notification in
            let engine = notification.object as? AVAudioEngine
            MainActor.assumeIsolated { self?.configurationChanged(engine) }
        }
    }

    /// Prepares an engine for the target device when microphone access is granted, unless one is already kept for
    /// it or it is a Bluetooth headset; call it at launch and whenever the chosen microphone changes.
    func prepare() {
        guard !isRecording, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            let device = targetDevice(), current?.device != device
        else { return }
        guard !InputDevices.isBluetooth(device) else {
            current = nil
            return
        }
        let clock = ContinuousClock()
        let begin = clock.now
        let engine = makeEngine(device: device)
        engine.prepare()
        // No `AVAudioEngineConfigurationChange` observer: preparing posts one itself, and re-preparing on it
        // loops. `start` instead reuses this engine only while the target device is unchanged.
        current = (engine, device)
        logger.notice("Prepared audio engine in \(Self.milliseconds(begin.duration(to: clock.now))) ms")
    }

    /// Starts capturing, asking for microphone access when needed.
    func start() async throws {
        guard await Self.requestMicrophoneAccess() else { throw RecorderError.microphoneDenied }
        buffer.reset()

        let clock = ContinuousClock()
        let begin = clock.now
        let device = targetDevice()
        let kept = current.flatMap { $0.device == device ? $0.engine : nil }
        current = nil
        var engine = kept ?? makeEngine(device: device)
        var attempt = 1
        // A Bluetooth headset can switch to its call profile, at a lower sample rate, while the engine starts, which
        // then fails with a format error. A fresh engine made right away reads the new format; waiting would let
        // the headset fall back to its music profile.
        while true {
            do {
                try startCapture(on: engine)
                break
            } catch where attempt < Self.startAttempts {
                logger.notice("Start attempt \(attempt) failed (\(error.localizedDescription)), retrying")
                attempt += 1
                engine = makeEngine(device: device)
            }
        }
        current = (engine, device)
        restarts = 0
        isRecording = true
        logger.notice(
            "Started recording in \(Self.milliseconds(begin.duration(to: clock.now))) ms (kept engine: \(kept != nil), attempts: \(attempt))")
    }

    /// Stops capturing and returns the samples recorded since `start`. The engine is paused rather than stopped,
    /// so it stays prepared for the next `start`, except on a Bluetooth headset, which it releases.
    func stop() -> [Float] {
        if isRecording, let (engine, device) = current {
            engine.inputNode.removeTap(onBus: 0)
            if let device, InputDevices.isBluetooth(device) {
                engine.stop()
                current = nil
            } else {
                engine.pause()
            }
        }
        isRecording = false
        let samples = buffer.take()
        logCapture(samples)
        return samples
    }

    /// Logs how much audio was captured, its peak and when sound first appears, to tell silent or truncated
    /// captures apart from transcription problems.
    private func logCapture(_ samples: [Float]) {
        let rate = Double(DatasetStore.sampleRate)
        let peak = samples.reduce(0) { max($0, abs($1)) }
        let firstSound = samples.firstIndex { abs($0) > 0.02 }.map { Double($0) / rate } ?? -1
        logger.notice(
            "Captured \(Double(samples.count) / rate) s, peak \(peak), first sound at \(firstSound) s, restarts \(self.restarts)")
    }

    /// Restarts the recording engine with a tap in the device's current format after a configuration change. Always:
    /// the notification can arrive while the engine still runs at the old format, and a Bluetooth headset then
    /// stops delivering audio about two seconds later.
    private func configurationChanged(_ changed: AVAudioEngine?) {
        guard isRecording, let engine = current?.engine, changed === engine else { return }
        let hardware = engine.inputNode.inputFormat(forBus: 0)
        guard restarts < Self.maxRestarts else {
            logger.error("Engine configuration keeps changing; capture stopped")
            return
        }
        restarts += 1
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try startCapture(on: engine)
            logger.notice("Restarted recording after a configuration change (\(hardware.sampleRate) Hz)")
        } catch {
            logger.error("Could not restart recording: \(error.localizedDescription)")
        }
    }

    /// The chosen microphone when connected, else the system default input, Bluetooth headsets excepted.
    private func targetDevice() -> AudioDeviceID? {
        selectedUID().flatMap(InputDevices.deviceID(forUID:)) ?? InputDevices.preferredDefaultInputID()
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

    private static let startAttempts = 3
    private static let maxRestarts = 3

    /// Taps the input node and starts the engine, leaving the engine stopped and untapped when it throws.
    private func startCapture(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        // The device's own format, not the node's output format, which can be stale after the device has changed
        // its sample rate: a tap whose rate differs from the device's makes `installTap` raise an Objective-C
        // exception that crashes the app.
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else { throw RecorderError.unsupportedFormat }
        input.installTap(
            onBus: 0, bufferSize: 4096, format: inputFormat,
            block: Self.makeTap(converter: converter, input: inputFormat, target: targetFormat, buffer: buffer))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
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
