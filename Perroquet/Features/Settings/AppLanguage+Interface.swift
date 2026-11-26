import AppKit
import PerroquetCore

extension AppLanguage {
    /// Label shown in the language picker; the language names stay in their own language.
    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .english: "English"
        case .french: "Français"
        }
    }

    /// Opens a new instance of the app, then quits this one. Throws when the new instance cannot be opened.
    @MainActor
    static func relaunch() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)
    }
}
