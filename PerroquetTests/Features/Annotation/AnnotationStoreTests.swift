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

    func testOpensOnNewestPendingOnly() throws {
        try add("a")
        try add("b")
        try add("c")
        try dataset.validate(id: "c", text: "done")
        let session = store()
        XCTAssertEqual(session.recordings.map(\.id), ["b", "a"])
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.pendingCount, 2)
    }

    func testOpensWithVerbatimText() throws {
        try add("a")
        try add("b", text: "hello\n")
        try dataset.validate(id: "a", text: "done")
        let session = store()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.currentText, "hello\n")
        XCTAssertEqual(session.recordings.count, 1)
    }

    func testPendingCountDropsAfterValidation() throws {
        try add("b")
        try add("a")
        let session = store()
        XCTAssertEqual(session.pendingCount, 2)
        try session.save("fixed")
        XCTAssertEqual(session.pendingCount, 1)
    }

    func testSaveValidatesAndAdvancesToNextOlderPending() throws {
        try add("b")
        try add("a")
        let session = store()
        try session.save("fixed b")
        XCTAssertEqual(session.current?.id, "a")
        let first = try XCTUnwrap(dataset.list().first { $0.id == "b" })
        XCTAssertEqual(first.status, .validated)
        XCTAssertEqual(first.readTranscription(), "fixed b")
    }

    func testSaveOnOldestWrapsToNewestThenEnds() throws {
        try add("a")
        try add("b")
        try add("c")
        let session = store()
        session.next()
        session.next()
        XCTAssertEqual(session.current?.id, "a")
        try session.save("A")
        XCTAssertEqual(session.current?.id, "c")
        try session.save("C")
        try session.save("B")
        XCTAssertNil(session.current)
    }

    func testValidatedRecordingNeverComesBack() throws {
        try add("c")
        try add("b")
        try add("a")
        let session = store()
        try session.save("C")
        XCTAssertEqual(session.current?.id, "b")
        session.previous()
        XCTAssertEqual(session.current?.id, "b")
        session.next()
        session.next()
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.recordings.map(\.id), ["b", "a"])
    }

    func testNextAndPreviousMoveWithoutSaving() throws {
        try add("c", text: "tc")
        try add("b", text: "tb")
        try add("a", text: "ta")
        let session = store()
        session.next()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.currentText, "tb")
        session.next()
        XCTAssertEqual(session.current?.id, "a")
        session.next()
        XCTAssertEqual(session.current?.id, "a")
        session.previous()
        session.previous()
        XCTAssertEqual(session.current?.id, "c")
        session.previous()
        XCTAssertEqual(session.current?.id, "c")
        XCTAssertEqual(session.pendingCount, 3)
        XCTAssertTrue(dataset.list().allSatisfy { $0.status == .pending })
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

    func testAllReviewedLeavesNothingCurrent() throws {
        try add("b")
        try add("a")
        let session = store()
        try session.save("x")
        try session.delete()
        XCTAssertNil(session.current)
        XCTAssertEqual(session.pendingCount, 0)
        session.previous()
        session.next()
        XCTAssertNil(session.current)
    }

    func testReloadPicksUpNewPendingAfterAllDone() async throws {
        try add("a")
        let session = store()
        try session.save("A")
        XCTAssertNil(session.current)
        try add("b")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.recordings.count, 1)
    }

    func testReloadJumpsToNewestWhenNewDictationArrives() async throws {
        try add("a")
        let session = store()
        try add("b")
        try add("c")
        await session.reload()
        XCTAssertEqual(session.current?.id, "c")
        XCTAssertEqual(session.recordings.count, 3)
    }

    func testReloadWithoutNewRecordingKeepsCurrent() async throws {
        try add("a")
        try add("b")
        let session = store()
        XCTAssertEqual(session.current?.id, "b")
        try dataset.validate(id: "a", text: "done")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.pendingCount, 1)
    }

    func testReloadAfterSaveDoesNotJumpBackToNewest() async throws {
        try add("a")
        try add("b")
        try add("c")
        let session = store()
        try session.save("C")
        XCTAssertEqual(session.current?.id, "b")
        try dataset.validate(id: "a", text: "done")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
    }

    func testStoreErrorLeavesPositionUnchanged() throws {
        let first = try add("b")
        try add("a")
        let session = store()
        let clash = root.appending(path: "Validated_Recordings/b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clash, withIntermediateDirectories: true)
        XCTAssertThrowsError(try session.save("x"))
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.pendingCount, 2)
        XCTAssertEqual(first.readTranscription(), "raw b")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.folder.path))
    }

    func testAutoplayOnlyAfterExplicitNavigation() async throws {
        try add("d")
        try add("c")
        try add("b")
        try add("a")
        let session = store()
        XCTAssertFalse(session.takeAutoplayRequest())
        await session.reload()
        XCTAssertFalse(session.takeAutoplayRequest())

        try session.save("D")
        XCTAssertTrue(session.takeAutoplayRequest())
        XCTAssertFalse(session.takeAutoplayRequest())

        try session.delete()
        XCTAssertTrue(session.takeAutoplayRequest())

        session.next()
        XCTAssertTrue(session.takeAutoplayRequest())

        session.previous()
        XCTAssertTrue(session.takeAutoplayRequest())
    }

    func testNoAutoplayWhenPositionDoesNotChange() throws {
        try add("a")
        let session = store()
        session.previous()
        session.next()
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

    func testTextStaysCorrectAfterSaveDeleteNavigation() throws {
        try add("c", text: "tc")
        try add("b", text: "tb")
        try add("a", text: "ta")
        let session = store()
        try session.save("C fixed")
        XCTAssertEqual(session.currentText, "tb")
        try session.delete()
        XCTAssertEqual(session.currentText, "ta")
        session.previous()
        XCTAssertNil(session.recordings.first { $0.id == "c" })
        XCTAssertEqual(session.current?.id, "a")
    }

    func testReloadDuringSaveKeepsInMemoryUpdate() async throws {
        try add("a")
        try add("b")
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let session = AnnotationStore(dataset: dataset) { dataset in
            let snapshot = dataset.list().reversed().filter { $0.status == .pending }
            entered.continuation.yield()
            for await _ in release.stream { break }
            return snapshot
        }
        try add("c")
        let reloading = Task { await session.reload() }
        for await _ in entered.stream { break }
        try session.save("C")
        release.continuation.yield()
        await reloading.value
        XCTAssertNil(session.recordings.first { $0.id == "b" })
        XCTAssertNotEqual(session.current?.id, "b")
    }

    func testEmptyDataset() {
        let session = store()
        XCTAssertNil(session.current)
        session.previous()
        session.next()
        XCTAssertNil(session.current)
        XCTAssertEqual(session.pendingCount, 0)
    }
}
