import AppKit
import SwiftUI

/// Main window content: a sidebar of pages and the selected page.
struct MainWindow: View {
    /// Scene identifier used to open the window.
    static let id = "main"

    /// A page of the sidebar, in display order.
    enum Page: Hashable {
        /// General page.
        case general
        /// Shortcuts page.
        case shortcuts
        /// Microphone page.
        case microphone
        /// To review page.
        case review
        /// Validated page.
        case validated

        /// Sidebar and window title.
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
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(page.title)
            .toolbar(removing: .title)
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .background(AppColors.background)
        .containerBackground(AppColors.background, for: .window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 920, minHeight: 540)
        .task {
            await annotation.reload()
            await validated.reload()
        }
        .onAppear {
            navigation.page = .general
            MainWindowPresenter.showInDock()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if MainWindowPresenter.concernsMainWindow(note) {
                MainWindowPresenter.showInDock()
                Task {
                    await annotation.reload()
                    await validated.reload()
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarHeader("Dictation")
            row(.general, icon: "gearshape")
            row(.shortcuts, icon: "keyboard")
            row(.microphone, icon: "mic")
            sidebarHeader("Data").padding(.top, 10)
            row(.review, icon: "text.badge.checkmark", count: annotation.pendingCount)
            row(.validated, icon: "checkmark.circle", count: validated.validatedCount)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func sidebarHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private func row(_ page: Page, icon: String, count: Int = 0) -> some View {
        SidebarRow(
            title: page.title, icon: icon, count: count, isSelected: navigation.page == page
        ) { navigation.page = page }
    }
}

/// Sidebar row: rounded, filled when selected, red-orange icon only on the selected page, count in a gray pill.
private struct SidebarRow: View {
    let title: LocalizedStringKey
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.textTertiary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.text)
                Spacer()
                if count > 0 {
                    Text(verbatim: String(count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppColors.button))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                    .fill(isSelected ? AppColors.selection : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
