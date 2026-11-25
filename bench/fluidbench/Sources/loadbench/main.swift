// Load and memory checks of the model, through the same load path as Perroquet's Transcriber.load():
// cache lookup + CoreML load + AsrManager + 1 s warm-up.
//
// Usage:
//   loadbench                one cold load in this process (run it in a fresh process each time)
//   loadbench cycles <n>     n x (load, transcribe 3 clips, unload), with system RAM after each load and unload
//   loadbench steady <n>     load once, then transcribe the whole manifest n times, with RAM every 25 clips
//
// "System" is system-wide used memory (anonymous + wired + compressed pages), the only way to see memory
// held by the ANE outside this process. Nothing else heavy should run at the same time.
import AVFoundation
import CoreML
import Darwin
import FluidAudio
import Foundation

struct Entry: Decodable { let path: String; let duration: Double }

func footprintMB() -> Int {
    var info = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    return Int(info.ri_phys_footprint / 1_048_576)
}

/// Wired memory only: where the ANE driver keeps the model (aned itself stays around 8 MB).
func wiredMB() -> Int { systemPages(\.wire_count) }

func systemUsedMB() -> Int {
    systemPages(\.internal_page_count) + systemPages(\.wire_count) + systemPages(\.compressor_page_count)
}

func systemPages(_ field: KeyPath<vm_statistics64, natural_t>) -> Int {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    return Int(UInt64(stats[keyPath: field]) * 16384 / 1_048_576)
}

/// Median of a few samples over `seconds`, to smooth out other processes.
func settledSystemMB(_ seconds: Double = 2, _ read: () -> Int = systemUsedMB) -> Int {
    var samples: [Int] = []
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        samples.append(read())
        Thread.sleep(forTimeInterval: 0.1)
    }
    return samples.sorted()[samples.count / 2]
}

func loadSamples(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
}

func ms(_ d: Duration) -> Int { Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000) }

func load() async throws -> AsrManager {
    let models = try await AsrModels.downloadAndLoad(
        version: .v3, encoderPrecision: .int8, encoderComputeUnits: .cpuAndNeuralEngine)
    let manager = AsrManager()
    try await manager.loadModels(models)
    var state = try TdtDecoderState()
    _ = try await manager.transcribe([Float](repeating: 0, count: 16000), decoderState: &state, language: nil)
    return manager
}

func transcribe(_ manager: AsrManager, _ samples: [Float]) async throws {
    var state = try TdtDecoderState()
    _ = try await manager.transcribe(samples, decoderState: &state, language: nil)
}

func manifest() throws -> [Entry] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
}

func single() async throws {
    let clock = ContinuousClock()
    let begin = clock.now
    _ = try await load()
    print("load_ms=\(ms(begin.duration(to: clock.now))) process_MB=\(footprintMB())")
}

func cycles(_ n: Int) async throws {
    let entries = try manifest().sorted { $0.duration < $1.duration }
    let clips = try [entries.count / 4, entries.count / 2, entries.count * 3 / 4].map { try loadSamples(entries[$0].path) }
    let clock = ContinuousClock()
    let baseline = settledSystemMB(3)
    let wiredBase = settledSystemMB(3, wiredMB)
    print("baseline_system_MB=\(baseline) baseline_wired_MB=\(wiredBase)")
    for i in 1...n {
        let begin = clock.now
        var manager: AsrManager? = try await load()
        let loadMs = ms(begin.duration(to: clock.now))
        for clip in clips { try await transcribe(manager!, clip) }
        let loaded = settledSystemMB()
        let wiredLoaded = settledSystemMB(1, wiredMB)
        await manager?.cleanup()
        manager = nil
        let unloaded = settledSystemMB()
        let wiredUnloaded = settledSystemMB(1, wiredMB)
        print(
            "cycle \(i): load_ms=\(loadMs) wired loaded=+\(wiredLoaded - wiredBase) unloaded=+\(wiredUnloaded - wiredBase) MB | used loaded=+\(loaded - baseline) unloaded=+\(unloaded - baseline) MB | process=\(footprintMB()) MB"
        )
    }
}

func steady(_ n: Int) async throws {
    let entries = try manifest()
    let baseline = settledSystemMB(3)
    let wiredBase = settledSystemMB(3, wiredMB)
    let manager = try await load()
    print(
        "after_load: wired=+\(settledSystemMB(1, wiredMB) - wiredBase) used=+\(settledSystemMB() - baseline) MB process=\(footprintMB()) MB")
    var done = 0
    var longest = 0.0
    for pass in 1...n {
        for entry in entries {
            try await transcribe(manager, try loadSamples(entry.path))
            done += 1
            longest = max(longest, entry.duration)
            if done % 25 == 0 {
                print(
                    "pass \(pass) clips=\(done) longest_so_far=\(Int(longest)) s wired=+\(settledSystemMB(1, wiredMB) - wiredBase) used=+\(settledSystemMB(1) - baseline) MB process=\(footprintMB()) MB"
                )
            }
        }
    }
}

func run() async throws {
    let args = CommandLine.arguments
    switch args.count > 1 ? args[1] : "" {
    case "cycles": try await cycles(Int(args[2]) ?? 5)
    case "steady": try await steady(Int(args[2]) ?? 1)
    default: try await single()
    }
}

try await run()
