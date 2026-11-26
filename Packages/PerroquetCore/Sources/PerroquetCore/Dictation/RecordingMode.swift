import Foundation

/// How the global shortcut drives recording.
public enum RecordingMode: String, CaseIterable, Identifiable, Sendable {
    /// One press starts, the next press stops.
    case tap
    /// Records while the shortcut is held.
    case hold

    /// Stable identifier for lists and pickers.
    public var id: String { rawValue }
}
