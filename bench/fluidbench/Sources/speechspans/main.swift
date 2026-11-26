// Writes `speech_spans.json` next to the raw audio of every dataset recording, as the app does for each new
// dictation (same settings as the app's SpeechDetector: Silero VAD, threshold 0.5, 1 s minimum silence, segments
// padded by 1 s, clamped, merged, rounded to the millisecond). The model transcribes these spans spliced together
// and the annotation player skips the silences between them. Format: {"ranges":[[start,end],...]} in seconds.
// Usage: speechspans [--force] <dataset root>...
// Each root is a FineTuningDataset folder. Up-to-date files are skipped unless --force. A recording where no speech
// is detected gets no file, so the app plays it whole.
import AVFoundation
import FluidAudio
import Foundation
import Trimming

struct TrimError: Error, CustomStringConvertible {
    let description: String
}

let padding = 1.0  // SpeechSpans.padding in the app
let hysteresis: Float = 0.15
let threshold: Float = 0.5
// Padding is applied after segmentation, as in the app: same ranges once merged.
let segmentation = VadSegmentationConfig(
    minSpeechDuration: 0.15, minSilenceDuration: 1.0, maxSpeechDuration: 3600, speechPadding: 0,
    silenceThresholdForSplit: max(0.3, threshold - hysteresis), negativeThreshold: threshold - hysteresis,
    negativeThresholdOffset: hysteresis)
let spansFileName = "speech_spans.json"  // SpeechSpans.fileName in the app
let statusFolders = ["Pending_Recordings", "Validated_Recordings"]

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard Int(format.sampleRate) == sampleRate, format.channelCount == 1 else {
        throw TrimError(description: "\(url.path): expected 16 kHz mono, got \(format.sampleRate) Hz")
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw TrimError(description: "\(url.path): cannot allocate buffer")
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else {
        throw TrimError(description: "\(url.path): no float channel data")
    }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

/// Same JSON as the app's `SpeechSpans`: ranges rounded to the millisecond, sorted keys.
struct SpansFile: Encodable {
    let ranges: [[Double]]

    init(_ spans: [Span]) {
        ranges = spans.map { [($0.start * 1000).rounded() / 1000, ($0.end * 1000).rounded() / 1000] }
    }
}

func modificationDate(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
}

/// Raw audio of each recording of the root, by id.
func recordings(in root: URL) -> [String: URL] {
    var found: [String: URL] = [:]
    for status in statusFolders {
        let folder = root.appending(path: status, directoryHint: .isDirectory)
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for id in ids where !id.hasPrefix(".") {
            let audio = ["audio.flac", "audio.wav"].map { folder.appending(path: id).appending(path: $0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            if let audio { found[id] = audio }
        }
    }
    return found
}

func speechSpans(_ samples: [Float], silero: VadManager) async throws -> [Span] {
    let probabilities = try await silero.process(samples)
    return await silero.segmentSpeech(from: probabilities, totalSamples: samples.count, config: segmentation).map {
        Span(start: $0.startTime - padding, end: $0.endTime + padding)
    }
}

func writeSpans(root: URL, force: Bool, silero: VadManager) async {
    let fileManager = FileManager.default
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let sources = recordings(in: root)
    var written = 0, upToDate = 0, noSpeech = 0, failed = 0
    var rawSeconds = 0.0, speechSeconds = 0.0
    for (id, audio) in sources.sorted(by: { $0.key < $1.key }) {
        let folder = audio.deletingLastPathComponent()
        let output = folder.appending(path: spansFileName)
        if !force, let done = modificationDate(output), let source = modificationDate(audio), done >= source {
            upToDate += 1
            continue
        }
        do {
            let samples = try loadSamples(audio)
            let duration = Double(samples.count) / Double(sampleRate)
            let spans = mergeSpans(try await speechSpans(samples, silero: silero), duration: duration)
            if spans.isEmpty {
                try? fileManager.removeItem(at: output)
                noSpeech += 1
                continue
            }
            try encoder.encode(SpansFile(spans)).write(to: output, options: .atomic)
            written += 1
            rawSeconds += duration
            speechSeconds += spans.reduce(0) { $0 + $1.end - $1.start }
        } catch {
            failed += 1
            print("failed \(id): \(error)")
        }
    }
    let skipped = rawSeconds > 0 ? Int((1 - speechSeconds / rawSeconds) * 100) : 0
    print(
        "\(root.path): \(sources.count) recordings, \(written) written (\(skipped)% silence), "
            + "\(upToDate) up to date, \(noSpeech) without speech, \(failed) failed")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let force = arguments.contains("--force")
let roots = arguments.filter { $0 != "--force" }.map { URL(fileURLWithPath: $0, isDirectory: true) }
guard !roots.isEmpty else {
    print("usage: speechspans [--force] <dataset root>...")
    exit(2)
}
let silero = try await VadManager()
for root in roots {
    await writeSpans(root: root, force: force, silero: silero)
}
