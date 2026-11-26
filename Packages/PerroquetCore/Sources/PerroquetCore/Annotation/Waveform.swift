import AVFoundation

/// Peak amplitudes of an audio file, for drawing its waveform.
public enum Waveform {
    /// Number of bars of a waveform.
    public static let bucketCount = 100
    private static let chunkFrames: AVAudioFrameCount = 32_768

    /// `bucketCount` peaks in 0…1, each the largest absolute sample of its slice of the file, scaled so the
    /// loudest slice is 1. Empty when the file cannot be read. Runs off the calling actor.
    public static func peaks(of url: URL, buckets: Int = bucketCount) async -> [Float] {
        await Task.detached(priority: .userInitiated) { extract(url, buckets: buckets) }.value
    }

    nonisolated private static func extract(_ url: URL, buckets: Int) -> [Float] {
        guard buckets > 0, let file = try? AVAudioFile(forReading: url), file.length > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames)
        else { return [] }
        let total = file.length
        var peaks = [Float](repeating: 0, count: buckets)
        var position: AVAudioFramePosition = 0
        while position < total {
            do { try file.read(into: buffer, frameCount: chunkFrames) } catch { return [] }
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for index in 0..<count {
                    let bucket = min(buckets - 1, Int((position + AVAudioFramePosition(index)) * AVAudioFramePosition(buckets) / total))
                    let value = abs(samples[index])
                    if value > peaks[bucket] { peaks[bucket] = value }
                }
            }
            position += AVAudioFramePosition(count)
        }
        guard let loudest = peaks.max(), loudest > 0 else { return peaks }
        return peaks.map { $0 / loudest }
    }
}
