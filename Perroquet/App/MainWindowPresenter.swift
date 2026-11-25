import AppKit

/// Brings the main window to the front and shows the app in the Dock while that window is open.
@MainActor
enum MainWindowPresenter {
    /// The pending delayed hide started by `hideFromDock()`, cancelled when the app is shown again.
    private static var pendingHide: Task<Void, Never>?

    /// Un-minimizes, orders front and makes key the main window, then activates the app.
    ///
    /// Call right after `openWindow`, since SwiftUI creates the window asynchronously.
    static func bringToFront() {
        NSApp.activate()
        Task {
            guard let window = NSApp.windows.first(where: {
                isMainWindow($0) && ($0.isVisible || $0.isMiniaturized)
            }) else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
        }
    }

    /// Whether `window` is the main window scene's window.
    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(MainWindow.id) == true
    }

    /// Whether a window notification (key, close…) is about the main window.
    static func concernsMainWindow(_ notification: Notification) -> Bool {
        (notification.object as? NSWindow).map(isMainWindow) == true
    }

    /// Shows the app in the Dock and Cmd-Tab, then re-activates it so the window stays in front.
    static func showInDock() {
        pendingHide?.cancel()
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Returns the app to a menu-bar-only app with no Dock icon once the main window is really gone.
    ///
    /// Called from `willClose`: waits for the close to finish, then leaves the Dock only if no main
    /// window is still visible (a close immediately followed by a reopen keeps the Dock icon).
    static func hideFromDock() {
        pendingHide?.cancel()
        pendingHide = Task {
            guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
            guard !NSApp.windows.contains(where: { isMainWindow($0) && $0.isVisible }) else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
