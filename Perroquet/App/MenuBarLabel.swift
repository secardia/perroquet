import AppKit
import PerroquetCore
import SwiftUI

/// Menu bar item label. Every icon is drawn on a canvas the size of the parrot, so the status item keeps
/// one width and does not shift when the icon changes.
struct MenuBarLabel: View {
    let icon: MenuBarIcon

    /// Point size of the SF Symbols drawn in place of the parrot.
    private static let symbolPointSize: CGFloat = 14

    var body: some View {
        Image(nsImage: Self.image(for: icon))
            .accessibilityLabel(Self.accessibilityLabel(for: icon))
    }

    private static func accessibilityLabel(for icon: MenuBarIcon) -> Text {
        switch icon {
        case .idle: Text(verbatim: Bundle.main.appName)
        case .transcribing: Text("Transcribing")
        case .cancelled: Text("Dictation cancelled")
        case .problem: Text("Problem")
        }
    }

    private static let parrot: NSImage = {
        let image = NSImage(resource: .menuBarIcon)
        image.isTemplate = true
        return image
    }()

    private static func image(for icon: MenuBarIcon) -> NSImage {
        switch icon {
        case .idle: parrot
        case .transcribing: centredSymbol("ellipsis")
        case .cancelled: centredSymbol("xmark")
        case .problem: centredSymbol("exclamationmark.triangle")
        }
    }

    /// Draws the symbol centred on a transparent canvas the size of the parrot.
    private static func centredSymbol(_ name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else {
            assertionFailure("Unknown SF Symbol \(name)")
            return parrot
        }
        let canvas = parrot.size
        let image = NSImage(size: canvas, flipped: false) { _ in
            let origin = NSPoint(x: (canvas.width - symbol.size.width) / 2, y: (canvas.height - symbol.size.height) / 2)
            symbol.draw(in: NSRect(origin: origin, size: symbol.size))
            return true
        }
        image.isTemplate = true
        return image
    }
}
