import XCTest
@testable import Perroquet

final class WaveformTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appending(path: "WaveformTests-\(UUID().uuidString).flac")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testPeaksFollowTheLoudnessOfEachSlice() async throws {
        let samples = [Float](repeating: 0.1, count: 8_000) + [Float](repeating: 0.5, count: 8_000)
        try FLACEncoder.write(samples: samples, sampleRate: 16_000, to: url)
        let peaks = await Waveform.peaks(of: url, buckets: 10)
        XCTAssertEqual(peaks.count, 10)
        XCTAssertEqual(peaks[0], 0.2, accuracy: 0.01)
        XCTAssertEqual(peaks[9], 1, accuracy: 0.01)
        XCTAssertTrue(peaks.allSatisfy { (0...1).contains($0) })
    }

    func testSilenceStaysFlat() async throws {
        try FLACEncoder.write(samples: [Float](repeating: 0, count: 1_600), sampleRate: 16_000, to: url)
        let peaks = await Waveform.peaks(of: url, buckets: 5)
        XCTAssertEqual(peaks, [0, 0, 0, 0, 0])
    }

    func testUnreadableFileGivesNoPeaks() async {
        let peaks = await Waveform.peaks(of: url, buckets: 5)
        XCTAssertTrue(peaks.isEmpty)
    }
}
