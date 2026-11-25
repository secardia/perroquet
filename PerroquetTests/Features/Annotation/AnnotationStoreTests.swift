import XCTest
@testable import Perroquet

private final class Gate: @unchecked Sendable {
    var isBlocking = false
}

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
                text: text ?? "raw \(id)", duration: 1,
                modelIdentifier: "m"),
            id: id)
    }

    private func store(pageSize: Int = RecordingPage.defaultSize) async -> AnnotationStore {
        let session = AnnotationStore(dataset: dataset, pageSize: pageSize)
        await session.reload()
        return session
    }

    func testOpensOnNewestPendingOnly() async throws {
        try add("a")
        try add("b")
        try add("c")
        try dataset.validate(id: "c", text: "done")
        let session = await store()
        XCTAssertEqual(session.recordings.map(\.id), ["b", "a"])
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.pendingCount, 2)
    }

    func testOpensWithVerbatimText() async throws {
        try add("a")
        try add("b", text: "hello\n")
        try dataset.validate(id: "a", text: "done")
        let session = await store()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.currentText, "hello\n")
        XCTAssertEqual(session.recordings.count, 1)
    }

    func testPendingCountDropsAfterValidation() async throws {
        try add("b")
        try add("a")
        let session = await store()
        XCTAssertEqual(session.pendingCount, 2)
        try session.save("fixed")
        XCTAssertEqual(session.pendingCount, 1)
    }

    func testSaveValidatesAndAdvancesToNextOlderPending() async throws {
        try add("b")
        try add("a")
        let session = await store()
        try session.save("fixed b")
        XCTAssertEqual(session.current?.id, "a")
        let first = try XCTUnwrap(dataset.list().first { $0.id == "b" })
        XCTAssertEqual(first.status, .validated)
        XCTAssertEqual(first.readTranscription(), "fixed b")
    }

    func testSaveOnOldestWrapsToNewestThenEnds() async throws {
        try add("a")
        try add("b")
        try add("c")
        let session = await store()
        session.select("a")
        XCTAssertEqual(session.current?.id, "a")
        try session.save("A")
        XCTAssertEqual(session.current?.id, "c")
        try session.save("C")
        try session.save("B")
        XCTAssertNil(session.current)
    }

    func testValidatedRecordingNeverComesBack() async throws {
        try add("c")
        try add("b")
        try add("a")
        let session = await store()
        try session.save("C")
        XCTAssertEqual(session.current?.id, "b")
        session.select("a")
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.recordings.map(\.id), ["b", "a"])
    }

    func testSelectMovesWithoutSaving() async throws {
        try add("c", text: "tc")
        try add("b", text: "tb")
        try add("a", text: "ta")
        let session = await store()
        session.select("b")
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.currentText, "tb")
        session.select("a")
        XCTAssertEqual(session.current?.id, "a")
        session.select("c")
        XCTAssertEqual(session.current?.id, "c")
        XCTAssertEqual(session.pendingCount, 3)
        XCTAssertTrue(dataset.list().allSatisfy { $0.status == .pending })
    }

    func testDeleteRemovesFromDiskAndAdvances() async throws {
        let first = try add("b")
        try add("a")
        let session = await store()
        try session.delete()
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.recordings.map(\.id), ["a"])
        XCTAssertEqual(dataset.list().map(\.id), ["a"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.folder.path))
    }

    func testAllReviewedLeavesNothingCurrent() async throws {
        try add("b")
        try add("a")
        let session = await store()
        try session.save("x")
        try session.delete()
        XCTAssertNil(session.current)
        XCTAssertEqual(session.pendingCount, 0)
        XCTAssertNil(session.current)
    }

    func testReloadPicksUpNewPendingAfterAllDone() async throws {
        try add("a")
        let session = await store()
        try session.save("A")
        XCTAssertNil(session.current)
        try add("b")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertEqual(session.recordings.count, 1)
    }

    func testReloadJumpsToNewestWhenNewDictationArrives() async throws {
        try add("a")
        let session = await store()
        try add("b")
        try add("c")
        await session.reload()
        XCTAssertEqual(session.current?.id, "c")
        XCTAssertEqual(session.recordings.count, 3)
    }

    func testReloadWithoutNewRecordingKeepsCurrent() async throws {
        try add("a")
        try add("b")
        let session = await store()
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
        let session = await store()
        try session.save("C")
        XCTAssertEqual(session.current?.id, "b")
        try dataset.validate(id: "a", text: "done")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
    }

    func testStoreErrorLeavesPositionUnchanged() async throws {
        let first = try add("b")
        try add("a")
        let session = await store()
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
        let session = await store()
        XCTAssertFalse(session.takeAutoplayRequest())
        await session.reload()
        XCTAssertFalse(session.takeAutoplayRequest())

        try session.save("D")
        XCTAssertTrue(session.takeAutoplayRequest())
        XCTAssertFalse(session.takeAutoplayRequest())

        try session.delete()
        XCTAssertTrue(session.takeAutoplayRequest())

        session.select("a")
        XCTAssertTrue(session.takeAutoplayRequest())

        session.select("b")
        XCTAssertTrue(session.takeAutoplayRequest())
    }

    func testNoAutoplayWhenPositionDoesNotChange() async throws {
        try add("a")
        let session = await store()
        session.select("a")
        XCTAssertFalse(session.takeAutoplayRequest())
        try session.save("A")
        XCTAssertNil(session.current)
        XCTAssertFalse(session.takeAutoplayRequest())
    }

    func testNoAutoplayWhenReloadOpensNewPending() async throws {
        try add("a")
        let session = await store()
        try session.save("A")
        _ = session.takeAutoplayRequest()
        try add("b")
        await session.reload()
        XCTAssertEqual(session.current?.id, "b")
        XCTAssertFalse(session.takeAutoplayRequest())
    }

    func testTextStaysCorrectAfterSaveDeleteNavigation() async throws {
        try add("c", text: "tc")
        try add("b", text: "tb")
        try add("a", text: "ta")
        let session = await store()
        try session.save("C fixed")
        XCTAssertEqual(session.currentText, "tb")
        try session.delete()
        XCTAssertEqual(session.currentText, "ta")
        XCTAssertNil(session.recordings.first { $0.id == "c" })
        XCTAssertEqual(session.current?.id, "a")
    }

    func testReloadDuringSaveKeepsInMemoryUpdate() async throws {
        try add("a")
        try add("b")
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let gate = Gate()
        let session = AnnotationStore(dataset: dataset) { dataset in
            let snapshot = dataset.ids(in: .pending)
            guard gate.isBlocking else { return snapshot }
            entered.continuation.yield()
            for await _ in release.stream { break }
            return snapshot
        }
        await session.reload()
        gate.isBlocking = true
        try add("c")
        let reloading = Task { await session.reload() }
        for await _ in entered.stream { break }
        try session.save("C")
        release.continuation.yield()
        await reloading.value
        XCTAssertNil(session.recordings.first { $0.id == "b" })
        XCTAssertNotEqual(session.current?.id, "b")
    }

    func testEmptyDataset() async {
        let session = await store()
        XCTAssertNil(session.current)
        XCTAssertNil(session.current)
        XCTAssertEqual(session.pendingCount, 0)
    }

    func testSelectGoesToThatPendingRecordingAndRequestsAutoplay() async throws {
        try add("a", text: "ta")
        try add("b", text: "tb")
        let session = await store()
        XCTAssertEqual(session.current?.id, "b")
        session.select("a")
        XCTAssertEqual(session.current?.id, "a")
        XCTAssertEqual(session.currentText, "ta")
        XCTAssertTrue(session.takeAutoplayRequest())
        session.select("a")
        XCTAssertFalse(session.takeAutoplayRequest())
        session.select("unknown")
        XCTAssertEqual(session.current?.id, "a")
    }

    func testFirstPageIsLoadedAndCountComesFromTheFolderListing() async throws {
        for index in 0..<7 { try add("r\(index)") }
        let session = await store(pageSize: 3)
        XCTAssertEqual(session.recordings.map(\.id), ["r6", "r5", "r4"])
        XCTAssertEqual(session.pendingCount, 7)
        XCTAssertTrue(session.hasMore)
    }

    func testLoadMoreAppendsTheNextPage() async throws {
        for index in 0..<7 { try add("r\(index)") }
        let session = await store(pageSize: 3)
        session.loadMore()
        XCTAssertEqual(session.recordings.map(\.id), ["r6", "r5", "r4", "r3", "r2", "r1"])
        session.loadMore()
        XCTAssertEqual(session.recordings.count, 7)
        XCTAssertFalse(session.hasMore)
    }

    func testSaveOnTheLastLoadedRowAdvancesIntoTheNextPage() async throws {
        for index in 0..<4 { try add("r\(index)") }
        let session = await store(pageSize: 2)
        session.select("r2")
        try session.save("done")
        XCTAssertEqual(session.current?.id, "r1")
        XCTAssertEqual(session.pendingCount, 3)
    }

    func testFolderWithoutAudioIsSkippedWhenItsPageLoads() async throws {
        for index in 0..<4 { try add("r\(index)") }
        let broken = dataset.root.appending(path: "Pending_Recordings/r2")
        try FileManager.default.removeItem(at: broken.appending(path: "audio.flac"))
        let session = await store(pageSize: 2)
        XCTAssertEqual(session.pendingCount, 4)
        session.loadMore()
        XCTAssertEqual(session.recordings.map(\.id), ["r3", "r1", "r0"])
    }
}
