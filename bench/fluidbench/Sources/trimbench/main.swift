// Speech-trimming bench: transcribes each file after several trimming methods, same ASR settings as the app.
// Usage: trimbench <manifest.json> <outdir> [limit] [--only variant,variant...]
// --only transcribes just the named variants (into its own outdir, since progress is kept per outdir).
// Each finished file is appended to <outdir>/progress.jsonl; a rerun with the same outdir skips those files, so a
// crash only loses the file in progress. The per-variant JSON files are written once every file is done.
// Build in release: the FluidAudio config asserts (padding <= minSpeechDuration) trap in debug builds.
import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Trimming

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

struct Row: Codable {
    let id: String
    let duration: Double
    let keptS: Double
    let segments: Int
    let time: Double
    let hyp: String
    let ref: String
    let annotatedOnRaw: Bool
    var speechOnlyKept = true
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

/// One line of progress.jsonl: every variant's row for one file.
struct Progress: Codable {
    let id: String
    let rows: [String: Row]
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
    var args = CommandLine.arguments
    let usage = BenchError(description: "usage: trimbench <manifest.json> <outdir> [limit] [--only variant,...] [--language fr]")
    var only: Set<String>?
    if let i = args.firstIndex(of: "--only") {
        guard i + 1 < args.count else { throw usage }
        only = Set(args[i + 1].split(separator: ",").map(String.init))
        args.removeSubrange(i...(i + 1))
    }
    // Language hint passed to the decoder (FluidAudio's script filter; for French it also blocks English function words).
    var language: Language?
    if let i = args.firstIndex(of: "--language") {
        guard i + 1 < args.count, let l = Language(rawValue: args[i + 1]) else { throw usage }
        language = l
        args.removeSubrange(i...(i + 1))
    }
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
    // The encoder rejects inputs under 0.5 s: a cut that keeps less is padded with trailing silence.
    let minAsrSamples = sampleRate / 2
    func transcribe(_ audio: [Float]) async throws -> (String, Double) {
        guard !audio.isEmpty else { return ("", 0) }
        let t = clock.now
        var state = try TdtDecoderState()
        let padded = audio + [Float](repeating: 0, count: max(0, minAsrSamples - audio.count))
        let r = try await asr.transcribe(padded, decoderState: &state, language: language)
        return (r.text, seconds(t.duration(to: clock.now)))
    }

    guard !manifest.isEmpty else { throw BenchError(description: "\(args[1]): empty manifest") }
    _ = try await transcribe(try loadSamples(manifest[manifest.count / 2].path))

    let progressURL = outDir.appendingPathComponent("progress.jsonl")
    var done: [String: [String: Row]] = [:]
    if let text = try? String(contentsOf: progressURL, encoding: .utf8) {
        // A line cut short by a crash does not decode and its file is redone.
        for line in text.split(separator: "\n") {
            if let p = try? JSONDecoder().decode(Progress.self, from: Data(line.utf8)) { done[p.id] = p.rows }
        }
    }
    if !FileManager.default.fileExists(atPath: progressURL.path) {
        FileManager.default.createFile(atPath: progressURL.path, contents: nil)
    }
    let progress = try FileHandle(forWritingTo: progressURL)
    // Start on a fresh line after a line cut short by a crash.
    if try progress.seekToEnd() > 0, (try? String(contentsOf: progressURL, encoding: .utf8))?.hasSuffix("\n") == false {
        try progress.write(contentsOf: Data("\n".utf8))
    }
    // Keep the log in step with the work when stdout is redirected to a file.
    setvbuf(stdout, nil, _IOLBF, 0)
    print("resuming:", manifest.filter { done[$0.id] != nil }.count, "of", manifest.count, "files already done")

    var rows: [String: Row] = [:]
    func record(_ variant: String, _ e: Entry, samples: [Float], spans: [Span]?, vadTime: Double?,
                modelTime: Double? = nil, silence: Double = 0) async throws {
        if let only, !only.contains(variant) { return }
        let t0 = clock.now
        let spliced = spans.map { splice(samples, spans: $0) }
        let spliceTime = seconds(t0.duration(to: clock.now))
        let edge = [Float](repeating: 0, count: Int(silence * Double(sampleRate)))
        let audio = edge + (spliced?.audio ?? samples) + edge
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
        rows[variant] = row
    }

    for (n, e) in manifest.enumerated() where done[e.id] == nil {
        rows = [:]
        let samples = try loadSamples(e.path)
        try await record("full", e, samples: samples, spans: nil, vadTime: nil)
        for silence in [0.5, 1.0] {
            try await record("full-sil\(silence)", e, samples: samples, spans: nil, vadTime: nil, silence: silence)
        }

        var t = clock.now
        let probs = try await silero.probabilities(samples)
        let sileroTime = seconds(t.duration(to: clock.now))
        for c in SileroConfig.all {
            let ts = clock.now
            let spans = await silero.spans(probs, totalSamples: samples.count, config: c)
            let segTime = seconds(ts.duration(to: clock.now))
            try await record(c.name, e, samples: samples, spans: spans,
                             vadTime: sileroTime + segTime, modelTime: sileroTime)
            guard SileroConfig.withEdgeSilence.contains(c.name) else { continue }
            for silence in [0.5, 1.0] {
                try await record("\(c.name)-edge\(silence)", e, samples: samples, spans: spans,
                                 vadTime: sileroTime + segTime, modelTime: sileroTime, silence: silence)
            }
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
        try progress.write(contentsOf: JSONEncoder().encode(Progress(id: e.id, rows: rows)) + Data("\n".utf8))
        done[e.id] = rows
        print("[\(n + 1)/\(manifest.count)] \(e.id)")
    }
    try progress.close()

    var byVariant: [String: [Row]] = [:]
    for e in manifest {
        for (variant, row) in done[e.id] ?? [:] { byVariant[variant, default: []].append(row) }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    for (variant, r) in byVariant {
        try encoder.encode(r).write(to: outDir.appendingPathComponent("\(variant).json"))
    }
    print("done", manifest.count, "files,", byVariant.count, "variants")
}

try await runBench()
