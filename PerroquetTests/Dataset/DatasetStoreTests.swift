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

    private func record(words: [TranscriptionRecord.Word]? = nil) -> TranscriptionRecord {
        TranscriptionRecord(
            text: "hello world", confidence: 0.9, duration: 1.5, processingTime: 0.2,
            modelIdentifier: "model/x", words: words)
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

    func testAddPendingWritesAllFiles() throws {
        let words = [TranscriptionRecord.Word(text: "hello", startMs: 0, endMs: 300)]
        let recording = try store.addPending(samples: [0, 0.5, -0.5, 1], transcription: record(words: words))
        XCTAssertEqual(recording.status, .pending)
        for name in ["audio.wav", "transcription_raw.txt", "transcription.txt", "infos.json", "metadata.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: recording.folder.appending(path: name).path), name)
        }
        XCTAssertEqual(try text(recording.folder.appending(path: "transcription_raw.txt")), "hello world")
        XCTAssertEqual(try text(recording.folder.appending(path: "transcription.txt")), "hello world")

        let wav = try Data(contentsOf: recording.audio)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(wav.subdata(in: 22..<24), Data([1, 0]))
        XCTAssertEqual(wav.subdata(in: 24..<28), Data([0x80, 0x3E, 0, 0]))
        XCTAssertEqual(wav.count, 44 + 8)

        let infos = try json(recording.folder.appending(path: "infos.json"))
        XCTAssertEqual(infos["provider"] as? String, "local")
        XCTAssertEqual(infos["modelIdentifier"] as? String, "model/x")
        XCTAssertEqual(infos["textLength"] as? Int, 11)
        XCTAssertEqual(infos["words"] as? Int, 1)
        XCTAssertNotNil(infos["md5"])
        XCTAssertNil(infos["language"])

        let metadata = try json(recording.folder.appending(path: "metadata.json"))
        XCTAssertEqual(metadata["audio_duration_ms"] as? Int, 1500)
        let metaWords = try XCTUnwrap(metadata["words"] as? [[String: Any]])
        XCTAssertEqual(metaWords.first?["word"] as? String, "hello")
        XCTAssertEqual(metaWords.first?["end_ms"] as? Int, 300)
        XCTAssertNotNil(metadata["timestamp"] as? String)
        XCTAssertNil(metadata["language"])
    }

    func testWordsOmittedWhenUnknown() throws {
        let recording = try store.addPending(samples: [0], transcription: record())
        XCTAssertNil(try json(recording.folder.appending(path: "infos.json"))["words"])
        XCTAssertNil(try json(recording.folder.appending(path: "metadata.json"))["words"])
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
        XCTAssertEqual(store.list(in: .validated).map(\.id), [recording.id])
        XCTAssertTrue(store.list(in: .pending).isEmpty)
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
