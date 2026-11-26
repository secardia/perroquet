import AVFoundation
import Foundation

/// A recording folder found in the dataset.
public struct DatasetRecording: Identifiable, Equatable, Sendable {
    /// Folder name, `yyyyMMdd-HHmmss-<UUID>`.
    public let id: String
    /// Review state, given by the containing folder.
    let status: RecordingStatus
    /// The recording folder.
    let folder: URL
    /// `audio.wav` or `audio.flac`, never `audio_original.*`.
    public let audio: URL

    /// Speech of the audio from `speech_spans.json` (written at save time or by `bench/speech_spans.sh`);
    /// nil when the folder has none or it is unreadable.
    public func readSpeechSpans() -> SpeechSpans? {
        guard let data = try? Data(contentsOf: folder.appending(path: SpeechSpans.fileName)) else { return nil }
        return try? JSONDecoder().decode(SpeechSpans.self, from: data)
    }

    private struct Infos: Decodable {
        let duration: TimeInterval
    }

    /// Reads `transcription.txt` from disk ("" when unreadable).
    func readTranscription() -> String {
        (try? String(contentsOf: folder.appending(path: "transcription.txt"), encoding: .utf8)) ?? ""
    }

    /// Audio length in seconds: `duration` of `infos.json`, else the length of the audio file; nil when neither is readable.
    func readDuration() -> TimeInterval? {
        if let data = try? Data(contentsOf: folder.appending(path: "infos.json")),
            let infos = try? JSONDecoder().decode(Infos.self, from: data)
        {
            return infos.duration
        }
        guard let file = try? AVAudioFile(forReading: audio), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
