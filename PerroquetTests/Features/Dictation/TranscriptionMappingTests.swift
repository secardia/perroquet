import FluidAudio
import XCTest
@testable import Perroquet

final class TranscriptionMappingTests: XCTestCase {
    func testMapsResultAndGroupsTokensIntoWords() {
        let result = ASRResult(
            text: "Hello world", confidence: 0.75, duration: 2, processingTime: 0.5,
            tokenTimings: [
                TokenTiming(token: "▁Hel", tokenId: 1, startTime: 0.1, endTime: 0.2, confidence: 0.9),
                TokenTiming(token: "lo", tokenId: 2, startTime: 0.2, endTime: 0.4, confidence: 0.9),
                TokenTiming(token: "▁world", tokenId: 3, startTime: 0.5, endTime: 0.9, confidence: 0.9),
            ])
        let record = TranscriptionRecord(result, modelIdentifier: "m")
        XCTAssertEqual(record.text, "Hello world")
        XCTAssertEqual(record.confidence, 0.75)
        XCTAssertEqual(record.duration, 2)
        let words = record.words
        XCTAssertEqual(words?.map(\.text), ["Hello", "world"])
        XCTAssertEqual(words?.first?.startMs, 100)
        XCTAssertEqual(words?.first?.endMs, 400)
    }

    func testNoTokenTimingsMeansNoWords() {
        let result = ASRResult(text: "x", confidence: 1, duration: 1, processingTime: 1)
        XCTAssertNil(TranscriptionRecord(result, modelIdentifier: "m").words)
    }

    func testDownloadingSummaryShowsPercentage() {
        XCTAssertEqual(Transcriber.State.downloading(0.426).summary, "Downloading… 42%")
    }
}
