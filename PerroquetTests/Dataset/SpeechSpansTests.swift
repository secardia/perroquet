import XCTest
@testable import Perroquet

final class SpeechSpansTests: XCTestCase {
    func testNothingDetectedGivesNil() {
        XCTAssertNil(SpeechSpans(detected: [], duration: 10))
    }

    func testSegmentsArePaddedAndClampedToTheAudio() throws {
        let spans = try XCTUnwrap(SpeechSpans(detected: [0.2..<2, 9..<9.8], duration: 10))
        XCTAssertEqual(spans.ranges, [0..<3, 8..<10])
    }

    func testOverlappingPaddedSegmentsAreMerged() throws {
        let spans = try XCTUnwrap(SpeechSpans(detected: [3.6..<4, 2..<3, 7..<8], duration: 10))
        XCTAssertEqual(spans.ranges, [1..<5, 6..<9])
    }

    func testPlayableTimeStaysInSpeechAndJumpsOverSilences() throws {
        let spans = try XCTUnwrap(SpeechSpans(detected: [2..<3, 6..<7], duration: 10))
        XCTAssertEqual(spans.playableTime(from: 0), 1)
        XCTAssertEqual(spans.playableTime(from: 2.2), 2.2)
        XCTAssertEqual(spans.playableTime(from: 4.5), 5)
        XCTAssertEqual(spans.playableTime(from: 4), 5)
        XCTAssertNil(spans.playableTime(from: 8.5))
    }

    func testSilencesAreEverythingOutsideTheSpeech() throws {
        let spans = try XCTUnwrap(SpeechSpans(detected: [2..<3, 6..<7], duration: 10))
        XCTAssertEqual(spans.silences(duration: 10), [0..<1, 4..<5, 8..<10])
    }

    func testSplicedJoinsTheSpeechWithShortGaps() throws {
        let rate = DatasetStore.sampleRate
        let samples: [Float] = (0..<8 * rate).map { Float($0) }
        let spans = try XCTUnwrap(SpeechSpans(detected: [1..<2, 6..<7], duration: 8))
        XCTAssertEqual(spans.ranges, [0..<3, 5..<8])
        let spliced = spans.spliced(samples)
        let gap = Int(SpeechSpans.spliceGap * Double(rate))
        XCTAssertEqual(spliced.count, 6 * rate + gap)
        let firstEnd: Int = 3 * rate
        let secondStart: Int = firstEnd + gap
        XCTAssertEqual(Array(spliced[..<firstEnd]), Array(samples[..<firstEnd]))
        XCTAssertEqual(Array(spliced[firstEnd..<secondStart]), [Float](repeating: 0, count: gap))
        XCTAssertEqual(Array(spliced[secondStart...]), Array(samples[(5 * rate)...]))
    }

    func testPausesUpToTwiceThePaddingAreKept() throws {
        let spans = try XCTUnwrap(SpeechSpans(detected: [0..<1, 2.9..<4], duration: 4))
        XCTAssertEqual(spans.ranges, [0..<4])
    }

    func testRoundTripsThroughJSON() throws {
        let spans = try XCTUnwrap(SpeechSpans(detected: [1.23456..<2], duration: 10))
        let decoded = try JSONDecoder().decode(SpeechSpans.self, from: JSONEncoder().encode(spans))
        XCTAssertEqual(decoded, spans)
        XCTAssertEqual(spans.ranges, [0.235..<3])
    }
}
