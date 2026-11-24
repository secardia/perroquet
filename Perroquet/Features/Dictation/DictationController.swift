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

    /// Current phase of the pipeline.
    private(set) var state: State = .idle
    /// Text of the last non-empty dictation.
    private(set) var lastText = ""
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
    /// Test hook: pending microphone start, kept so that a quick stop waits for it.
    @ObservationIgnored private(set) var recordingStart: Task<Void, Error>?
    /// Test hook: in-flight transcribe, paste and save task of the last dictation.
    @ObservationIgnored private(set) var pipeline: Task<Void, Never>?

    /// Creates a controller over its collaborators; the mode is restored from `defaults`.
    init(
        recorder: AudioRecording,
        transcriber: SpeechTranscribing,
        paster: TextPasting,
        store: RecordingStore,
        defaults: UserDefaults = .standard
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.paster = paster
        self.store = store
        self.defaults = defaults
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
        state = .recording
        recordingStart = Task { [weak self, recorder] in
            do {
                try await recorder.start()
            } catch {
                self?.recordingFailed(error)
                throw error
            }
        }
    }

    private func recordingFailed(_ error: Error) {
        guard state == .recording else { return }
        message = "Could not start recording: \(error.localizedDescription)"
        state = .idle
    }

    private func endRecording() {
        state = .transcribing
        pipeline = Task {
            let finished = await process()
            state = .idle
            if let finished { await save(finished.samples, finished.record) }
        }
    }

    private func process() async -> (samples: [Float], record: TranscriptionRecord)? {
        do {
            try await recordingStart?.value
        } catch {
            message = "Could not start recording: \(error.localizedDescription)"
            return nil
        }
        let samples = recorder.stop()
        guard !samples.isEmpty else { return nil }

        var record: TranscriptionRecord
        do {
            record = try await transcriber.transcribe(samples)
        } catch {
            message = "Transcription failed: \(error.localizedDescription)"
            return nil
        }
        let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        record.text = text

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
