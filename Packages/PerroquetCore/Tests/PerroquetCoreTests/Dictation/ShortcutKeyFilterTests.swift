import AppKit
import KeyboardShortcuts
import XCTest
@testable import PerroquetCore

final class ShortcutKeyFilterTests: XCTestCase {
    private let keyV = KeyboardShortcuts.Key.v.rawValue

    func testBareKeyRefusedUnlessAllowed() {
        XCTAssertFalse(ShortcutKeyFilter.accepts(keyCode: keyV, modifiers: [], allowsBareKeys: false))
        XCTAssertFalse(ShortcutKeyFilter.accepts(keyCode: keyV, modifiers: .shift, allowsBareKeys: false))
        XCTAssertTrue(ShortcutKeyFilter.accepts(keyCode: keyV, modifiers: [], allowsBareKeys: true))
    }

    func testModifierOrFunctionKeyAccepted() {
        XCTAssertTrue(ShortcutKeyFilter.accepts(keyCode: keyV, modifiers: .command, allowsBareKeys: false))
        let f5 = KeyboardShortcuts.Key.f5.rawValue
        XCTAssertTrue(ShortcutKeyFilter.accepts(keyCode: f5, modifiers: [], allowsBareKeys: false))
    }

    func testDeleteClearsOnlyWithoutModifiers() {
        let delete = KeyboardShortcuts.Key.delete.rawValue
        XCTAssertTrue(ShortcutKeyFilter.clears(keyCode: delete, modifiers: []))
        XCTAssertFalse(ShortcutKeyFilter.clears(keyCode: delete, modifiers: .command))
        XCTAssertFalse(ShortcutKeyFilter.clears(keyCode: keyV, modifiers: []))
    }
}
