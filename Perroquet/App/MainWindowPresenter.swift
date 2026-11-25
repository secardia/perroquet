import AppKit

/// Brings the main window to the front and shows the app in the Dock while that window is open.
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

    /// Whether `window` is the main window scene's window.
    @MainActor
    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(MainWindow.id) == true
    }

    /// Shows the app in the Dock and Cmd-Tab, then re-activates it so the window stays in front.
    @MainActor
    static func showInDock() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Returns the app to a menu-bar-only app with no Dock icon.
    @MainActor
    static func hideFromDock() {
        NSApp.setActivationPolicy(.accessory)
    }
}
