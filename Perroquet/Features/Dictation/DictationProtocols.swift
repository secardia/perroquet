import Foundation

/// Turns recorded samples into a transcription.
@MainActor
protocol SpeechTranscribing {
    /// Whether the model is loaded and able to transcribe.
    var isReady: Bool { get }
    /// Transcribes 16 kHz mono samples.
    func transcribe(_ samples: [Float]) async throws -> TranscriptionRecord
}

/// Captures microphone audio as 16 kHz mono Float samples.
@MainActor
protocol AudioRecording {
    /// Starts capturing, asking for microphone access when needed.
    func start() async throws
    /// Stops capturing and returns the samples recorded since `start`.
    func stop() -> [Float]
}

/// Inserts text at the cursor of the frontmost app.
@MainActor
protocol TextPasting {
    /// Pastes `text` into the frontmost app.
    func paste(_ text: String) async throws
}

/// Persists a finished dictation.
protocol RecordingStore: Sendable {
    /// Stores the audio and its transcription.
    func save(samples: [Float], transcription: TranscriptionRecord) throws
    /// Current transcription of the most recent stored recording, or nil when there is none.
    func latestText() -> String?
}
