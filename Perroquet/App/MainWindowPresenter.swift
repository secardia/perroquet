import AppKit

/// Brings the main window to the front of an app that has no Dock icon.
enum MainWindowPresenter {
    /// Un-minimizes, orders front and makes key the main window, then activates the app.
    ///
    /// Call right after `openWindow`, since SwiftUI creates the window asynchronously.
    @MainActor
    static func bringToFront() {
        NSApp.activate()
        Task {
            guard let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue.hasPrefix(MainWindow.id) == true && ($0.isVisible || $0.isMiniaturized)
            }) else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
        }
    }
}
