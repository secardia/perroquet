import Observation
import SwiftUI

/// Page shown by the main window, shared so the menu bar and the app menu can send it to General.
@MainActor
@Observable
final class MainNavigation {
    /// Selected sidebar page.
    var page: MainWindow.Page = .general
}

/// Opens the main window on the General page and brings it to the front.
@MainActor
func openSettings(_ navigation: MainNavigation, _ openWindow: OpenWindowAction) {
    navigation.page = .general
    openWindow(id: MainWindow.id)
    MainWindowPresenter.bringToFront()
}

/// "Settings…" in the app menu, replacing the system one.
struct SettingsCommand: Commands {
    let navigation: MainNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openSettings(navigation, openWindow) }
                .keyboardShortcut(",")
        }
    }
}
