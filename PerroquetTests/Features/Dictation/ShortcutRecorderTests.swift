import AppKit
import KeyboardShortcuts
import XCTest
@testable import Perroquet

final class ShortcutRecorderTests: XCTestCase {
    private let keyV = KeyboardShortcuts.Key.v.rawValue

    func testBareKeyRefusedUnlessAllowed() {
        XCTAssertFalse(ShortcutRecorder.accepts(keyCode: keyV, modifiers: [], allowsBareKeys: false))
        XCTAssertFalse(ShortcutRecorder.accepts(keyCode: keyV, modifiers: .shift, allowsBareKeys: false))
        XCTAssertTrue(ShortcutRecorder.accepts(keyCode: keyV, modifiers: [], allowsBareKeys: true))
    }

    func testModifierOrFunctionKeyAccepted() {
        XCTAssertTrue(ShortcutRecorder.accepts(keyCode: keyV, modifiers: .command, allowsBareKeys: false))
        let f5 = KeyboardShortcuts.Key.f5.rawValue
        XCTAssertTrue(ShortcutRecorder.accepts(keyCode: f5, modifiers: [], allowsBareKeys: false))
    }

    func testDeleteClearsOnlyWithoutModifiers() {
        let delete = KeyboardShortcuts.Key.delete.rawValue
        XCTAssertTrue(ShortcutRecorder.clears(keyCode: delete, modifiers: []))
        XCTAssertFalse(ShortcutRecorder.clears(keyCode: delete, modifiers: .command))
        XCTAssertFalse(ShortcutRecorder.clears(keyCode: keyV, modifiers: []))
    }
}
