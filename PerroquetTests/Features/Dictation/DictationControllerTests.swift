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
            if let error = fakes.transcribeError { throw error }
            return TranscriptionRecord(
                text: fakes.text, confidence: 1, duration: 1, processingTime: 0.1, modelIdentifier: "m")
        }
    }

    private struct Paste: TextPasting {
        let fakes: Fakes
        func paste(_ text: String) async throws { fakes.pasted.append(text) }
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
        mode: RecordingMode? = nil, latest: String? = nil, defaults: UserDefaults? = nil
    ) -> (DictationController, Fakes) {
        let fakes = Fakes()
        fakes.latest = latest
        let defaults = defaults ?? makeDefaults()
        let controller = DictationController(
            recorder: Recorder(fakes: fakes), transcriber: Transcribe(fakes: fakes), paster: Paste(fakes: fakes),
            store: Store(fakes: fakes), defaults: defaults)
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
}
