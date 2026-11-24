import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut toggling dictation. Default is ⌘$: on a French AZERTY layout `$`
    /// sits on the ANSI right-bracket key.
    static let toggleDictation = Self("toggleDictation", default: .init(.rightBracket, modifiers: .command))

    /// Global shortcut cancelling the dictation in progress. Default is Escape; it is only registered
    /// while a dictation is running, so other apps keep receiving it.
    static let cancelDictation = Self("cancelDictation", default: .init(.escape))
}

/// Connects the global shortcut to a controller.
enum DictationHotkey {
    /// Routes key down and key up events of `toggleDictation` to `controller`, and enables
    /// `cancelDictation` only while `controller` is recording or transcribing.
    @MainActor
    static func install(for controller: DictationController) {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) {
            MainActor.assumeIsolated { controller.hotkeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) {
            MainActor.assumeIsolated { controller.hotkeyUp() }
        }
        KeyboardShortcuts.onKeyDown(for: .cancelDictation) {
            MainActor.assumeIsolated { controller.cancel() }
        }
        KeyboardShortcuts.disable(.cancelDictation)
        controller.onStateChange = { syncCancelShortcut(with: $0) }
    }

    /// Registers `cancelDictation` while a dictation is running and releases it when idle. Also to be called
    /// after the user records a new cancel shortcut, which registers it system-wide.
    static func syncCancelShortcut(with state: DictationController.State) {
        if state == .idle {
            KeyboardShortcuts.disable(.cancelDictation)
        } else {
            KeyboardShortcuts.enable(.cancelDictation)
        }
    }
}
