import AVFoundation
import ApplicationServices
import AppKit
import Observation

/// Microphone and Accessibility permission state.
@MainActor
@Observable
final class Permissions {
    /// Current microphone authorization status.
    private(set) var microphone: AVAuthorizationStatus
    /// Whether the app is trusted for Accessibility.
    private(set) var accessibilityTrusted: Bool
    /// Called once when a permission goes from not granted to granted after `beginGrant()`.
    @ObservationIgnored var onGranted: (@MainActor () -> Void)?

    @ObservationIgnored private let readMicrophone: () -> AVAuthorizationStatus
    @ObservationIgnored private let readAccessibility: () -> Bool
    @ObservationIgnored private var grantRequestedAt: Date?
    @ObservationIgnored private var accessibilityPrompted = false
    @ObservationIgnored private let now: () -> Date

    /// Creates the state from the system; the readers can be replaced in tests.
    init(
        readMicrophone: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        readAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.readMicrophone = readMicrophone
        self.readAccessibility = readAccessibility
        microphone = readMicrophone()
        accessibilityTrusted = readAccessibility()
    }

    /// How long `beginGrant()` keeps `onGranted` armed.
    static let grantWindow: TimeInterval = 120

    /// Arms `onGranted` for the next not granted to granted transition within `grantWindow`, which only
    /// grants started by the user from the app (not a system prompt raised elsewhere) should trigger.
    func beginGrant() {
        grantRequestedAt = now()
    }

    /// Re-reads the current system state, publishing only what changed.
    func refresh() {
        let micWasGranted = microphone == .authorized
        let accessibilityWasTrusted = accessibilityTrusted
        let newMicrophone = readMicrophone()
        let newAccessibility = readAccessibility()
        if newMicrophone != microphone { microphone = newMicrophone }
        if newAccessibility != accessibilityTrusted { accessibilityTrusted = newAccessibility }
        let granted = (!micWasGranted && newMicrophone == .authorized) || (!accessibilityWasTrusted && newAccessibility)
        if granted, let armedAt = grantRequestedAt {
            grantRequestedAt = nil
            if now().timeIntervalSince(armedAt) <= Self.grantWindow { onGranted?() }
        }
    }

    /// Asks for microphone access (system prompt on first call), then refreshes.
    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    /// Asks for Accessibility trust (system prompt), then refreshes.
    private func requestAccessibilityAndRefresh() {
        _ = Self.requestAccessibility()
        refresh()
    }

    /// Opens one window per Grant click: the system prompt the first time, which adds the app to the
    /// Accessibility list and offers to open System Settings, then the settings pane on later clicks.
    func grantAccessibility() {
        if accessibilityPrompted {
            openAccessibilitySettings()
        } else {
            accessibilityPrompted = true
            requestAccessibilityAndRefresh()
        }
    }

    /// Returns whether Accessibility is trusted, showing the system prompt when it is not.
    nonisolated static func requestAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens the Microphone pane of System Settings.
    func openMicrophoneSettings() {
        open("Privacy_Microphone")
    }

    /// Opens the Accessibility pane of System Settings.
    private func openAccessibilitySettings() {
        open("Privacy_Accessibility")
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
