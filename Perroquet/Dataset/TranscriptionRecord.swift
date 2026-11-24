import Foundation

/// A transcription outcome to store in the dataset, independent of the ASR engine.
struct TranscriptionRecord: Sendable {
    /// One timed word.
    struct Word: Sendable {
        /// The word as transcribed.
        var text: String
        /// Start offset in the audio, in milliseconds.
        var startMs: Int
        /// End offset in the audio, in milliseconds.
        var endMs: Int
    }

    /// Transcribed text.
    var text: String
    /// Overall confidence reported by the engine.
    var confidence: Double
    /// Audio duration in seconds.
    var duration: TimeInterval
    /// Time spent transcribing, in seconds.
    var processingTime: TimeInterval
    /// Identifier of the model that produced the text.
    var modelIdentifier: String
    /// Word timings, when the engine provides them.
    var words: [Word]?
}
