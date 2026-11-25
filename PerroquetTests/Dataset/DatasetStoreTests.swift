import AVFoundation
import XCTest
@testable import Perroquet

final class DatasetStoreTests: XCTestCase {
    private var root: URL!
    private var store: DatasetStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "PerroquetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = DatasetStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func record() -> TranscriptionRecord {
        TranscriptionRecord(text: "hello world", duration: 1.5, modelIdentifier: "model/x")
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testRootIsSeparatedPerAppName() {
        let support = URL.applicationSupportDirectory
        XCTAssertEqual(
            DatasetStore.root(forApp: "Perroquet Dev").path,
            support.appending(path: "Perroquet Dev/FineTuningDataset").path)
        XCTAssertEqual(
            DatasetStore.root(forApp: "Perroquet").path,
            support.appending(path: "Perroquet/FineTuningDataset").path)
    }

    func testIDFormatAndOrdering() {
        let uuid = UUID()
        let early = RecordingID.make(date: Date(timeIntervalSince1970: 1_800_000_000), uuid: uuid)
        let late = RecordingID.make(date: Date(timeIntervalSince1970: 1_800_000_100), uuid: UUID())
        XCTAssertNotNil(early.range(
            of: #"^\d{8}-\d{6}-[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$"#, options: .regularExpression))
        XCTAssertTrue(early.hasSuffix(uuid.uuidString))
        XCTAssertLessThan(early, late)
    }

    func testDateParsedFromID() throws {
        let date = try XCTUnwrap(RecordingID.date(from: "20261124-180208-BC386AE4-F45A-4B93-BA08-11805B6D1F3E"))
        let parts = Calendar(identifier: .gregorian).dateComponents(
            in: .gmt, from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 11, 24])
        XCTAssertEqual([parts.hour, parts.minute, parts.second], [18, 2, 8])
    }

    func testMakeUsesUTCPrefix() {
        let id = RecordingID.make(date: Date(timeIntervalSince1970: 1_800_000_000), uuid: UUID())
        XCTAssertTrue(id.hasPrefix("20270115-080000-"), id)
    }

    func testDateRoundTripsThroughMake() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let parsed = try XCTUnwrap(RecordingID.date(from: RecordingID.make(date: now)))
        XCTAssertEqual(parsed.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    func testMalformedIDHasNoDate() {
        XCTAssertNil(RecordingID.date(from: "a"))
        XCTAssertNil(RecordingID.date(from: "not-a-valid-id-at-all"))
        XCTAssertNil(RecordingID.date(from: ""))
    }

    func testAddPendingWritesExactlyTheRawFolder() throws {
        let samples = [Float](repeating: 0.25, count: 4_800)
        let recording = try store.addPending(
            samples: samples, transcription: record(), date: Date(timeIntervalSinceReferenceDate: 1_000))
        XCTAssertEqual(recording.status, .pending)
        XCTAssertEqual(recording.audio.lastPathComponent, "audio.flac")
        let names = try FileManager.default.contentsOfDirectory(atPath: recording.folder.path).sorted()
        XCTAssertEqual(names, ["audio.flac", "infos.json", "transcription.txt", "transcription_raw.txt"])
        XCTAssertEqual(try text(recording.folder.appending(path: "transcription_raw.txt")), "hello world")
        XCTAssertEqual(try text(recording.folder.appending(path: "transcription.txt")), "hello world")

        let file = try AVAudioFile(forReading: recording.audio)
        XCTAssertEqual(file.length, 4_800)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.settings[AVFormatIDKey] as? UInt32, kAudioFormatFLAC)

        let infos = try json(recording.folder.appending(path: "infos.json"))
        XCTAssertEqual(Set(infos.keys), ["createdAt", "duration", "modelIdentifier"])
        XCTAssertEqual(infos["modelIdentifier"] as? String, "model/x")
        XCTAssertEqual(infos["duration"] as? Double, 1.5)
        XCTAssertEqual(infos["createdAt"] as? Double, 1_000)
    }

    func testStoredAudioKeepsTheSamples() throws {
        let recording = try store.addPending(samples: [0, 0.5, -0.5], transcription: record())
        let file = try AVAudioFile(forReading: recording.audio, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(file.length, AVAudioFramePosition(FLACEncoder.minimumFrames))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 3))
        try file.read(into: buffer, frameCount: 3)
        let decoded = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(decoded[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded[2], -0.5, accuracy: 0.001)
    }

    func testWAVOnlyLegacyFolderIsStillListed() throws {
        let folder = root.appending(path: "Pending_Recordings/20260101-000000-W", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "audio.wav"))
        XCTAssertEqual(store.list().first?.audio.lastPathComponent, "audio.wav")
    }

