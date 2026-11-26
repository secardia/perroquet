import AVFoundation

/// Writes mono Float samples as a 16-bit FLAC file.
enum FLACEncoder {
    /// Errors raised while encoding.
    enum EncodeError: Error {
        /// The sample buffer could not be allocated.
        case bufferUnavailable
    }

    /// Frames in one FLAC block; the system encoder produces an unreadable file for anything shorter.
    static let minimumFrames = 4_608

    /// Writes `samples` (mono, -1...1) to `url` as 16-bit FLAC at `sampleRate`.
    ///
    /// Audio shorter than one FLAC block is padded with silence up to `minimumFrames`.
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
        ]
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let frames = max(samples.count, minimumFrames)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
            let channel = buffer.int16ChannelData?[0]
        else { throw EncodeError.bufferUnavailable }
        for index in 0..<frames {
            let sample = index < samples.count ? max(-1, min(1, samples[index])) : 0
            channel[index] = Int16((sample * Float(Int16.max)).rounded())
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        try file.write(from: buffer)
    }
}
