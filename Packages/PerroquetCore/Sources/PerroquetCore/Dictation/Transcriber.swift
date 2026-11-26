import CoreML
import FluidAudio
import Foundation
import Observation

/// Parakeet TDT v3 speech recognition through FluidAudio.
@MainActor
@Observable
public final class Transcriber: SpeechTranscribing {
    /// Model loading progress.
    public enum State: Equatable, Sendable {
        /// Nothing started yet.
        case idle
        /// Fetching the model files, with the completed fraction.
        case downloading(Double)
        /// Compiling and warming up the model.
        case loading
        /// The model can transcribe.
        case ready
        /// Loading failed, with the reason.
        case failed(String)

        /// Short label for status displays.
        public var summary: String {
            switch self {
            case .idle: String(localized: "Waiting", bundle: .module)
            case .downloading(let fraction): String(localized: "Downloading… \(Int(fraction * 100))%", bundle: .module)
            case .loading: String(localized: "Loading…", bundle: .module)
            case .ready: String(localized: "Ready", bundle: .module)
            case .failed(let message): String(localized: "Failed: \(message)", bundle: .module)
            }
        }
    }

    /// Hugging Face repository of the model, stored in `infos.json`.
    static let modelIdentifier = "FluidInference/parakeet-tdt-0.6b-v3-coreml"
    /// Human-readable model and runtime, shown in the Dictation tab.
    static let modelDisplayName = "Parakeet TDT 0.6B v3 · CoreML 6-bit · Neural Engine"
    private static let modelVersion = AsrModelVersion.v3
    // `.int8` selects FluidAudio's default encoder, the 6-bit palettized one.
    private static let encoderPrecision = ParakeetEncoderPrecision.int8
    private static let encoderComputeUnits = MLComputeUnits.cpuAndNeuralEngine
    /// Share of FluidAudio's overall progress taken by the download phase; dividing by it shows the download as 0–100 %.
    private static let downloadPhaseWeight = 0.5

    /// Model loading progress.
    public private(set) var state: State = .idle
    private var manager: AsrManager?

    public init() {}

    /// Whether the model is loaded and warmed up.
    public var isReady: Bool { state == .ready }

    /// Why the last load failed; nil unless it did.
    var failureReason: String? {
        if case .failed(let reason) = state { reason } else { nil }
    }

    /// Relaunches `load()` when the last attempt failed; returns whether it did.
    func retryIfFailed() -> Bool {
        guard case .failed = state else { return false }
        Task { await load() }
        return true
    }

    /// Downloads (first run), loads and warms up the model.
    public func load() async {
        switch state {
        case .idle, .failed: break
        default: return
        }
        state = .downloading(0)
        do {
            let models = try await AsrModels.downloadAndLoad(
                version: Self.modelVersion,
                encoderPrecision: Self.encoderPrecision,
                encoderComputeUnits: Self.encoderComputeUnits,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in self?.apply(progress) }
                })
            state = .loading
            let manager = AsrManager()
            try await manager.loadModels(models)
            var decoderState = try TdtDecoderState()
            _ = try await manager.transcribe(
                [Float](repeating: 0, count: DatasetStore.sampleRate), decoderState: &decoderState, language: nil)
            self.manager = manager
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Transcribes 16 kHz mono samples with a fresh decoder state.
    func transcribe(_ samples: [Float]) async throws -> TranscriptionRecord {
        guard let manager else { throw TranscriberError.notReady }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState, language: nil)
        return TranscriptionRecord(result, modelIdentifier: Self.modelIdentifier)
    }

    private func apply(_ progress: DownloadProgress) {
        guard case .downloading = state else { return }
        switch progress.phase {
        case .compiling: state = .loading
        default: state = .downloading(min(progress.fractionCompleted / Self.downloadPhaseWeight, 1))
        }
    }
}

/// Errors raised by `Transcriber`.
enum TranscriberError: Error {
    /// `transcribe` was called before the model finished loading.
    case notReady
}

extension TranscriptionRecord {
    /// Maps a FluidAudio result.
    init(_ result: ASRResult, modelIdentifier: String) {
        self.init(text: result.text, duration: result.duration, modelIdentifier: modelIdentifier)
    }
}
