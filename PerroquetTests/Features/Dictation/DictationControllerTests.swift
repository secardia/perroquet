import XCTest
@testable import Perroquet

@MainActor
final class DictationControllerTests: XCTestCase {
    private final class Fakes {
        var ready = true
        var samples: [Float] = [0.1, 0.2]
        var text = " hello "
        var events: [String] = []
        var pasted: [String] = []
        var saved: [TranscriptionRecord] = []
        var transcribeError: Error?
        var recordError: Error?
        var storeError: Error?
        var latest: String?
        var holdTranscription = false
        var onPaste: (() -> Void)?
        var transcriptionGate: CheckedContinuation<Void, Never>?
    }

    private struct Recorder: AudioRecording {
        let fakes: Fakes
        func start() async throws {
            if let error = fakes.recordError { throw error }
            fakes.events.append("start")
        }
        func stop() -> [Float] { fakes.events.append("stop"); return fakes.samples }
    }

    private struct Transcribe: SpeechTranscribing {
        let fakes: Fakes
        var isReady: Bool { fakes.ready }
        func transcribe(_ samples: [Float]) async throws -> TranscriptionRecord {
            if fakes.holdTranscription {
                await withCheckedContinuation { fakes.transcriptionGate = $0 }
            }
            if let error = fakes.transcribeError { throw error }
            return TranscriptionRecord(
                text: fakes.text, confidence: 1, duration: 1, processingTime: 0.1, modelIdentifier: "m")
        }
    }

    private struct Paste: TextPasting {
        let fakes: Fakes
        func paste(_ text: String) async throws {
            fakes.pasted.append(text)
            fakes.onPaste?()
        }
    }

    private struct Store: RecordingStore, @unchecked Sendable {
        let fakes: Fakes
        func save(samples: [Float], transcription: TranscriptionRecord) throws {
            if let error = fakes.storeError { throw error }
            fakes.saved.append(transcription)
        }
        func latestText() -> String? { fakes.latest }
    }

    private func make(
        mode: RecordingMode? = nil, latest: String? = nil, defaults: UserDefaults? = nil,
        cancelledDuration: Duration = .seconds(1)
    ) -> (DictationController, Fakes) {
        let fakes = Fakes()
        fakes.latest = latest
        let defaults = defaults ?? makeDefaults()
        let controller = DictationController(
            recorder: Recorder(fakes: fakes), transcriber: Transcribe(fakes: fakes), paster: Paste(fakes: fakes),
            store: Store(fakes: fakes), defaults: defaults,
            cancelledDuration: cancelledDuration)
        if let mode { controller.mode = mode }
        return (controller, fakes)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func settle(_ controller: DictationController) async {
        await controller.pipeline?.value
    }

    func testTapTogglesAndPastesAndStores() async {
        let (controller, fakes) = make(mode: .tap)
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .recording)
        controller.hotkeyUp()
        XCTAssertEqual(controller.state, .recording)
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .transcribing)
        await settle(controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(fakes.events, ["start", "stop"])
        XCTAssertEqual(fakes.pasted, ["hello"])
        XCTAssertEqual(fakes.saved.map(\.text), ["hello"])
        XCTAssertEqual(controller.lastText, "hello")
    }

    func testHoldStartsOnDownStopsOnUp() async {
        let (controller, fakes) = make(mode: .hold)
        controller.hotkeyDown()
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .recording)
        controller.hotkeyUp()
        XCTAssertEqual(controller.state, .transcribing)
        await settle(controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(fakes.events, ["start", "stop"])
        XCTAssertEqual(fakes.pasted, ["hello"])
    }