    func testValidateMovesAndRewritesTranscription() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        let validated = try store.validate(id: recording.id, text: "fixed")
        XCTAssertEqual(validated.status, .validated)
        XCTAssertEqual(validated.readTranscription(), "fixed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.folder.path))
        XCTAssertEqual(try text(validated.folder.appending(path: "transcription.txt")), "fixed")
        XCTAssertEqual(try text(validated.folder.appending(path: "transcription_raw.txt")), "hello world")
        XCTAssertEqual(store.list().map(\.status), [.validated])
    }

    func testSaveTextKeepsValidatedStatus() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        let validated = try store.validate(id: recording.id, text: "fixed")
        try store.saveText(id: recording.id, text: "fixed again")
        XCTAssertEqual(validated.readTranscription(), "fixed again")
        XCTAssertEqual(store.ids(in: .validated), [recording.id])
        XCTAssertTrue(store.ids(in: .pending).isEmpty)
    }

    func testDeleteRemovesTheRecordingFolder() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        try store.delete(id: recording.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.folder.path))
        XCTAssertTrue(store.list().isEmpty)
    }

    func testDeleteValidatedRecording() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        let validated = try store.validate(id: recording.id, text: "fixed")
        try store.delete(id: recording.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: validated.folder.path))
        XCTAssertTrue(store.list().isEmpty)
    }

    func testDeleteUnknownIDThrows() {
        XCTAssertThrowsError(try store.delete(id: "nope")) {
            XCTAssertEqual($0 as? DatasetStore.StoreError, .recordingNotFound("nope"))
        }
    }

    func testValidateUnknownIDThrows() {
        XCTAssertThrowsError(try store.validate(id: "nope", text: "x")) {
            XCTAssertEqual($0 as? DatasetStore.StoreError, .recordingNotFound("nope"))
        }
    }

    func testMoveOntoExistingDestinationFails() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        let clash = root.appending(path: "Validated_Recordings/\(recording.id)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clash, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.validate(id: recording.id, text: "x"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.folder.path))
    }

    func testListPicksFlacAndIgnoresOriginal() throws {
        let folder = root.appending(path: "Validated_Recordings/20260101-000000-X", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "audio.flac"))
        try Data().write(to: folder.appending(path: "audio_original.wav"))
        try "t".write(to: folder.appending(path: "transcription.txt"), atomically: true, encoding: .utf8)
        let listed = store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.audio.lastPathComponent, "audio.flac")
        XCTAssertEqual(listed.first?.readTranscription(), "t")
    }

    func testListIgnoresHiddenTemporaryFolders() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        let hidden = root.appending(path: "Pending_Recordings/.x.importing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data().write(to: hidden.appending(path: "audio.wav"))
        XCTAssertEqual(store.list().map(\.id), [recording.id])
    }

    func testAddPendingLeavesNoTemporaryFolder() throws {
        try store.addPending(samples: [0], transcription: record())
        let names = try FileManager.default.contentsOfDirectory(
            atPath: root.appending(path: "Pending_Recordings").path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".") })
    }

    func testListSortedByIDAcrossFolders() throws {
        let a = try store.addPending(samples: [0], transcription: record(), id: "20260101-000001-A")
        let b = try store.addPending(samples: [0], transcription: record(), id: "20260101-000002-B")
        try store.validate(id: a.id, text: "x")
        XCTAssertEqual(store.list().map(\.id), [a.id, b.id])
    }
}
