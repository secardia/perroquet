import AppKit
import PerroquetCore
import SwiftUI

/// Menu shown by the menu bar item: state line, copy of the last dictation, settings and quit.
struct MenuBarContent: View {
    @Environment(DictationController.self) private var controller
    @Environment(Transcriber.self) private var transcriber
    @Environment(MainNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow

    /// Longest preview of the last dictation shown under "Copy last dictation".
    private static let previewLength = 50

    var body: some View {
        Text(controller.problem ?? transcriber.state.summary)
        Divider()
        if !controller.lastText.isEmpty {
            Button(action: controller.copyLastText) {
                Text("Copy last dictation")
                Text(Self.preview(of: controller.lastText))
            }
            .keyboardShortcut("c")
            Divider()
        }
        Button("Settings…") { openSettings(navigation, openWindow) }
            .keyboardShortcut(",")
        Divider()
        Button("Quit \(Bundle.main.appName)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Start of `text` on a single line, cut with an ellipsis.
    static func preview(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > previewLength ? line.prefix(previewLength) + "…" : line
    }
}
