import AppKit
import SwiftUI

/// Shows the last dictation; clicking it copies the text and the copy icon briefly turns into a checkmark.
struct LastDictationCard: View {
    @Environment(DictationController.self) private var controller
    /// Space reserved at the trailing edge of the text for the copy icon.
    private static let iconReservedWidth: CGFloat = 32

    @State private var copyCount = 0
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last dictation").font(.subheadline).foregroundStyle(.secondary)
            copyButton
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            justCopied = true
            try? await Task.sleep(for: .seconds(1))
            justCopied = false
        }
    }

    private var copyButton: some View {
        Button(action: copyLastText) {
            row
                .padding(.vertical, 5)
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
