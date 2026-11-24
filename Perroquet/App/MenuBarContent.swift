import AppKit
import SwiftUI

/// Panel shown by the menu bar item: last dictation plus the open-window and quit actions.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LastDictationCard(style: .panel)

            HStack {
                Button("Open Perroquet") {
                    openWindow(id: MainWindow.id)
                    MainWindowPresenter.bringToFront()
                    dismiss()
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
