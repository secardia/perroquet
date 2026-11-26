import FluidAudio

/// Speech spans from FluidAudio's FSMN-VAD.
public struct FsmnTrimmer: Sendable {
    public let manager: FsmnVadManager

    public init(manager: FsmnVadManager) {
        self.manager = manager
    }

    public static let paddings: [Double] = [0, 0.2, 0.3, 0.5]

    public static func name(padding: Double) -> String { padding == 0 ? "fsmn" : "fsmn-pad\(padding)" }

    /// FSMN-VAD rejects audio shorter than 0.5 s at 16 kHz.
    public static let minimumSamples = 8_000

    /// FluidAudio scores long audio in ~30 s chunks and rejects a last chunk under 0.5 s; on that error the audio is
    /// retried with 0.5 s of trailing silence, which `mergeSpans` clamps away.
    public func spans(_ samples: [Float]) async throws -> [Span] {
        let segments: [FsmnVadSegment]
        do {
            segments = try await manager.detect(audio: samples)
        } catch {
            segments = try await manager.detect(audio: samples + [Float](repeating: 0, count: Self.minimumSamples))
        }
        return segments.map { Span(start: Double($0.startMs) / 1000, end: Double($0.endMs) / 1000) }
    }

    public func padded(_ spans: [Span], by padding: Double) -> [Span] {
        spans.map { Span(start: $0.start - padding, end: $0.end + padding) }
    }
}
