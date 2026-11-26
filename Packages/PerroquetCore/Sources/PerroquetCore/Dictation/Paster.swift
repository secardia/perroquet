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
    /// Replaces the content with `snapshot`.
    func write(_ snapshot: PasteboardSnapshot)
    /// Empties the pasteboard.
    func clear()
}

extension NSPasteboard.PasteboardType {
    /// Convention asking clipboard managers to ignore the content (nspasteboard.org).
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// Convention marking sensitive content, such as a password (nspasteboard.org).
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
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

    /// Replaces the content with `snapshot`.
    func write(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let items = snapshot.items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// Empties the pasteboard.
    func clear() {
        pasteboard.clearContents()
    }
}

/// Pastes text by borrowing the pasteboard and simulating ⌘V, then restoring the previous content.
@MainActor
public struct Paster: TextPasting {
    /// Reasons a paste can fail.
    enum PasteError: LocalizedError {
        /// Accessibility is not granted, so ⌘V cannot be simulated.
        case accessibilityDenied

        /// Message shown to the user.
        var errorDescription: String? {
            String(localized: "Accessibility access is required to paste. Enable \(Bundle.main.appName) in System Settings.", bundle: .module)
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
        restoreDelay: Duration = .seconds(1)
    ) {
        self.pasteboard = pasteboard
        self.isTrusted = isTrusted
        self.sendPasteShortcut = sendPasteShortcut
        self.restoreDelay = restoreDelay
    }

    /// Paster using the general pasteboard and real ⌘V events.
    public init() {
        self.init(pasteboard: SystemPasteboard())
    }

    /// Pastes `text` into the frontmost app, then restores the previous pasteboard content.
    func paste(_ text: String) async throws {
        guard isTrusted() else { throw PasteError.accessibilityDenied }
        let saved = pasteboard.snapshot()
        pasteboard.write(PasteboardSnapshot(items: [[.string: Data(text.utf8), .transient: Data()]]))
        let ours = pasteboard.changeCount
        sendPasteShortcut()
        try? await Task.sleep(for: restoreDelay)
        guard pasteboard.changeCount == ours else { return }
        if saved.items.contains(where: { $0[.concealed] != nil }) {
            pasteboard.clear()
        } else {
            let marked = saved.items.map { $0.merging([.transient: Data()]) { current, _ in current } }
            pasteboard.write(PasteboardSnapshot(items: marked))
        }
    }

    /// Posts ⌘V to the system.
    nonisolated static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = keyCode(for: "v")
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Virtual key code producing `character` with ⌘ held in the current keyboard layout; falls back to
    /// the ANSI position of "v" when no layout produces it.
    nonisolated static func keyCode(for character: Character) -> CGKeyCode {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue(),
        ]
        for source in sources {
            guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
            if let code = keyCode(for: character, layout: data) { return code }
        }
        return CGKeyCode(kVK_ANSI_V)
    }

    /// Modifier state of ⌘ for `UCKeyTranslate`: layouts such as "Dvorak - QWERTY ⌘" read shortcuts through it.
    private nonisolated static let commandModifierState = UInt32((cmdKey >> 8) & 0xFF)

    private nonisolated static func keyCode(for character: Character, layout: Data) -> CGKeyCode? {
        layout.withUnsafeBytes { raw -> CGKeyCode? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<UInt16(128) {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    base, code, UInt16(kUCKeyActionDown), Self.commandModifierState,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == String(character) {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
