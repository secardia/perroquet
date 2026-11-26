// Speech-trimming bench: transcribes each file after several trimming methods, same ASR settings as the app.
// Usage: trimbench <manifest.json> <outdir> [limit]
// Build in release: the FluidAudio config asserts (padding <= minSpeechDuration) trap in debug builds.
import AVFoundation
import CoreML
import FluidAudio
import Foundation

struct Entry: Decodable {
    let id: String
    let path: String
    let duration: Double
    let ref: String
    let annotatedOnRaw: Bool?

    enum CodingKeys: String, CodingKey {
        case id, path, duration, ref
        case annotatedOnRaw = "annotated_on_raw"
    }
}

struct Row: Encodable {
    let id: String
    let duration: Double
    let keptS: Double
    let segments: Int
    let time: Double
    let hyp: String
    let ref: String
    let annotatedOnRaw: Bool
    let speechOnlyKept = true
    var vadTime: Double?
    var spliceTime: Double?
    var vadModelTime: Double?

    enum CodingKeys: String, CodingKey {
        case id, duration, segments, time, hyp, ref
        case keptS = "kept_s"
        case annotatedOnRaw = "annotated_on_raw"
        case speechOnlyKept = "speech_only_kept"
        case vadTime = "vad_time"
        case spliceTime = "splice_time"
        case vadModelTime = "vad_model_time"
    }
}

struct BenchError: Error, CustomStringConvertible {
    let description: String
}

func loadSamples(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = file.processingFormat
    guard Int(format.sampleRate) == sampleRate, format.channelCount == 1 else {
        throw BenchError(
            description: "\(path): expected 16 kHz mono, got \(format.sampleRate) Hz x \(format.channelCount)")
    }
    guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw BenchError(description: "\(path): cannot allocate \(file.length) frames")
    }
    try file.read(into: buf)
    guard let channel = buf.floatChannelData else { throw BenchError(description: "\(path): no float samples") }
    return Array(UnsafeBufferPointer(start: channel[0], count: Int(buf.frameLength)))
}

func seconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

func runBench() async throws {
    let args = CommandLine.arguments
    let usage = BenchError(description: "usage: trimbench <manifest.json> <outdir> [limit]")
    guard args.count >= 3, args.count <= 4 else { throw usage }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    var manifest = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
    if args.count > 3 {
        guard let limit = Int(args[3]), limit > 0 else { throw usage }
        manifest = Array(manifest.prefix(limit))
    }
    let outDir = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let config = MLModelConfiguration()
    config.computeUnits = .cpuAndNeuralEngine
    let models = try await AsrModels.load(
        from: root.appendingPathComponent("models/coreml"),
        configuration: config,
        version: .v3,
        encoderPrecision: .int8,
        encoderComputeUnits: .cpuAndNeuralEngine
    )
    let asr = AsrManager()
    try await asr.loadModels(models)
    let silero = SileroTrimmer(manager: try await VadManager())
    let fsmn = FsmnTrimmer(manager: try await FsmnVadManager.load())
    let energy = EnergyTrimmer()

    let clock = ContinuousClock()
    func transcribe(_ audio: [Float]) async throws -> (String, Double) {
        guard !audio.isEmpty else { return ("", 0) }
        let t = clock.now
        var state = try TdtDecoderState()
        let r = try await asr.transcribe(audio, decoderState: &state, language: nil)
        return (r.text, seconds(t.duration(to: clock.now)))
    }

    guard !manifest.isEmpty else { throw BenchError(description: "\(args[1]): empty manifest") }
    _ = try await transcribe(try loadSamples(manifest[manifest.count / 2].path))

    var rows: [String: [Row]] = [:]
    func record(_ variant: String, _ e: Entry, samples: [Float], spans: [Span]?, vadTime: Double?,
                modelTime: Double? = nil) async throws {
        let t0 = clock.now
        let spliced = spans.map { splice(samples, spans: $0) }
        let spliceTime = seconds(t0.duration(to: clock.now))
        let audio = spliced?.audio ?? samples
        let (hyp, time) = try await transcribe(audio)
        let fullSeconds = Double(samples.count) / Double(sampleRate)
        var row = Row(
            id: e.id, duration: e.duration, keptS: spliced?.speechSeconds ?? fullSeconds,
            segments: spliced?.segments ?? 1, time: time, hyp: hyp, ref: e.ref,
            annotatedOnRaw: e.annotatedOnRaw ?? false)
        if let vadTime {
            row.vadTime = vadTime
            row.spliceTime = spliceTime
        }
        row.vadModelTime = modelTime
        rows[variant, default: []].append(row)
    }

    for (n, e) in manifest.enumerated() {
        let samples = try loadSamples(e.path)
        try await record("full", e, samples: samples, spans: nil, vadTime: nil)

        var t = clock.now
        let probs = try await silero.probabilities(samples)
        let sileroTime = seconds(t.duration(to: clock.now))
        for c in SileroConfig.all {
            let ts = clock.now
            let spans = await silero.spans(probs, totalSamples: samples.count, config: c)
            let segTime = seconds(ts.duration(to: clock.now))
            try await record(c.name, e, samples: samples, spans: spans,
                             vadTime: sileroTime + segTime, modelTime: sileroTime)
        }

        t = clock.now
        let fsmnSpans = try await fsmn.spans(samples)
        let fsmnTime = seconds(t.duration(to: clock.now))
        for pad in FsmnTrimmer.paddings {
            t = clock.now
            let spans = fsmn.padded(fsmnSpans, by: pad)
            try await record(FsmnTrimmer.name(padding: pad), e, samples: samples, spans: spans,
                             vadTime: fsmnTime + seconds(t.duration(to: clock.now)), modelTime: fsmnTime)
        }

        for c in EnergyConfig.all {
            t = clock.now
            let spans = energy.spans(energy.frameDB(samples), config: c)
            try await record(c.name, e, samples: samples, spans: spans, vadTime: seconds(t.duration(to: clock.now)))
        }
        print("[\(n + 1)/\(manifest.count)] \(e.id)")
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    for (variant, r) in rows {
        try encoder.encode(r).write(to: outDir.appendingPathComponent("\(variant).json"))
    }
    print("done", manifest.count, "files,", rows.count, "variants")
}

try await runBench()
