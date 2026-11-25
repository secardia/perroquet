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
                text: "raw \(id)", duration: 1, modelIdentifier: "m"),
            id: id)
        try dataset.validate(id: id, text: text)
    }

    private func loadedStore(pageSize: Int = RecordingPage.defaultSize) async -> ValidatedStore {
        let store = ValidatedStore(dataset: dataset, pageSize: pageSize)
        await store.reload()
        return store
    }

    func testOpensOnNewestValidatedOnly() async throws {
        try addValidated("a")
        try addValidated("b")
        try dataset.addPending(
            samples: [0],
            transcription: TranscriptionRecord(
                text: "p", duration: 1, modelIdentifier: "m"),
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
        XCTAssertTrue(store.rows.texts.isEmpty)
        let recording = try XCTUnwrap(store.recordings.first)
        await store.rows.load(recording)
        XCTAssertEqual(store.rows.texts["a"], "hello")
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
        XCTAssertEqual(store.rows.texts["b"], "fixed")
        XCTAssertEqual(store.validatedCount, 2)
        let saved = try XCTUnwrap(dataset.recording(id: "b", status: .validated))
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
        XCTAssertEqual(dataset.ids(in: .validated), ["c", "a"])
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

    func testFirstPageCountAndLoadMore() async throws {
        for index in 0..<5 { try addValidated("r\(index)") }
        let store = await loadedStore(pageSize: 2)
        XCTAssertEqual(store.recordings.map(\.id), ["r4", "r3"])
        XCTAssertEqual(store.validatedCount, 5)
        store.loadMore()
        XCTAssertEqual(store.recordings.map(\.id), ["r4", "r3", "r2", "r1"])
        XCTAssertTrue(store.hasMore)
    }

    func testDeleteCrossesThePageBoundary() async throws {
        for index in 0..<4 { try addValidated("r\(index)") }
        let store = await loadedStore(pageSize: 2)
        XCTAssertEqual(store.recordings.count, 2)
        store.select("r2")
        try store.delete()
        XCTAssertEqual(store.selectedID, "r1")
        XCTAssertEqual(store.recordings.count, 3)
        XCTAssertEqual(store.validatedCount, 3)
    }
}
