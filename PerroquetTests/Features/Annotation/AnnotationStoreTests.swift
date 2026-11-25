import XCTest
@testable import Perroquet

@MainActor
final class AnnotationStoreTests: XCTestCase {
    private var root: URL!
    private var dataset: DatasetStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "AnnotationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataset = DatasetStore(root: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func add(_ id: String, text: String? = nil) throws -> DatasetRecording {
        try dataset.addPending(
            samples: [0],
            transcription: TranscriptionRecord(
                text: text ?? "raw \(id)", confidence: 1, duration: 1, processingTime: 0,
                modelIdentifier: "m"),
            id: id)
    }

    private func store() -> AnnotationStore { AnnotationStore(dataset: dataset) }

    func testOpensOnNewestPending() throws {
        try add("a")
        try add("b")
        try add("c")
        try dataset.validate(id: "c", text: "done")
        let session = store()
        XCTAssertEqual(session.recordings.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(session.current?.id, "b")
    }

    func testSaveGoesToNextOlderPendingThenWrapsToNewest() throws {
        try add("a")
        try add("b")
        try add("c")
        let session = store()
        XCTAssertEqual(session.current?.id, "c")
        try session.save("C")
        XCTAssertEqual(session.current?.id, "b")
        session.previous()
        XCTAssertEqual(session.current?.id, "c")
        _ = session.takeAutoplayRequest()
        session.previous()
        XCTAssertEqual(session.current?.id, "c")
        XCTAssertFalse(session.takeAutoplayRequest())
        try session.save("again")
        XCTAssertEqual(session.current?.id, "b")
        try session.save("B")
        XCTAssertEqual(session.current?.id, "a")
        session.previous()
        XCTAssertEqual(session.current?.id, "b")
        session.previous()
        session.previous()
        try session.save("again")
        XCTAssertEqual(session.current?.id, "a")
    }

    func testSavingWithNoOlderPendingWrapsToNewestPending() async throws {
        try add("a")
        let session = store()
        try add("b")
        try add("c")
        await session.reload()
        XCTAssertEqual(session.current?.id, "a")
        try session.save("A")
        XCTAssertEqual(session.current?.id, "c")
    }

    func testOpensOnFirstPendingWithVerbatimText() throws {
        try add("a")
        try add("b", text: "hello\n")
        try dataset.validate(id: "a", text: "done")
        let session = store()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.currentText, "hello\n")
        XCTAssertEqual(session.validatedCount, 1)
        XCTAssertEqual(session.recordings.count, 2)
    }

    func testSaveValidatesAndAdvancesToNextPending() throws {
        try add("b")
        try add("a")
        let session = store()
        try session.save("fixed a")
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.validatedCount, 1)
        let first = try XCTUnwrap(dataset.list().first { $0.id == "b" })
        XCTAssertEqual(first.status, .validated)
        XCTAssertEqual(first.readTranscription(), "fixed a")
    }

    func testDeleteRemovesFromDiskAndAdvances() throws {
        let first = try add("b")
        try add("a")
        let session = store()
        try session.delete()
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.recordings.map(\.id), ["a"])
        XCTAssertEqual(dataset.list().map(\.id), ["a"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.folder.path))
    }

    func testAllDoneThenPreviousGoesToLast() throws {
        try add("b")
        try add("a")
        let session = store()
        try session.save("x")
        try session.delete()
        XCTAssertNil(session.current)
        XCTAssertEqual(session.validatedCount, 1)
        XCTAssertEqual(session.recordings.count, 1)
        session.previous()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.current?.status, .validated)
    }

    func testPreviousSkipsDeletedAndResaveValidated() async throws {
        try add("c")
        try add("b")
        try add("a")
        let session = store()
        try session.save("A")
        try session.delete()
        XCTAssertEqual(session.current?.id, "a")
        session.previous()
        XCTAssertEqual(session.current?.id, "c")
        XCTAssertEqual(session.currentText, "A")
        session.previous()
        XCTAssertEqual(session.current?.id, "c")

        await session.reload()
        try session.save("A2")
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(dataset.list().first { $0.id == "c" }?.readTranscription(), "A2")
        XCTAssertNil(dataset.list().first { $0.id == "b" })
    }

    func testDeleteValidatedReachedByPrevious() throws {
        try add("b")
        try add("a")
        let session = store()
        try session.save("B")
        session.previous()
        XCTAssertEqual(session.current?.id, "b")
        try session.delete()
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(dataset.list().map(\.id), ["a"])
    }

    func testResaveBackInTheMiddleReturnsToPending() throws {
        try add("c")
        try add("b")
        try add("a")
        let session = store()
        try session.save("A")
        XCTAssertEqual(session.current?.id, "b")
        session.previous()
        try session.save("A again")
        XCTAssertEqual(session.current?.id, "b")
    }

    func testReloadPicksUpNewPendingAfterAllDone() async throws {
        try add("a")
        let session = store()
        try session.save("A")
        XCTAssertNil(session.current)
        try add("b")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.recordings.count, 2)
    }

    func testReloadKeepsCurrentWhenNewDictationArrives() async throws {
        try add("a")
        let session = store()
        try add("b")
        await session.reload()
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.recordings.count, 2)
    }

    func testStoreErrorLeavesPositionUnchanged() throws {
        let first = try add("b")
        try add("a")
        let session = store()
        let clash = root.appending(path: "Validated_Recordings/b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clash, withIntermediateDirectories: true)
        XCTAssertThrowsError(try session.save("x"))
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(first.readTranscription(), "raw b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.folder.path))
    }

    func testAutoplayOnlyAfterExplicitNavigation() async throws {
        try add("c")
        try add("b")
        try add("a")
        let session = store()
        XCTAssertFalse(session.takeAutoplayRequest())
        await session.reload()
        XCTAssertFalse(session.takeAutoplayRequest())

        try session.save("A")
        XCTAssertTrue(session.takeAutoplayRequest())
        XCTAssertFalse(session.takeAutoplayRequest())

        try session.delete()
        XCTAssertTrue(session.takeAutoplayRequest())

        session.previous()
        XCTAssertTrue(session.takeAutoplayRequest())
    }

    func testNoAutoplayWhenPositionDoesNotChange() throws {
        try add("a")
        let session = store()
        session.previous()
        XCTAssertFalse(session.takeAutoplayRequest())
        try session.save("A")
        XCTAssertNil(session.current)
        XCTAssertFalse(session.takeAutoplayRequest())
    }

    func testNoAutoplayWhenReloadOpensNewPending() async throws {
        try add("a")
        let session = store()
        try session.save("A")
        _ = session.takeAutoplayRequest()
        try add("b")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertFalse(session.takeAutoplayRequest())
    }

    func testTextStaysCorrectAfterSaveDeletePrevious() throws {
        try add("c", text: "tc")
        try add("b", text: "tb")
        try add("a", text: "ta")
        let session = store()
        try session.save("A fixed")
        XCTAssertEqual(session.currentText, "tb")
        try session.delete()
        XCTAssertEqual(session.currentText, "ta")
        session.previous()
        XCTAssertEqual(session.currentText, "A fixed")
        XCTAssertEqual(session.recordings.first?.readTranscription(), "A fixed")
    }

    func testReloadDuringSaveKeepsInMemoryUpdate() async throws {
        try add("a")
        try add("b")
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let session = AnnotationStore(dataset: dataset) { dataset in
            let snapshot = Array(dataset.list().reversed())
            entered.continuation.yield()
            for await _ in release.stream { break }
            return snapshot
        }
        try add("c")
        let reloading = Task { await session.reload() }
        for await _ in entered.stream { break }
        try session.save("B")
        release.continuation.yield()
        await reloading.value
        XCTAssertEqual(session.recordings.first { $0.id == "b" }?.status, .validated)
        XCTAssertNotEqual(session.current?.id, "b")
    }

    func testEmptyDataset() {
        let session = store()
        XCTAssertNil(session.current)
        session.previous()
        XCTAssertNil(session.current)
        XCTAssertEqual(session.validatedCount, 0)
    }
}
