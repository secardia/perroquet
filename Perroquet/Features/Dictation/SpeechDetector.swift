import FluidAudio
import Foundation

/// Finds the speech of a dictation with FluidAudio's Silero VAD: the model transcribes only that speech, and the
/// annotation player skips the rest.
///
/// The model is downloaded and loaded on first use; when that fails, `speechSpans` returns nil (the dictation is
/// then transcribed whole) and the next call retries.
actor SpeechDetector: SpeechDetecting {
    /// Speech starts above this probability (`SpeechSpans.method`).
    private static let threshold: Float = 0.5
    /// Speech ends below `threshold` minus this offset.
    private static let hysteresis: Float = 0.15
    /// Shorter silences stay inside the speech, in seconds.
    private static let minimumSilence: TimeInterval = 1.0

    /// Padding is applied by `SpeechSpans`: FluidAudio's own padding asserts above `minSpeechDuration` in debug
    /// builds, and gives the same ranges once merged.
    private static let segmentation = VadSegmentationConfig(
        minSpeechDuration: 0.15,
        minSilenceDuration: minimumSilence,
        maxSpeechDuration: 3600,
        speechPadding: 0,
        silenceThresholdForSplit: max(0.3, threshold - hysteresis),
        negativeThreshold: threshold - hysteresis,
        negativeThresholdOffset: hysteresis
    )

    private var manager: VadManager?

    /// The speech of 16 kHz mono samples; nil when there is none or the model is unavailable.
    func speechSpans(_ samples: [Float]) async -> SpeechSpans? {
        guard !samples.isEmpty, let manager = await loadedManager(),
            let probabilities = try? await manager.process(samples)
        else { return nil }
        let segments = await manager.segmentSpeech(
            from: probabilities, totalSamples: samples.count, config: Self.segmentation)
        return SpeechSpans(
            detected: segments.map { $0.startTime..<$0.endTime },
            duration: Double(samples.count) / Double(DatasetStore.sampleRate))
    }

    /// Downloads (first run) and loads the model ahead of the first dictation.
    func load() async {
        _ = await loadedManager()
    }

    private func loadedManager() async -> VadManager? {
        if manager == nil { manager = try? await VadManager() }
        return manager
    }
}
