import AppKit
import Carbon.HIToolbox

/// Full copy of a pasteboard's content.
struct PasteboardSnapshot: Equatable {
    /// Per item, the data of each pasteboard type.
    var items: [[NSPasteboard.PasteboardType: Data]]
}

/// Pasteboard operations needed by `Paster`.
@MainActor
protocol PasteboardAccess {
    /// Increments whenever the pasteboard content changes.
    var changeCount: Int { get }
    /// Copies every item with all its types.
    func snapshot() -> PasteboardSnapshot
    /// Replaces the content with plain text.
    func setString(_ text: String)
    /// Replaces the content with a previous snapshot.
    func restore(_ snapshot: PasteboardSnapshot)
}

/// `PasteboardAccess` backed by the general pasteboard.
@MainActor
struct SystemPasteboard: PasteboardAccess {
    private var pasteboard: NSPasteboard { .general }

    /// Increments whenever the pasteboard content changes.
    var changeCount: Int { pasteboard.changeCount }

    /// Copies every item with all its types.
    func snapshot() -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        }
        return PasteboardSnapshot(items: items)
    }

    /// Replaces the content with plain text.
    func setString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Replaces the content with a previous snapshot.
    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let items = snapshot.items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

/// Pastes text by borrowing the pasteboard and simulating ⌘V, then restoring the previous content.
@MainActor
struct Paster: TextPasting {
    /// Reasons a paste can fail.
    enum PasteError: LocalizedError {
        /// Accessibility is not granted, so ⌘V cannot be simulated.
        case accessibilityDenied

        /// Message shown to the user.
        var errorDescription: String? {
            "Accessibility access is required to paste. Enable Perroquet in System Settings."
        }
    }

    private let pasteboard: PasteboardAccess
    private let isTrusted: () -> Bool
    private let sendPasteShortcut: () -> Void
    private let restoreDelay: Duration

    /// Creates a paster; the defaults use the real accessibility check and ⌘V event.
    init(
        pasteboard: PasteboardAccess,
        isTrusted: @escaping () -> Bool = Permissions.requestAccessibility,
        sendPasteShortcut: @escaping () -> Void = Paster.postCommandV,
        restoreDelay: Duration = .milliseconds(400)
    ) {
        self.pasteboard = pasteboard
        self.isTrusted = isTrusted
        self.sendPasteShortcut = sendPasteShortcut
        self.restoreDelay = restoreDelay
    }

    /// Paster using the general pasteboard and real ⌘V events.
    static func system() -> Paster {
        Paster(pasteboard: SystemPasteboard())
    }

    /// Pastes `text` into the frontmost app, then restores the previous pasteboard content.
    func paste(_ text: String) async throws {
        guard isTrusted() else { throw PasteError.accessibilityDenied }
        let saved = pasteboard.snapshot()
        pasteboard.setString(text)
        let ours = pasteboard.changeCount
        sendPasteShortcut()
        try? await Task.sleep(for: restoreDelay)
        if pasteboard.changeCount == ours {
            pasteboard.restore(saved)
        }
    }

    /// Posts ⌘V to the system.
    nonisolated static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
