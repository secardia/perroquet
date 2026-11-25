import Carbon.HIToolbox
import XCTest
@testable import Perroquet

@MainActor
final class PasterTests: XCTestCase {
    private final class FakePasteboard: PasteboardAccess {
        var changeCount = 0
        var content = PasteboardSnapshot(items: [[.string: Data("old".utf8)]])
        func snapshot() -> PasteboardSnapshot { content }
        func write(_ snapshot: PasteboardSnapshot) { changeCount += 1; content = snapshot }
        func clear() { changeCount += 1; content = PasteboardSnapshot(items: []) }
    }

    func testPasteWritesTextSendsShortcutAndRestores() async throws {
        let board = FakePasteboard()
        var seenDuringShortcut: PasteboardSnapshot?
        let paster = Paster(
            pasteboard: board, isTrusted: { true },
            sendPasteShortcut: { seenDuringShortcut = board.content }, restoreDelay: .milliseconds(1))
        let original = board.content
        try await paster.paste("new")
        XCTAssertEqual(
            seenDuringShortcut,
            PasteboardSnapshot(items: [[.string: Data("new".utf8), .transient: Data()]]))
        XCTAssertEqual(board.content.items.count, original.items.count)
        XCTAssertEqual(board.content.items[0][.string], Data("old".utf8))
        XCTAssertNotNil(board.content.items[0][.transient])
    }

    func testDoesNotRestoreIfUserCopiedMeanwhile() async throws {
        let board = FakePasteboard()
        let paster = Paster(
            pasteboard: board, isTrusted: { true },
            sendPasteShortcut: { board.write(PasteboardSnapshot(items: [[.string: Data("user copy".utf8)]])) }, restoreDelay: .milliseconds(1))
        try await paster.paste("new")
        XCTAssertEqual(board.content, PasteboardSnapshot(items: [[.string: Data("user copy".utf8)]]))
    }

    func testConcealedSnapshotIsClearedNotRestored() async throws {
        let board = FakePasteboard()
        board.content = PasteboardSnapshot(items: [[.string: Data("secret".utf8), .concealed: Data()]])
        let paster = Paster(
            pasteboard: board, isTrusted: { true }, sendPasteShortcut: {}, restoreDelay: .milliseconds(1))
        try await paster.paste("new")
        XCTAssertEqual(board.content, PasteboardSnapshot(items: []))
    }

    func testKeyCodeForVIsTheANSIKeyOrFallsBack() {
        XCTAssertEqual(Paster.keyCode(for: "v"), CGKeyCode(kVK_ANSI_V))
        XCTAssertEqual(Paster.keyCode(for: "\u{1F99C}"), CGKeyCode(kVK_ANSI_V))
    }

    func testThrowsWithoutAccessibility() async {
        var sent = false
        let paster = Paster(
            pasteboard: FakePasteboard(), isTrusted: { false },
            sendPasteShortcut: { sent = true }, restoreDelay: .zero)
        do {
            try await paster.paste("x")
            XCTFail("expected error")
        } catch {
            XCTAssertFalse(sent)
        }
    }
}
