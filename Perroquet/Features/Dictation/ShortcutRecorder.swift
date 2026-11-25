import AppKit
import KeyboardShortcuts
import SwiftUI

/// Form row that records a global shortcut for `name`; a click arms it and the next key press is stored.
struct ShortcutRecorder: View {
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
    static func accepts(keyCode: Int, modifiers: NSEvent.ModifierFlags, allowsBareKeys: Bool) -> Bool {
        allowsBareKeys || !modifiers.intersection([.command, .option, .control]).isEmpty
            || functionKeys.contains(keyCode)
    }

    /// Whether the key press clears the shortcut.
    static func clears(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        clearKeys.contains(keyCode) && modifiers.intersection([.command, .option, .control, .shift]).isEmpty
    }

    let title: LocalizedStringKey
    let name: KeyboardShortcuts.Name
    /// The other shortcut of the app, which this one must not duplicate.
    let conflictsWith: KeyboardShortcuts.Name
    /// Whether a key without ⌘, ⌥ or ⌃ is accepted.
    let allowsBareKeys: Bool
    /// Called with true when capturing starts and with false once it ended, after any shortcut change.
    let onCapturing: (Bool) -> Void

    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var isCapturing = false
    @State private var monitor: Any?
    @State private var releaseMonitor: Any?
    @State private var window: NSWindow?
    @State private var frame = CGRect.zero

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: toggle) {
                label
                    .frame(minWidth: 110)
            }
            .buttonStyle(.appNeutral)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        }
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear {
            stop()
            removeReleaseMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stop()
            removeReleaseMonitor()
        }
    }

    @ViewBuilder private var label: some View {
        if isCapturing {
            Text("Press keys…")
        } else if let shortcut {
            Text(verbatim: shortcut.description)
        } else {
            Text("None")
        }
    }

    private func toggle() {
        if isCapturing { stop() } else { start() }
    }

    private func start() {
        removeReleaseMonitor()
        isCapturing = true
        window = NSApp.keyWindow
        onCapturing(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated { swallows(event) } ? nil : event
        }
    }

    private func swallows(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            capture(event)
            if !isCapturing { swallowRepeats(of: event.keyCode) }
            return true
        }
        guard event.window === window else {
            stop()
            return false
        }
        let height = event.window?.contentView?.bounds.height ?? 0
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        if !frame.contains(point) { stop() }
        return false
    }

    private func swallowRepeats(of keyCode: UInt16) {
        removeReleaseMonitor()
        releaseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.keyCode == keyCode else { return event }
            if event.type == .keyDown, event.isARepeat { return nil }
            MainActor.assumeIsolated { removeReleaseMonitor() }
            return event
        }
    }

    private func removeReleaseMonitor() {
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
    }

    private func capture(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let isBare = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if !allowsBareKeys, isBare, keyCode == KeyboardShortcuts.Key.escape.rawValue {
            stop()
            return
        }
        if Self.clears(keyCode: keyCode, modifiers: event.modifierFlags) {
            KeyboardShortcuts.setShortcut(nil, for: name)
        } else if Self.accepts(keyCode: keyCode, modifiers: event.modifierFlags, allowsBareKeys: allowsBareKeys),
            let captured = KeyboardShortcuts.Shortcut(event: event),
            captured != KeyboardShortcuts.getShortcut(for: conflictsWith)
        {
            KeyboardShortcuts.setShortcut(captured, for: name)
        } else {
            return
        }
        shortcut = KeyboardShortcuts.getShortcut(for: name)
        stop()
    }

    private func stop() {
        guard isCapturing else { return }
        isCapturing = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window = nil
        onCapturing(false)
    }
}
