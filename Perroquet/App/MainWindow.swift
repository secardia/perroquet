import AppKit
import SwiftUI

/// Main window content: a sidebar of pages and the selected page.
struct MainWindow: View {
    /// Scene identifier used to open the window.
    static let id = "main"

    enum Page: Hashable {
        case general
        case shortcuts
        case microphone
        case review
        case validated

        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .microphone: "Microphone"
            case .review: "To review"
            case .validated: "Validated"
            }
        }
    }

    @Environment(AnnotationStore.self) private var annotation
    @Environment(ValidatedStore.self) private var validated
    @Environment(MainNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(selection: $navigation.page) {
                Section("Dictation") {
                    Label("General", systemImage: "gearshape").tag(Page.general)
                    Label("Shortcuts", systemImage: "keyboard").tag(Page.shortcuts)
                    Label("Microphone", systemImage: "mic").tag(Page.microphone)
                }
                Section("Data") {
                    Label("To review", systemImage: "text.badge.checkmark")
                        .badge(annotation.pendingCount)
                        .tag(Page.review)
                    Label("Validated", systemImage: "checkmark.circle")
                        .badge(validated.validatedCount)
                        .tag(Page.validated)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            let page = navigation.page
            Group {
                switch page {
                case .general: GeneralSettingsView()
                case .shortcuts: ShortcutSettingsView()
                case .microphone: MicrophoneSettingsView()
                case .review: AnnotationView()
                case .validated: ValidatedListView()
                }
            }
            .navigationTitle(page.title)
        }
        .frame(minWidth: 640, minHeight: 360)
        .task {
            await annotation.reload()
            await validated.reload()
        }
        .onChange(of: navigation.page) { Task { await validated.reload() } }
        .onAppear {
            navigation.page = .general
            MainWindowPresenter.showInDock()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if MainWindowPresenter.concernsMainWindow(note) {
                MainWindowPresenter.showInDock()
                Task {
                    if navigation.page != .review { await annotation.reload() }
                    if navigation.page != .validated { await validated.reload() }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if MainWindowPresenter.concernsMainWindow(note) {
                navigation.page = .general
                MainWindowPresenter.hideFromDock()
            }
        }
    }
}
