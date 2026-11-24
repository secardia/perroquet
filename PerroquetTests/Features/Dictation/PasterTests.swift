import XCTest
@testable import Perroquet

@MainActor
final class PasterTests: XCTestCase {
    private final class FakePasteboard: PasteboardAccess {
        var changeCount = 0
        var content = PasteboardSnapshot(items: [[.string: Data("old".utf8)]])
        func snapshot() -> PasteboardSnapshot { content }
        func setString(_ text: String) {
            changeCount += 1
            content = PasteboardSnapshot(items: [[.string: Data(text.utf8)]])
        }
        func restore(_ snapshot: PasteboardSnapshot) { changeCount += 1; content = snapshot }
    }

    func testPasteWritesTextSendsShortcutAndRestores() async throws {
        let board = FakePasteboard()
        var seenDuringShortcut: PasteboardSnapshot?
        let paster = Paster(
            pasteboard: board, isTrusted: { true },
            sendPasteShortcut: { seenDuringShortcut = board.content }, restoreDelay: .milliseconds(1))
        let original = board.content
        try await paster.paste("new")
        XCTAssertEqual(seenDuringShortcut, PasteboardSnapshot(items: [[.string: Data("new".utf8)]]))
        XCTAssertEqual(board.content, original)
    }

    func testDoesNotRestoreIfUserCopiedMeanwhile() async throws {
        let board = FakePasteboard()
        let paster = Paster(
            pasteboard: board, isTrusted: { true },
            sendPasteShortcut: { board.setString("user copy") }, restoreDelay: .milliseconds(1))
        try await paster.paste("new")
        XCTAssertEqual(board.content, PasteboardSnapshot(items: [[.string: Data("user copy".utf8)]]))
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
