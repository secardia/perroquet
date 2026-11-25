import AppKit
import SwiftUI

/// Panel shown by the menu bar item: last dictation plus the open-window and quit actions.
struct MenuBarContent: View {
    @Environment(DictationController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LastDictationCard()

            if let problem = controller.problem {
                Text(problem)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Open \(Bundle.main.appName)") {
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
