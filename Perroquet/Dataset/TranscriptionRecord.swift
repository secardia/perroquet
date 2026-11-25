import Foundation

/// A transcription outcome to store in the dataset, independent of the ASR engine.
struct TranscriptionRecord: Sendable {
    /// Transcribed text.
    var text: String
    /// Audio duration in seconds.
    var duration: TimeInterval
    /// Identifier of the model that produced the text.
    var modelIdentifier: String
}
