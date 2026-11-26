import Foundation
import Trimming

struct EnergyConfig {
    let thresholdDB: Double
    let padding: Double
    let minSilence: Double

    var name: String { "energy-db\(Int(thresholdDB))-pad\(padding)-sil\(minSilence)" }

    static let grid: [EnergyConfig] = [6.0, 10, 15].flatMap { d in
        [0.1, 0.2, 0.3].flatMap { p in [0.3, 0.75].map { EnergyConfig(thresholdDB: d, padding: p, minSilence: $0) } }
    }

    /// Gentler cuts: lower thresholds, wide padding, only long silences removed.
    static let gentle: [EnergyConfig] = [
        (3, 0.3, 0.75), (3, 0.5, 1.5), (4, 0.3, 0.75), (6, 0.5, 0.75), (6, 0.5, 1.5), (6, 0.5, 3.0),
        (8, 0.3, 0.75), (8, 0.5, 0.75), (8, 0.5, 1.5), (6, 0.3, 1.5), (6, 0.3, 2.0), (10, 0.5, 1.5),
    ].map { EnergyConfig(thresholdDB: $0.0, padding: $0.1, minSilence: $0.2) }

    static let all = grid + gentle
}

/// Model-free gate: frames above (10th-percentile noise floor + D dB) are speech.
struct EnergyTrimmer {
    static let frameSeconds = 0.030
    static let hopSeconds = 0.010
    static let minSpeechSeconds = 0.15

    func frameDB(_ samples: [Float]) -> [Double] {
        let win = Int(Self.frameSeconds * Double(sampleRate))
        let hop = Int(Self.hopSeconds * Double(sampleRate))
        guard samples.count >= win else { return [] }
        return stride(from: 0, through: samples.count - win, by: hop).map { i in
            var sum = 0.0
            for j in i..<(i + win) { sum += Double(samples[j]) * Double(samples[j]) }
            return 10 * log10(sum / Double(win) + 1e-10)
        }
    }

    func spans(_ frameDB: [Double], config: EnergyConfig) -> [Span] {
        guard !frameDB.isEmpty else { return [] }
        let floor = frameDB.sorted()[frameDB.count / 10]
        let gate = floor + config.thresholdDB

        var runs: [Span] = []
        var open: Int?
        func close(_ lastFrame: Int) {
            guard let first = open else { return }
            runs.append(Span(
                start: Double(first) * Self.hopSeconds,
                end: Double(lastFrame) * Self.hopSeconds + Self.frameSeconds))
            open = nil
        }
        for (i, db) in frameDB.enumerated() {
            if db >= gate { if open == nil { open = i } } else if open != nil { close(i - 1) }
        }
        close(frameDB.count - 1)

        var merged: [Span] = []
        for r in runs {
            if var last = merged.last, r.start - last.end < config.minSilence {
                last.end = r.end
                merged[merged.count - 1] = last
            } else {
                merged.append(r)
            }
        }
        return merged.filter { $0.end - $0.start >= Self.minSpeechSeconds }
            .map { Span(start: $0.start - config.padding, end: $0.end + config.padding) }
    }
}
