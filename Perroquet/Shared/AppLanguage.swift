import AppKit
import Foundation

/// The language the app's interface uses: follow the system, or force English or French.
///
/// Stored as the app's own `AppleLanguages` preference, the same one System Settings › Language & Region › Apps
/// writes, so both stay consistent. The language is picked up at launch only.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case french

    private static let key = "AppleLanguages"

    /// The choice that was active when the process started: the interface language never changes afterwards.
    static let atLaunch = stored()

    /// Stable identifier for pickers.
    var id: String { rawValue }

    /// Label shown in the language picker; the language names stay in their own language.
    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .english: "English"
        case .french: "Français"
        }
    }

    private var code: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .french: "fr"
        }
    }

    /// The choice stored in the persistent `domain` of `defaults` (the app's own domain by default); anything else
    /// counts as following the system. The domain is read directly so a launch argument cannot shadow the stored value.
    static func stored(
        in defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? ""
    ) -> AppLanguage {
        guard let first = (defaults.persistentDomain(forName: domain)?[key] as? [String])?.first else { return .system }
        return allCases.first { $0.code.map(first.hasPrefix) ?? false } ?? .system
    }

    /// Stores the choice in `defaults`; following the system removes the key.
    func store(in defaults: UserDefaults = .standard) {
        if let code {
            defaults.set([code], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    /// Opens a new instance of the app, then quits this one.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
