import FluidAudio

struct FsmnTrimmer {
    let manager: FsmnVadManager

    static let paddings: [Double] = [0, 0.2, 0.3, 0.5]

    static func name(padding: Double) -> String { padding == 0 ? "fsmn" : "fsmn-pad\(padding)" }

    func spans(_ samples: [Float]) async throws -> [Span] {
        try await manager.detect(audio: samples).map {
            Span(start: Double($0.startMs) / 1000, end: Double($0.endMs) / 1000)
        }
    }

    func padded(_ spans: [Span], by padding: Double) -> [Span] {
        spans.map { Span(start: $0.start - padding, end: $0.end + padding) }
    }
}
