import FluidAudio
import Trimming

struct SileroConfig {
    let threshold: Float
    let padding: Double
    let minSilence: Double

    var name: String { "silero-t\(threshold)-pad\(padding)-sil\(minSilence)" }

    static let grid: [SileroConfig] = [Float(0.5), 0.7, 0.85].flatMap { t in
        [0.1, 0.2, 0.3].flatMap { p in [0.3, 0.75].map { SileroConfig(threshold: t, padding: p, minSilence: $0) } }
    }

    /// Gentler cuts: low threshold, wide padding, only long silences removed.
    static let gentle: [SileroConfig] = [
        (0.3, 0.3, 0.75), (0.3, 0.5, 0.75), (0.3, 0.5, 1.5), (0.5, 0.5, 0.75), (0.5, 0.5, 1.5), (0.5, 0.5, 3.0),
        (0.7, 0.5, 0.75), (0.7, 0.5, 1.5), (0.7, 0.5, 3.0), (0.5, 1.0, 1.0), (0.5, 0.3, 2.0), (0.85, 0.5, 1.5),
    ].map { SileroConfig(threshold: Float($0.0), padding: $0.1, minSilence: $0.2) }

    static let all = grid + gentle
    /// Also run with 0.5 s and 1 s of silence added before and after the spliced speech.
    static let withEdgeSilence: Set<String> = ["silero-t0.5-pad1.0-sil1.0"]
}

struct SileroTrimmer {
    let manager: VadManager
    private static let hysteresisOffset: Float = 0.15

    /// Runs the model once per file; the probabilities are reused for every config.
    func probabilities(_ samples: [Float]) async throws -> [VadResult] {
        try await manager.process(samples)
    }

    /// Release builds only: padding above minSpeechDuration (0.15) trips a debug assert in FluidAudio.
    /// The entry threshold is negativeThreshold + offset, so pinning the negative one gives `threshold`.
    func spans(_ results: [VadResult], totalSamples: Int, config: SileroConfig) async -> [Span] {
        let negative = config.threshold - Self.hysteresisOffset
        let seg = VadSegmentationConfig(
            minSpeechDuration: 0.15,
            minSilenceDuration: config.minSilence,
            maxSpeechDuration: 3600,
            speechPadding: config.padding,
            silenceThresholdForSplit: max(0.3, negative),
            negativeThreshold: negative,
            negativeThresholdOffset: Self.hysteresisOffset
        )
        let segments = await manager.segmentSpeech(from: results, totalSamples: totalSamples, config: seg)
        return segments.map { Span(start: $0.startTime, end: $0.endTime) }
    }
}
