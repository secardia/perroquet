import AVFoundation
import XCTest
@testable import Perroquet

@MainActor
final class PermissionsTests: XCTestCase {
    private final class SystemState {
        var microphone = AVAuthorizationStatus.notDetermined
        var accessibility = false
        var now = Date(timeIntervalSince1970: 0)
    }

    private func makePermissions(_ system: SystemState) -> Permissions {
        Permissions(readMicrophone: { system.microphone }, readAccessibility: { system.accessibility }, now: { system.now })
    }

    func testGrantingAccessibilityTriggersOnGrantedOnce() {
        let system = SystemState()
        let permissions = makePermissions(system)
        var count = 0
        permissions.onGranted = { count += 1 }
        permissions.beginGrant()
        permissions.refresh()
        XCTAssertEqual(count, 0)
        system.accessibility = true
        permissions.refresh()
        permissions.refresh()
        XCTAssertEqual(count, 1)
    }

    func testUnarmedGrantDoesNotTrigger() {
        let system = SystemState()
        let permissions = makePermissions(system)
        var count = 0
        permissions.onGranted = { count += 1 }
        system.microphone = .authorized
        permissions.refresh()
        XCTAssertEqual(count, 0)
    }

    func testExpiredArmDoesNotTrigger() {
        let system = SystemState()
        let permissions = makePermissions(system)
        var count = 0
        permissions.onGranted = { count += 1 }
        permissions.beginGrant()
        system.now = system.now.addingTimeInterval(Permissions.grantWindow + 1)
        system.microphone = .authorized
        permissions.refresh()
        XCTAssertEqual(count, 0)
    }

    func testGrantingMicrophoneTriggersOnGranted() {
        let system = SystemState()
        let permissions = makePermissions(system)
        var count = 0
        permissions.onGranted = { count += 1 }
        permissions.beginGrant()
        system.microphone = .denied
        permissions.refresh()
        XCTAssertEqual(count, 0)
        system.microphone = .authorized
        permissions.refresh()
        XCTAssertEqual(count, 1)
    }

    func testAlreadyGrantedAtStartDoesNotTrigger() {
        let system = SystemState()
        system.accessibility = true
        let permissions = makePermissions(system)
        var count = 0
        permissions.onGranted = { count += 1 }
        permissions.beginGrant()
        permissions.refresh()
        XCTAssertEqual(count, 0)
    }

    func testRevokingThenRegrantingTriggersAgain() {
        let system = SystemState()
        let permissions = makePermissions(system)
        var count = 0
        permissions.onGranted = { count += 1 }
        permissions.beginGrant()
        system.accessibility = true
        permissions.refresh()
        system.accessibility = false
        permissions.refresh()
        permissions.beginGrant()
        system.accessibility = true
        permissions.refresh()
        XCTAssertEqual(count, 2)
    }
}
