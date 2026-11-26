import Foundation
import Observation

/// Row details of a recording list (text and audio length), read lazily off the main actor and cached by id.
@MainActor
@Observable
public final class RecordingRows {
    /// Texts read so far, by recording id.
    public private(set) var texts: [String: String] = [:]
    /// Audio lengths read so far, by recording id.
    public private(set) var durations: [String: TimeInterval] = [:]

    /// Reads the text and duration of a row once and caches them.
    public func load(_ recording: DatasetRecording) async {
        guard texts[recording.id] == nil else { return }
        let (text, duration) = await Task.detached { (recording.readTranscription(), recording.readDuration()) }.value
        if texts[recording.id] == nil { texts[recording.id] = text }
        if let duration, durations[recording.id] == nil { durations[recording.id] = duration }
    }

    /// Replaces the cached text of a row.
    func setText(_ text: String, for id: String) {
        texts[id] = text
    }

    /// Forgets one row.
    func remove(_ id: String) {
        texts[id] = nil
        durations[id] = nil
    }

    /// Forgets every row not in `ids`.
    func keep(_ ids: Set<String>) {
        texts = texts.filter { ids.contains($0.key) }
        durations = durations.filter { ids.contains($0.key) }
    }
}
