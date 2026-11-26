import Foundation

/// Parts of a recording that hold speech, in seconds of the raw audio: sorted, disjoint, never empty.
///
/// The model transcribes these ranges spliced together (`spliced(_:)`), and they are stored as `speech_spans.json`
/// next to the raw audio, so the annotation player skips exactly what the model did not hear while the waveform
/// keeps the whole recording. Settings from the silence-trimming bench (`bench/RESULTS.md`): Silero VAD speech,
/// padded by 1 s on each side, so only pauses over 2 s are shortened.
public struct SpeechSpans: Codable, Equatable, Sendable {
    /// File name in the recording folder.
    static let fileName = "speech_spans.json"
    /// Bench name of the trimming, stored in `infos.json` of a recording transcribed from the spliced audio.
    static let method = "silero-t0.5-pad1.0-sil1.0"
    /// Audio kept on each side of a detected speech segment, in seconds.
    static let padding: TimeInterval = 1.0
    /// Silence put between two spliced ranges, in seconds.
    static let spliceGap: TimeInterval = 0.15
    /// Below this distance a skip is not worth a seek, in seconds.
    static let skipTolerance: TimeInterval = 0.02

    /// Speech ranges in seconds.
    let ranges: [Range<TimeInterval>]

    /// Pads the detected segments, clamps them to `duration`, merges the overlapping ones and rounds to the
    /// millisecond; nil when nothing is left.
    init?(detected: [Range<TimeInterval>], duration: TimeInterval) {
        let padded = detected.map {
            Self.round(max(0, $0.lowerBound - Self.padding))..<Self.round(min(duration, $0.upperBound + Self.padding))
        }
        var merged: [Range<TimeInterval>] = []
        for range in padded.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        guard !merged.isEmpty else { return nil }
        ranges = merged
    }

    /// Where playback at `time` goes on when silences are skipped: `time` itself inside speech, the start of the
    /// next speech range in a silence, nil after the last one.
    func playableTime(from time: TimeInterval) -> TimeInterval? {
        guard let next = ranges.first(where: { time < $0.upperBound }) else { return nil }
        return max(time, next.lowerBound)
    }

    /// The speech ranges of 16 kHz mono `samples` joined by `spliceGap` of silence: the audio the model transcribes.
    func spliced(_ samples: [Float]) -> [Float] {
        let rate = Double(DatasetStore.sampleRate)
        let gap = [Float](repeating: 0, count: Int(Self.spliceGap * rate))
        var out: [Float] = []
        for (index, range) in ranges.enumerated() {
            let start = min(samples.count, Int((range.lowerBound * rate).rounded()))
            let end = min(samples.count, Int((range.upperBound * rate).rounded()))
            if index > 0 { out += gap }
            out += samples[start..<max(start, end)]
        }
        return out
    }

    /// The silences of a recording of `duration` seconds: everything outside the speech ranges.
    public func silences(duration: TimeInterval) -> [Range<TimeInterval>] {
        var silences: [Range<TimeInterval>] = []
        var start: TimeInterval = 0
        for range in ranges {
            if range.lowerBound > start { silences.append(start..<range.lowerBound) }
            start = max(start, range.upperBound)
        }
        if duration > start { silences.append(start..<duration) }
        return silences
    }

    private static func round(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 1000).rounded() / 1000
    }
}
