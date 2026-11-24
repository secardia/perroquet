import Foundation

/// A recording folder found in the dataset.
struct DatasetRecording: Identifiable, Equatable, Sendable {
    /// Folder name, `yyyyMMdd-HHmmss-<UUID>`.
    let id: String
    /// Review state, given by the containing folder.
    let status: RecordingStatus
    /// The recording folder.
    let folder: URL
    /// `audio.wav` or `audio.flac`, never `audio_original.*`.
    let audio: URL

    /// Reads `transcription.txt` from disk ("" when unreadable).
    func readTranscription() -> String {
        (try? String(contentsOf: folder.appending(path: "transcription.txt"), encoding: .utf8)) ?? ""
    }
}
