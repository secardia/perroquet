import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut toggling dictation. Default is ⌘$: on a French AZERTY layout `$`
    /// sits on the ANSI right-bracket key.
    static let toggleDictation = Self("toggleDictation", default: .init(.rightBracket, modifiers: .command))
}

/// Connects the global shortcut to a controller.
enum DictationHotkey {
    /// Routes key down and key up events of `toggleDictation` to `controller`.
    @MainActor
    static func install(for controller: DictationController) {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) {
            MainActor.assumeIsolated { controller.hotkeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) {
            MainActor.assumeIsolated { controller.hotkeyUp() }
        }
    }
}
