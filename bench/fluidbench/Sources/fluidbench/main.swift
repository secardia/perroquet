// CoreML benchmark through FluidAudio.
// Usage: fluidbench <ane|gpu|cpu|all> <encoder: ane|gpu|cpu|all> <int8|int8-v2|int4> <out.json> [limit]
import AVFoundation
import CoreML
import Darwin
import FluidAudio
import Foundation

struct Entry: Decodable { let id: String; let path: String; let duration: Double; let ref: String }

func units(_ s: String) -> MLComputeUnits {
    switch s {
    case "gpu": return .cpuAndGPU
    case "cpu": return .cpuOnly
    case "all": return .all
    default: return .cpuAndNeuralEngine
    }
}

func footprintMB() -> (Double, Double) {
    var info = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    return (Double(info.ri_phys_footprint) / 1_048_576, Double(info.ri_lifetime_max_phys_footprint) / 1_048_576)
}

func loadSamples(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
}

func seconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

func runBench() async throws {
    let args = CommandLine.arguments
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    var manifest = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
    if args.count > 5 { manifest = Array(manifest.prefix(Int(args[5])!)) }

    let memBaseline = footprintMB().0
    let clock = ContinuousClock()
    let t0 = clock.now
    let config = MLModelConfiguration()
    config.computeUnits = units(args[1])
    let models = try await AsrModels.load(
        from: root.appendingPathComponent("models/coreml"),
        configuration: config,
        version: .v3,
        encoderPrecision: ParakeetEncoderPrecision(rawValue: args[3])!,
        encoderComputeUnits: units(args[2])
    )
    let manager = AsrManager()
    try await manager.loadModels(models)
    let loadS = seconds(t0.duration(to: clock.now))
    let memLoaded = footprintMB().0

    let warm = try loadSamples(manifest[manifest.count / 2].path)
    var t1 = clock.now
    var state = try TdtDecoderState()
    _ = try await manager.transcribe(warm, decoderState: &state, language: nil)
    let warmupS = seconds(t1.duration(to: clock.now))

    var rows: [[String: Any]] = []
    for e in manifest {
        let samples = try loadSamples(e.path)
        t1 = clock.now
        var st = try TdtDecoderState()
        let r = try await manager.transcribe(samples, decoderState: &st, language: nil)
        rows.append(["id": e.id, "duration": e.duration, "time": seconds(t1.duration(to: clock.now)), "hyp": r.text, "ref": e.ref])
    }
    let (memAfter, memPeak) = footprintMB()
    let out: [String: Any] = [
        "load_s": loadS, "warmup_s": warmupS, "rows": rows,
        "rss_peak_mb": { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Double(u.ru_maxrss) / 1_048_576 }(),
        "mem_baseline_mb": memBaseline, "mem_loaded_mb": memLoaded, "mem_after_mb": memAfter, "mem_peak_mb": memPeak,
    ]
    try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: args[4]))
    print("done", rows.count)
}

try await runBench()
