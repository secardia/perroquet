import AppKit
import SwiftUI

/// Main window content: one tab per feature.
struct MainWindow: View {
    /// Scene identifier used to open the window.
    static let id = "main"

    private enum Tab {
        case dictation
        case annotation
    }

    @State private var selection = Tab.dictation

    var body: some View {
        TabView(selection: $selection) {
            DictationView()
                .tabItem { Label("Dictation", systemImage: "mic") }
                .tag(Tab.dictation)
            AnnotationView(isActive: selection == .annotation)
                .tabItem { Label("Annotation", systemImage: "text.badge.checkmark") }
                .tag(Tab.annotation)
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear { MainWindowPresenter.showInDock() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if MainWindowPresenter.concernsMainWindow(note) { MainWindowPresenter.showInDock() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if MainWindowPresenter.concernsMainWindow(note) { MainWindowPresenter.hideFromDock() }
        }
    }
}
