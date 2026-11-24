import AppKit
import SwiftUI

/// Shows the last dictation; clicking it copies the text and the copy icon briefly turns into a checkmark.
struct LastDictationCard: View {
    /// Where the card is shown.
    enum Style {
        /// Standalone card with its own title and rounded box, for the menu bar panel.
        case panel
        /// Bare text row for a Form section, which supplies the title, the box and the row inset. The button
        /// grows over that inset so that clicking anywhere in the row copies.
        case formRow
    }

    @Environment(DictationController.self) private var controller
    /// Inset a macOS 26 grouped Form puts around each row (measured: 10 pt on every side; `listRowInsets` is
    /// ignored there). The button is padded by it inside and pulled back by it outside, so it covers the whole
    /// row while the text stays aligned with the other rows.
    private static let formRowInset: CGFloat = 10
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
                    copyButton(verticalPadding: 5, horizontalPadding: 10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            case .formRow:
                copyButton(verticalPadding: Self.formRowInset, horizontalPadding: Self.formRowInset)
                    .padding(-Self.formRowInset)
            }
        }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            justCopied = true
            try? await Task.sleep(for: .seconds(1))
            justCopied = false
        }
    }

    private func copyButton(verticalPadding: CGFloat, horizontalPadding: CGFloat) -> some View {
        Button(action: copyLastText) {
            row(horizontalPadding: horizontalPadding)
                .padding(.vertical, verticalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(controller.lastText.isEmpty ? nil : .link)
    }

    private func row(horizontalPadding: CGFloat) -> some View {
        Text(controller.lastText.isEmpty ? "Nothing yet" : controller.lastText)
            .foregroundStyle(controller.lastText.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, horizontalPadding)
            .padding(.trailing, Self.iconReservedWidth)
            .overlay(alignment: .trailing) {
                if !controller.lastText.isEmpty {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, horizontalPadding)
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
