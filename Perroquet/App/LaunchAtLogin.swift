import Observation
import ServiceManagement

/// Registers the app to open at login, reflecting the real `SMAppService` state.
@MainActor
@Observable
final class LaunchAtLogin {
    /// Whether the app is registered to open at login.
    private(set) var isEnabled: Bool
    /// Last registration failure, cleared on the next success.
    private(set) var errorMessage: String?

    /// Reads the current state from the system.
    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Re-reads the system state, which can change in System Settings.
    func refresh() {
        let enabled = SMAppService.mainApp.status == .enabled
        if enabled != isEnabled { isEnabled = enabled }
        if enabled { errorMessage = nil }
    }

    /// Registers or unregisters the app; on failure the state reverts to the real one and the error is kept.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                errorMessage = String(localized: "Approve \(Bundle.main.appName) in System Settings → General → Login Items to launch it at login.")
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            errorMessage = enabled
                ? String(localized: "Could not enable launch at login: \(error.localizedDescription)")
                : String(localized: "Could not disable launch at login: \(error.localizedDescription)")
        }
        refresh()
    }
}
