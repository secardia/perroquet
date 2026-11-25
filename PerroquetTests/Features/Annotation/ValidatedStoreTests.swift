import XCTest
@testable import Perroquet

@MainActor
final class ValidatedStoreTests: XCTestCase {
    private var root: URL!
    private var dataset: DatasetStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "ValidatedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataset = DatasetStore(root: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func addValidated(_ id: String, text: String = "text") throws {
        try dataset.addPending(
            samples: [0],
            transcription: TranscriptionRecord(
                text: "raw \(id)", confidence: 1, duration: 1, processingTime: 0, modelIdentifier: "m"),
            id: id)
        try dataset.validate(id: id, text: text)
    }

    private func loadedStore() async -> ValidatedStore {
        let store = ValidatedStore(dataset: dataset)
        await store.reload()
        return store
    }

    func testOpensOnNewestValidatedOnly() async throws {
        try addValidated("a")
        try addValidated("b")
        try dataset.addPending(
            samples: [0],
            transcription: TranscriptionRecord(
                text: "p", confidence: 1, duration: 1, processingTime: 0, modelIdentifier: "m"),
            id: "c")
        let store = await loadedStore()
        XCTAssertEqual(store.recordings.map(\.id), ["b", "a"])
        XCTAssertEqual(store.selectedID, "b")
        XCTAssertEqual(store.validatedCount, 2)
        XCTAssertFalse(store.takeAutoplayRequest())
    }

    func testEmptyDataset() async {
        let store = await loadedStore()
        XCTAssertNil(store.selectedID)
        XCTAssertNil(store.current)
        XCTAssertEqual(store.validatedCount, 0)
    }

    func testRowTextIsReadLazilyAndCached() async throws {
        try addValidated("a", text: "hello")
        let store = await loadedStore()
        XCTAssertTrue(store.texts.isEmpty)
        let recording = try XCTUnwrap(store.recordings.first)
        await store.loadText(for: recording)
        XCTAssertEqual(store.texts["a"], "hello")
    }

    func testSelectChangesTextAndRequestsAutoplay() async throws {
        try addValidated("a", text: "ta")
        try addValidated("b", text: "tb")
        let store = await loadedStore()
        XCTAssertEqual(store.currentText, "tb")
        store.select("a")
        XCTAssertEqual(store.currentText, "ta")
        XCTAssertTrue(store.takeAutoplayRequest())
        store.select("a")
        XCTAssertFalse(store.takeAutoplayRequest())
    }

    func testSaveRewritesTextKeepsValidatedAndSelectsNextOlder() async throws {
        try addValidated("a", text: "ta")
        try addValidated("b", text: "tb")
        let store = await loadedStore()
        try store.save("fixed")
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertEqual(store.texts["b"], "fixed")
        XCTAssertEqual(store.validatedCount, 2)
        let saved = try XCTUnwrap(dataset.list(in: .validated).first { $0.id == "b" })
        XCTAssertEqual(saved.readTranscription(), "fixed")
    }

    func testSaveOnOldestStaysSelected() async throws {
        try addValidated("a")
        let store = await loadedStore()
        try store.save("fixed")
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertEqual(store.currentText, "fixed")
    }

    func testDeleteSelectsNextOlderThenNewerThenNone() async throws {
        try addValidated("a")
        try addValidated("b")
        try addValidated("c")
        let store = await loadedStore()
        store.select("b")
        try store.delete()
        XCTAssertEqual(store.selectedID, "a")
        XCTAssertEqual(dataset.list(in: .validated).map(\.id), ["a", "c"])
        try store.delete()
        XCTAssertEqual(store.selectedID, "c")
        try store.delete()
        XCTAssertNil(store.selectedID)
        XCTAssertEqual(store.validatedCount, 0)
    }

    func testReloadPicksUpNewValidationAndKeepsSelection() async throws {
        try addValidated("a")
        let store = await loadedStore()
        try addValidated("b")
        await store.reload()
        XCTAssertEqual(store.recordings.map(\.id), ["b", "a"])
        XCTAssertEqual(store.selectedID, "a")
    }
}
