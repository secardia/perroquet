import Foundation

/// Turns recorded samples into a transcription.
@MainActor
protocol SpeechTranscribing {
    /// Whether the model is loaded and able to transcribe.
    var isReady: Bool { get }
    /// Why the last model load failed; nil unless it failed.
    var failureReason: String? { get }
    /// Relaunches model loading when the previous attempt failed; returns whether it did.
    func retryIfFailed() -> Bool
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

/// Finds the speech of a dictation: the model transcribes only it, and the annotation player skips the rest.
protocol SpeechDetecting: Sendable {
    /// The speech of 16 kHz mono samples; nil when there is none or detection is unavailable.
    func speechSpans(_ samples: [Float]) async -> SpeechSpans?
}

/// Persists a finished dictation.
protocol RecordingStore: Sendable {
    /// Stores the raw audio, its speech spans when known, and its transcription.
    func save(samples: [Float], speechSpans: SpeechSpans?, transcription: TranscriptionRecord) throws
    /// Current transcription of the most recent stored recording, or nil when there is none.
    func latestText() -> String?
}
