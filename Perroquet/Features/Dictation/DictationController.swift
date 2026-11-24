import Foundation
import Observation

/// Coordinates recording, transcription, pasting and dataset storage.
@MainActor
@Observable
final class DictationController {
    /// Phase of the dictation pipeline.
    enum State: Equatable {
        /// Waiting for the shortcut.
        case idle
        /// The microphone is capturing.
        case recording
        /// Transcribing and pasting the last recording.
        case transcribing

        /// SF Symbol shown in the menu bar.
        var menuBarSymbol: String {
            switch self {
            case .idle: "waveform"
            case .recording: "mic.fill"
            case .transcribing: "ellipsis"
            }
        }
    }

    /// UserDefaults key under which the recording mode is stored.
    private static let modeDefaultsKey = "recordingMode"

    /// SF Symbol shown in the menu bar: the cross right after a cancel, otherwise the one of `state`.
    var menuBarSymbol: String {
        state == .idle && showsCancelled ? "xmark" : state.menuBarSymbol
    }

    /// Current phase of the pipeline.
    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    /// Text of the last non-empty dictation.
    private(set) var lastText = ""
    /// Whether a cancelled dictation is still being acknowledged in the menu bar.
    private(set) var showsCancelled = false
    /// Last problem or reason a shortcut press was ignored.
    private(set) var message: String?

    /// How the shortcut drives recording; persisted on change.
    var mode: RecordingMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey) }
    }

    private let recorder: AudioRecording
    private let transcriber: SpeechTranscribing
    private let paster: TextPasting
    private let store: RecordingStore
    private let defaults: UserDefaults
    private let cancelledDuration: Duration
    /// Called on the main actor each time `state` changes.
    @ObservationIgnored var onStateChange: ((State) -> Void)?
    /// Incremented when a dictation starts or is cancelled, so a stale pipeline cannot touch the current one.
    @ObservationIgnored private var generation = 0
    /// Test hook: completes once the recorder of the previous dictation is released; a new recording waits for it.
    @ObservationIgnored private(set) var recorderRelease: Task<Void, Never>?
    /// Test hook: pending microphone start, kept so that a quick stop waits for it.
    @ObservationIgnored private(set) var recordingStart: Task<Void, Error>?
    /// Test hook: timer ending the cancelled acknowledgement.
    @ObservationIgnored private(set) var cancelledMark: Task<Void, Never>?
    /// Test hook: in-flight transcribe, paste and save task of the last dictation.
    @ObservationIgnored private(set) var pipeline: Task<Void, Never>?

    /// Creates a controller over its collaborators; the mode is restored from `defaults`.
    init(
        recorder: AudioRecording,
        transcriber: SpeechTranscribing,
        paster: TextPasting,
        store: RecordingStore,
        defaults: UserDefaults = .standard,
        cancelledDuration: Duration = .seconds(1)
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.paster = paster
        self.store = store
        self.defaults = defaults
        self.cancelledDuration = cancelledDuration
        lastText = store.latestText() ?? ""
        mode = defaults.string(forKey: Self.modeDefaultsKey).flatMap(RecordingMode.init) ?? .tap
    }

    /// Shortcut pressed.
    func hotkeyDown() {
        switch state {
        case .idle:
            beginRecording()
        case .recording where mode == .tap:
            endRecording()
        case .recording, .transcribing:
            break
        }
    }

    /// Shortcut released.
    func hotkeyUp() {
        if state == .recording, mode == .hold {
            endRecording()
        }
    }

    private func beginRecording() {
        guard transcriber.isReady else {
            message = "The model is not ready yet."
            return
        }
        message = nil
        cancelledMark?.cancel()
        showsCancelled = false
        generation += 1
        let id = generation
        let release = recorderRelease
        state = .recording
        recordingStart = Task { [weak self, recorder] in
            await release?.value
            do {
                try await recorder.start()
            } catch {
                self?.recordingFailed(error, generation: id)
                throw error
            }
        }
    }

    /// Abandons the dictation in progress: nothing is pasted, stored or shown. No-op when idle.
    func cancel() {
        switch state {
        case .idle:
            return
        case .recording:
            let start = recordingStart
            recorderRelease = Task { [recorder] in
                _ = try? await start?.value
                _ = recorder.stop()
            }
        case .transcribing:
            break
        }
        generation += 1
        state = .idle
        showsCancelled = true
        cancelledMark?.cancel()
        cancelledMark = Task { [cancelledDuration] in
            try? await Task.sleep(for: cancelledDuration)
            guard !Task.isCancelled else { return }
            showsCancelled = false
        }
    }

    private func recordingFailed(_ error: Error, generation id: Int) {
        guard state == .recording, id == generation else { return }
        message = "Could not start recording: \(error.localizedDescription)"
        state = .idle
    }

    private func endRecording() {
        state = .transcribing
        let id = generation
        let start = recordingStart
        let stopped = Task { [recorder] () -> [Float]? in
            do {
                try await start?.value
            } catch {
                if id == generation { message = "Could not start recording: \(error.localizedDescription)" }
                return nil
            }
            return recorder.stop()
        }
        recorderRelease = Task { _ = await stopped.value }
        pipeline = Task {
            let finished = await process(await stopped.value, generation: id)
            if id == generation { state = .idle }
            if let finished { await save(finished.samples, finished.record) }
        }
    }

    private func process(
        _ samples: [Float]?, generation id: Int
    ) async -> (samples: [Float], record: TranscriptionRecord)? {
        guard let samples, !samples.isEmpty else { return nil }

        var record: TranscriptionRecord
        do {
            record = try await transcriber.transcribe(samples)
        } catch {
            if id == generation { message = "Transcription failed: \(error.localizedDescription)" }
            return nil
        }
        guard id == generation else { return nil }
        let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        record.text = text

        state = .idle
        lastText = text
        do {
            try await paster.paste(text)
        } catch {
            message = "Could not paste: \(error.localizedDescription)"
        }
        return (samples, record)
    }

    private func save(_ samples: [Float], _ record: TranscriptionRecord) async {
        let store = store
        do {
            try await Task.detached { try store.save(samples: samples, transcription: record) }.value
        } catch {
            message = "Could not save the recording: \(error.localizedDescription)"
        }
    }
}
