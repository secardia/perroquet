import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut toggling dictation. Default is ⌘⇧$: on a French AZERTY layout `$`
    /// sits on the ANSI right-bracket key.
    static let toggleDictation = Self("toggleDictation", default: .init(.rightBracket, modifiers: [.command, .shift]))

    /// Global shortcut cancelling the dictation in progress. Default is Escape; it is only registered
    /// while a dictation is running, so other apps keep receiving it.
    static let cancelDictation = Self("cancelDictation", default: .init(.escape))
}

/// Connects the global shortcut to a controller.
enum DictationHotkey {
    @MainActor private static var isCapturing = false

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

    /// Releases both shortcuts while the user records a new one, so that pressing one does not trigger it, and
    /// restores them afterwards.
    @MainActor
    static func setCapturing(_ capturing: Bool, controllerState: DictationController.State) {
        isCapturing = capturing
        if capturing {
            KeyboardShortcuts.disable(.toggleDictation, .cancelDictation)
        } else {
            KeyboardShortcuts.enable(.toggleDictation)
            syncCancelShortcut(with: controllerState)
        }
    }

    /// Registers `cancelDictation` while a dictation is running and releases it when idle.
    @MainActor
    static func syncCancelShortcut(with state: DictationController.State) {
        guard !isCapturing else { return }
        if state == .idle {
            KeyboardShortcuts.disable(.cancelDictation)
        } else {
            KeyboardShortcuts.enable(.cancelDictation)
        }
    }
}
