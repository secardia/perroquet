import AppKit
import KeyboardShortcuts

/// Decides what a key press means while the user records a shortcut.
public enum ShortcutKeyFilter {
    private static let functionKeys: Set<Int> = {
        let keys: [KeyboardShortcuts.Key] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
        ]
        return Set(keys.map(\.rawValue))
    }()
    private static let clearKeys: Set<Int> = [
        KeyboardShortcuts.Key.delete.rawValue,
        KeyboardShortcuts.Key.deleteForward.rawValue,
    ]

    /// Whether a key press with these modifiers can be stored; bare keys are only allowed with `allowsBareKeys`,
    /// except function keys.
    public static func accepts(keyCode: Int, modifiers: NSEvent.ModifierFlags, allowsBareKeys: Bool) -> Bool {
        allowsBareKeys || !modifiers.intersection([.command, .option, .control]).isEmpty
            || functionKeys.contains(keyCode)
    }

    /// Whether the key press clears the shortcut.
    public static func clears(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        clearKeys.contains(keyCode) && modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }
}
