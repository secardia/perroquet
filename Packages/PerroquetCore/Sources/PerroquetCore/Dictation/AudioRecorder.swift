import AVFoundation
import CoreAudio
import os
import Synchronization

/// Records the chosen microphone, or the system default, as 16 kHz mono Float32 samples.
///
/// One input-only unit is kept for the chosen device and only paused between dictations: it stays initialized but
/// the hardware I/O is stopped, so nothing is captured and no microphone indicator shows, while the next `start`
/// skips the cold start of creating and initializing the unit. The unit never opens the output device. Bluetooth
/// microphones are the exception: capturing from them switches the headset to its low-quality call profile, so no
/// unit is kept between dictations.
@MainActor
public final class AudioRecorder: AudioRecording {
    /// Reasons recording cannot start.
    enum RecorderError: LocalizedError {
        /// Microphone access was refused.
        case microphoneDenied
        /// No converter exists from the microphone format to 16 kHz mono.
        case unsupportedFormat
        /// No input device is available.
        case noMicrophone

        /// Message shown to the user.
        var errorDescription: String? {
            switch self {
            case .microphoneDenied: String(localized: "Microphone access is denied.", bundle: .module)
            case .unsupportedFormat: String(localized: "The microphone format is not supported.", bundle: .module)
            case .noMicrophone: String(localized: "No microphone is available.", bundle: .module)
            }
        }
    }

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(DatasetStore.sampleRate), channels: 1, interleaved: false)!
    private let buffer = SampleBuffer()
    /// Unit kept between dictations, with the device it was made for.
    private var current: (unit: InputUnit, device: AudioDeviceID?)?
    private var isRecording = false
    /// Times the running unit was restarted after a format change during this dictation.
    private var restarts = 0
    private let selectedUID: () -> String?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Perroquet", category: "recorder")

    /// `selectedUID` returns the UID of the chosen microphone; nil or an unplugged device means the system default,
    /// or the built-in microphone when the default is a Bluetooth headset.
    public init(selectedUID: @escaping () -> String? = { nil }) {
        self.selectedUID = selectedUID
    }

    /// Prepares a unit for the target device when microphone access is granted, unless one is already kept for it or
    /// it is a Bluetooth headset; call it at launch and whenever the chosen microphone changes.
    public func prepare() {
        guard !isRecording, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            let device = targetDevice(), current?.device != device
        else { return }
        current?.unit.dispose()
        current = nil
        guard !InputDevices.isBluetooth(device) else { return }
        let clock = ContinuousClock()
        let begin = clock.now
        do {
            let unit = try makeUnit(device: device)
            _ = try unit.configure()
            current = (unit, device)
            logger.notice("Prepared audio unit in \(Self.milliseconds(begin.duration(to: clock.now))) ms")
        } catch {
            logger.error("Could not prepare audio unit: \(error.localizedDescription)")
        }
    }

    /// Starts capturing, asking for microphone access when needed.
    func start() async throws {
        guard await Self.requestMicrophoneAccess() else { throw RecorderError.microphoneDenied }
        buffer.reset()

        let clock = ContinuousClock()
        let begin = clock.now
        let device = targetDevice()
        let previous = current
        current = nil
        let kept = previous.flatMap { $0.device == device ? $0.unit : nil }
        if kept == nil { previous?.unit.dispose() }
        let (unit, attempts) = try startUnit(device: device, kept: kept)
        current = (unit, device)
        restarts = 0
        isRecording = true
        logger.notice(
            "Started recording in \(Self.milliseconds(begin.duration(to: clock.now))) ms (kept unit: \(kept != nil), attempts: \(attempts))")
    }

    /// Stops capturing and returns the samples recorded since `start`. The unit is paused rather than released,
    /// so it stays prepared for the next `start`, except on a Bluetooth headset, which it releases.
    func stop() -> [Float] {
        if isRecording, let (unit, device) = current {
            if let device, InputDevices.isBluetooth(device) {
                unit.dispose()
                current = nil
            } else {
                unit.pause()
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

    /// Restarts the recording unit in the device's current format after a format change notification. On every
    /// notification: it can arrive before the unit's cached format updates, and a Bluetooth headset then stops
    /// delivering audio about two seconds later. Only restarts that find a different format count toward the cap.
    private func formatChanged(_ changed: InputUnit) {
        guard isRecording, let unit = current?.unit, changed === unit else { return }
        if unit.needsConfigure {
            guard restarts < Self.maxRestarts else {
                unit.pause()
                logger.error("Audio format keeps changing; capture stopped")
                return
            }
            restarts += 1
        }
        unit.pause()
        do {
            let format = try startCapture(on: unit)
            logger.notice("Restarted recording after a format change (\(format.sampleRate) Hz)")
        } catch {
            logger.error("Could not restart recording: \(error.localizedDescription)")
        }
    }

    /// The chosen microphone when connected, else the system default input, Bluetooth headsets excepted.
    private func targetDevice() -> AudioDeviceID? {
        selectedUID().flatMap(InputDevices.deviceID(forUID:)) ?? InputDevices.preferredDefaultInputID()
    }

    private func makeUnit(device: AudioDeviceID?) throws -> InputUnit {
        let unit: InputUnit
        do {
            unit = try InputUnit(device: device)
        } catch let failure as InputUnit.Failure {
            throw Self.recorderError(for: failure)
        }
        unit.onFormatChange = { [weak self, weak unit] in
            guard let unit else { return }
            self?.formatChanged(unit)
        }
        return unit
    }

    private static let startAttempts = 3
    private static let maxRestarts = 3

    /// Starts the kept unit, or a fresh one, retrying on a fresh unit; returns the running unit and attempts used.
    /// A Bluetooth headset can switch to its call profile, at a lower sample rate, while the unit starts, which then
    /// fails with a format error. A fresh unit made right away reads the new format; waiting would let the headset
    /// fall back to its music profile.
    private func startUnit(device: AudioDeviceID?, kept: InputUnit?) throws -> (unit: InputUnit, attempts: Int) {
        var candidate = kept
        var attempt = 1
        while true {
            do {
                let unit = try candidate ?? makeUnit(device: device)
                candidate = unit
                try startCapture(on: unit)
                return (unit, attempt)
            } catch {
                candidate?.dispose()
                candidate = nil
                guard attempt < Self.startAttempts else { throw error }
                logger.notice("Start attempt \(attempt) failed (\(error.localizedDescription)), retrying")
                attempt += 1
            }
        }
    }

    /// Configures the unit for the device's current format and starts it, leaving it paused when it throws.
    @discardableResult
    private func startCapture(on unit: InputUnit) throws -> AVAudioFormat {
        let configuration: InputUnit.Configuration
        do {
            configuration = try unit.configure()
        } catch let failure as InputUnit.Failure {
            throw Self.recorderError(for: failure)
        }
        let inputFormat = configuration.format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.unsupportedFormat
        }
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(configuration.maxFrames) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw RecorderError.unsupportedFormat
        }
        try unit.start(handler: Self.makeHandler(converter: converter, out: out, buffer: buffer))
        return inputFormat
    }

    private static func recorderError(for failure: InputUnit.Failure) -> RecorderError {
        failure == .noInputDevice ? .noMicrophone : .unsupportedFormat
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private nonisolated static func makeHandler(
        converter: AVAudioConverter, out: AVAudioPCMBuffer, buffer: SampleBuffer
    ) -> (AVAudioPCMBuffer) -> Void {
        { pcm in
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
    /// About a minute of audio, so appending from the audio thread rarely reallocates.
    private static let reservedSamples = DatasetStore.sampleRate * 60

    func reset() {
        samples.withLock {
            $0.removeAll(keepingCapacity: true)
            $0.reserveCapacity(Self.reservedSamples)
        }
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
