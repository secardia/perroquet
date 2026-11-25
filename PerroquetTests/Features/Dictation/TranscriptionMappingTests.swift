import FluidAudio
import XCTest
@testable import Perroquet

final class TranscriptionMappingTests: XCTestCase {
    func testMapsResult() {
        let result = ASRResult(text: "Hello world", confidence: 0.75, duration: 2, processingTime: 0.5)
        let record = TranscriptionRecord(result, modelIdentifier: "m")
        XCTAssertEqual(record.text, "Hello world")
        XCTAssertEqual(record.duration, 2)
        XCTAssertEqual(record.modelIdentifier, "m")
    }

    func testDownloadingSummaryShowsPercentage() {
        XCTAssertEqual(Transcriber.State.downloading(0.426).summary, "Downloading… 42%")
    }
}
