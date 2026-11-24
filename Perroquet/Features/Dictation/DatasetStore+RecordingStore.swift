import Foundation

extension DatasetStore: RecordingStore {
    /// Stores the dictation as a pending recording.
    func save(samples: [Float], transcription: TranscriptionRecord) throws {
        try addPending(samples: samples, transcription: transcription)
    }

    /// Current transcription of the recording with the greatest id.
    func latestText() -> String? {
        latest()?.readTranscription()
    }
}
