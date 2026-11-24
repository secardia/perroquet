import Foundation

/// Encodes mono Float samples as 16-bit PCM WAV.
enum WAVEncoder {
    /// Returns a complete WAV file (44-byte header plus samples) for the given mono samples.
    static func encode(samples: [Float], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(Int16((clamped * Float(Int16.max)).rounded()))
        }
        return data
    }
}
