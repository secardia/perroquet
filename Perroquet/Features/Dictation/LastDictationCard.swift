import AppKit
import SwiftUI

/// Shows the last dictation; clicking it copies the text and the copy icon briefly turns into a checkmark.
struct LastDictationCard: View {
    /// Where the card is shown.
    enum Style {
        /// Standalone card with its own title and rounded box, for the menu bar panel.
        case panel
        /// Bare text row for a Form section, which supplies the title and the box. Apply `listRowInsets(EdgeInsets())`
        /// so that the whole row is clickable.
        case formRow
    }

    @Environment(DictationController.self) private var controller
    /// Space reserved at the trailing edge of the text for the copy icon.
    private static let iconReservedWidth: CGFloat = 32

    @State private var copyCount = 0
    @State private var justCopied = false
    /// Where the card is shown.
    let style: Style

    var body: some View {
        Group {
            switch style {
            case .panel:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last dictation").font(.subheadline).foregroundStyle(.secondary)
                    copyButton(verticalPadding: 5)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            case .formRow:
                copyButton(verticalPadding: 10)
            }
        }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            justCopied = true
            try? await Task.sleep(for: .seconds(1))
            justCopied = false
        }
    }

    private func copyButton(verticalPadding: CGFloat) -> some View {
        Button(action: copyLastText) {
            row
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(controller.lastText.isEmpty ? nil : .link)
    }

    private var row: some View {
        Text(controller.lastText.isEmpty ? "Nothing yet" : controller.lastText)
            .foregroundStyle(controller.lastText.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .padding(.trailing, Self.iconReservedWidth)
            .overlay(alignment: .trailing) {
                if !controller.lastText.isEmpty {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 10)
                }
            }
    }

    private func copyLastText() {
        guard !controller.lastText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.lastText, forType: .string)
        copyCount += 1
    }
}
