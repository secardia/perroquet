import XCTest
@testable import PerroquetCore

@MainActor
final class MicrophoneSelectionTests: XCTestCase {
    private let usb = InputDevice(uid: "usb-1", name: "USB Mic")
    private let builtIn = InputDevice(uid: "builtin", name: "MacBook Mic")

    private func makeDefaults() -> UserDefaults {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDefaultsToSystemDefaultThenListsDevices() {
        let selection = MicrophoneSelection(defaults: makeDefaults(), listDevices: { [self] in [builtIn, usb] })
        XCTAssertNil(selection.selectedUID)
        XCTAssertEqual(selection.options.map(\.title), ["System default", "MacBook Mic", "USB Mic"])
    }

    func testChoiceSurvivesRelaunch() {
        let defaults = makeDefaults()
        MicrophoneSelection(defaults: defaults, listDevices: { [self] in [usb] }).select("usb-1")
        let relaunched = MicrophoneSelection(defaults: defaults, listDevices: { [self] in [usb] })
        XCTAssertEqual(relaunched.selectedUID, "usb-1")
    }

    func testMissingChoiceIsShownDisconnectedAndKept() {
        let defaults = makeDefaults()
        MicrophoneSelection(defaults: defaults, listDevices: { [self] in [usb] }).select("usb-1")
        let selection = MicrophoneSelection(defaults: defaults, listDevices: { [] })
        XCTAssertEqual(selection.selectedUID, "usb-1")
        XCTAssertEqual(selection.options.map(\.title), ["System default", "USB Mic (disconnected)"])
    }

    func testRefreshPicksUpReplugAndSelectingDefaultClears() {
        var connected: [InputDevice] = []
        let defaults = makeDefaults()
        let selection = MicrophoneSelection(defaults: defaults, listDevices: { connected })
        connected = [usb]
        selection.refresh()
        selection.select("usb-1")
        XCTAssertEqual(selection.options.map(\.title), ["System default", "USB Mic"])
        selection.select(nil)
        XCTAssertNil(MicrophoneSelection(defaults: defaults, listDevices: { [] }).selectedUID)
    }

    func testSelectingNotifiesTheChange() {
        let selection = MicrophoneSelection(defaults: makeDefaults(), listDevices: { [self] in [usb] })
        var notified = 0
        selection.onSelect = { notified += 1 }
        selection.select("usb-1")
        selection.select(nil)
        XCTAssertEqual(notified, 2)
    }

    func testFlagsBluetoothChoice() {
        let airPods = InputDevice(uid: "airpods", name: "AirPods", isBluetooth: true)
        let selection = MicrophoneSelection(defaults: makeDefaults(), listDevices: { [self] in [builtIn, airPods] })
        XCTAssertFalse(selection.selectedIsBluetooth)
        selection.select("airpods")
        XCTAssertTrue(selection.selectedIsBluetooth)
        selection.select("builtin")
        XCTAssertFalse(selection.selectedIsBluetooth)
    }
}
