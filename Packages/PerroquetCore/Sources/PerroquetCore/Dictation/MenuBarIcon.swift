/// What the menu bar item shows.
public enum MenuBarIcon: Equatable, Sendable {
    /// Ready, or recording: macOS already shows its own microphone indicator.
    case idle
    /// Transcribing and pasting the last recording.
    case transcribing
    /// Right after a cancelled dictation.
    case cancelled
    /// A problem is waiting to be shown.
    case problem
}
