import Foundation

/// How the global shortcut drives recording.
enum RecordingMode: String, CaseIterable, Identifiable {
    /// One press starts, the next press stops.
    case tap
    /// Records while the shortcut is held.
    case hold

    /// Stable identifier for lists and pickers.
    var id: String { rawValue }

    /// Label shown in the mode picker.
    var title: String {
        switch self {
        case .tap: String(localized: "Tap")
        case .hold: String(localized: "Hold")
        }
    }
}
