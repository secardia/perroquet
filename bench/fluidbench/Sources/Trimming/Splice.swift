import Foundation

/// A time range of the audio, in seconds.
public struct Span: Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Sample rate of every audio handled here, in Hz.
public let sampleRate = 16_000
/// Silence put between two spliced spans, in seconds.
public let spliceGapSeconds = 0.15

/// Clamps spans to the audio, then merges overlapping or adjacent ones.
public func mergeSpans(_ spans: [Span], duration: Double) -> [Span] {
    var merged: [Span] = []
    for s in spans.map({ Span(start: max(0, $0.start), end: min(duration, $0.end)) })
        .filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start })
    {
        if var last = merged.last, s.start <= last.end {
            last.end = max(last.end, s.end)
            merged[merged.count - 1] = last
        } else {
            merged.append(s)
        }
    }
    return merged
}

/// Concatenates the spans separated by 150 ms of zeros, without leading or trailing silence.
public func splice(_ samples: [Float], spans: [Span]) -> (audio: [Float], segments: Int, speechSeconds: Double) {
    let duration = Double(samples.count) / Double(sampleRate)
    let merged = mergeSpans(spans, duration: duration)
    let gap = [Float](repeating: 0, count: Int(spliceGapSeconds * Double(sampleRate)))
    var out: [Float] = []
    var speechSamples = 0
    for (i, s) in merged.enumerated() {
        if i > 0 { out += gap }
        let a = min(samples.count, Int((s.start * Double(sampleRate)).rounded()))
        let b = min(samples.count, Int((s.end * Double(sampleRate)).rounded()))
        out += samples[a..<max(a, b)]
        speechSamples += max(a, b) - a
    }
    return (out, merged.count, Double(speechSamples) / Double(sampleRate))
}
