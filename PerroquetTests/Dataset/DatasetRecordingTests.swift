import XCTest
@testable import Perroquet

final class DatasetRecordingTests: XCTestCase {
    private var root: URL!
    private var dataset: DatasetStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "RecordingDurationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataset = DatasetStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func addPending(samples: Int, reportedDuration: TimeInterval) throws -> DatasetRecording {
        try dataset.addPending(
            samples: [Float](repeating: 0, count: samples),
            transcription: TranscriptionRecord(
                text: "t", confidence: 1, duration: reportedDuration, processingTime: 0, modelIdentifier: "m"),
            id: "a")
    }

    func testDurationComesFromInfos() throws {
        let recording = try addPending(samples: 16000, reportedDuration: 7.5)
        XCTAssertEqual(try XCTUnwrap(recording.readDuration()), 7.5, accuracy: 0.001)
    }

    func testDurationFallsBackToTheAudioFile() throws {
        let recording = try addPending(samples: 32000, reportedDuration: 99)
        try FileManager.default.removeItem(at: recording.folder.appending(path: "infos.json"))
        XCTAssertEqual(try XCTUnwrap(recording.readDuration()), 2, accuracy: 0.01)
    }

    func testDurationIsNilWhenNothingIsReadable() throws {
        let recording = try addPending(samples: 16000, reportedDuration: 1)
        try FileManager.default.removeItem(at: recording.folder.appending(path: "infos.json"))
        try FileManager.default.removeItem(at: recording.audio)
        XCTAssertNil(recording.readDuration())
    }
}