    func testIgnoredWhileTranscribing() async {
        let (controller, fakes) = make(mode: .tap)
        controller.hotkeyDown()
        controller.hotkeyDown()
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .transcribing)
        await settle(controller)
        XCTAssertEqual(fakes.events, ["start", "stop"])
    }

    func testIgnoredWhenModelNotReady() {
        let (controller, fakes) = make(mode: .tap)
        fakes.ready = false
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNotNil(controller.message)
        XCTAssertTrue(fakes.events.isEmpty)
    }

    func testEmptyTextDoesNothing() async {
        let (controller, fakes) = make(mode: .tap)
        fakes.text = "  \n "
        controller.hotkeyDown()
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertTrue(fakes.pasted.isEmpty)
        XCTAssertTrue(fakes.saved.isEmpty)
        XCTAssertEqual(controller.lastText, "")
        XCTAssertEqual(controller.state, .idle)
    }

    func testStoreFailureStillPastesAndReports() async {
        let (controller, fakes) = make(mode: .tap)
        fakes.storeError = CocoaError(.fileWriteUnknown)
        controller.hotkeyDown()
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertEqual(fakes.pasted, ["hello"])
        XCTAssertEqual(controller.lastText, "hello")
        XCTAssertNotNil(controller.message)
    }

    func testTranscriptionFailureReportsAndReturnsToIdle() async {
        let (controller, fakes) = make(mode: .tap)
        fakes.transcribeError = CocoaError(.fileReadUnknown)
        controller.hotkeyDown()
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNotNil(controller.message)
        XCTAssertTrue(fakes.pasted.isEmpty)
    }

    func testRecordingStartFailureReturnsToIdleImmediately() async {
        let (controller, fakes) = make(mode: .tap)
        fakes.recordError = CocoaError(.fileReadNoPermission)
        controller.hotkeyDown()
        _ = try? await controller.recordingStart?.value
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNotNil(controller.message)
        XCTAssertTrue(fakes.pasted.isEmpty)
    }

    func testStartsWithLatestStoredText() {
        let (controller, _) = make(latest: "previous dictation")
        XCTAssertEqual(controller.lastText, "previous dictation")
    }

    func testStartsEmptyWhenStoreIsEmpty() {
        let (controller, _) = make()
        XCTAssertEqual(controller.lastText, "")
    }

    func testModePersistsInDefaults() {
        let defaults = makeDefaults()
        XCTAssertEqual(make(defaults: defaults).0.mode, .tap)
        _ = make(mode: .hold, defaults: defaults)
        XCTAssertEqual(make(defaults: defaults).0.mode, .hold)
    }

    private func waitForTranscriptionGate(_ fakes: Fakes) async {
        while fakes.transcriptionGate == nil { await Task.yield() }
    }

    func testCancelWhileRecordingDiscardsAudio() async {
        let (controller, fakes) = make(mode: .tap, latest: "previous")
        controller.hotkeyDown()
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        _ = try? await controller.recordingStart?.value
        await controller.recorderRelease?.value
        XCTAssertEqual(fakes.events, ["start", "stop"])
        XCTAssertTrue(fakes.pasted.isEmpty)
        XCTAssertTrue(fakes.saved.isEmpty)
        XCTAssertEqual(controller.lastText, "previous")
    }

    func testCancelWhileTranscribingIgnoresResult() async {
        let (controller, fakes) = make(mode: .tap, latest: "previous")
        fakes.holdTranscription = true
        controller.hotkeyDown()
        controller.hotkeyDown()
        await waitForTranscriptionGate(fakes)
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        fakes.transcriptionGate?.resume()
        await settle(controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(fakes.pasted.isEmpty)
        XCTAssertTrue(fakes.saved.isEmpty)
        XCTAssertEqual(controller.lastText, "previous")
    }

    func testCancelDuringPasteIsNoOp() async {
        let (controller, fakes) = make(mode: .tap)
        fakes.onPaste = { [unowned controller] in controller.cancel() }
        controller.hotkeyDown()
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(fakes.pasted, ["hello"])
        XCTAssertEqual(fakes.saved.map(\.text), ["hello"])
        XCTAssertEqual(controller.lastText, "hello")
    }

    func testCancelWhenIdleIsNoOp() {
        let (controller, fakes) = make(mode: .tap)
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(fakes.events.isEmpty)
    }

    func testNewDictationAfterCancelWhileTranscribingWorks() async {
        let (controller, fakes) = make(mode: .tap)
        fakes.holdTranscription = true
        controller.hotkeyDown()
        controller.hotkeyDown()
        await waitForTranscriptionGate(fakes)
        let staleGate = fakes.transcriptionGate
        let stalePipeline = controller.pipeline
        fakes.transcriptionGate = nil
        controller.cancel()

        fakes.holdTranscription = false
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .recording)
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(fakes.pasted, ["hello"])
        XCTAssertEqual(controller.lastText, "hello")

        staleGate?.resume()
        await stalePipeline?.value
        XCTAssertEqual(fakes.pasted, ["hello"])
        XCTAssertEqual(fakes.saved.count, 1)
    }

    func testNewDictationAfterCancelWhileRecordingWorks() async {
        let (controller, fakes) = make(mode: .tap)
        controller.hotkeyDown()
        controller.cancel()
        controller.hotkeyDown()
        XCTAssertEqual(controller.state, .recording)
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertEqual(fakes.pasted, ["hello"])
        XCTAssertEqual(fakes.events, ["start", "stop", "start", "stop"])
    }

    func testCancelShowsCrossThenIdleIcon() async {
        let (controller, _) = make(mode: .tap, cancelledDuration: .milliseconds(20))
        controller.hotkeyDown()
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.menuBarIcon, .symbol("xmark"))
        await controller.cancelledMark?.value
        XCTAssertEqual(controller.menuBarIcon, .parrot)
    }

    func testNewDictationDuringCrossShowsParrotAndTimerDoesNotClobber() async {
        let (controller, _) = make(mode: .tap, cancelledDuration: .milliseconds(20))
        controller.hotkeyDown()
        controller.cancel()
        let mark = controller.cancelledMark
        controller.hotkeyDown()
        XCTAssertEqual(controller.menuBarIcon, .parrot)
        await mark?.value
        XCTAssertEqual(controller.state, .recording)
        XCTAssertFalse(controller.showsCancelled)
        XCTAssertEqual(controller.menuBarIcon, .parrot)
        controller.hotkeyDown()
        await settle(controller)
        XCTAssertEqual(controller.menuBarIcon, .parrot)
    }
}
