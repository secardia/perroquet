import AppKit
import KeyboardShortcuts
import SwiftUI

/// General page: model state, launch and language settings, last dictation and permissions.
struct GeneralSettingsView: View {
    @Environment(DictationController.self) private var controller
    @Environment(Transcriber.self) private var transcriber
    @Environment(Permissions.self) private var permissions
    @Environment(LaunchAtLogin.self) private var launchAtLogin
    @State private var language = AppLanguage.atLaunch

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Dictation") {
                LabeledContent("State") { Text(transcriber.state.summary) }
                LabeledContent("Shortcut") {
                    Text(KeyboardShortcuts.getShortcut(for: .toggleDictation)?.description ?? String(localized: "Not set"))
                }
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
                if let message = launchAtLogin.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
                Toggle("Save recordings", isOn: $controller.saveRecordings)
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: language) { language.store() }
                if language != AppLanguage.atLaunch {
                    LabeledContent {
                        Button("Relaunch", action: AppLanguage.relaunch)
                    } label: {
                        Text("Takes effect the next time \(Bundle.main.appName) opens")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !controller.lastText.isEmpty {
                Section("Last dictation") {
                    LabeledContent {
                        Button("Copy", action: copyLastText)
                    } label: {
                        Text(controller.lastText).textSelection(.enabled)
                    }
                }
            }
            Section("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records your voice while you dictate. The audio is transcribed on this Mac and never sent anywhere. Dictations are kept on this Mac for review unless \"Save recordings\" is off.",
                    granted: permissions.microphone == .authorized
                ) {
                    permissions.beginGrant()
                    if permissions.microphone == .notDetermined {
                        Task { await permissions.requestMicrophone() }
                    } else {
                        permissions.openMicrophoneSettings()
                    }
                }
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets \(Bundle.main.appName) paste the transcribed text into the app you are typing in.",
                    granted: permissions.accessibilityTrusted
                ) {
                    permissions.beginGrant()
                    permissions.grantAccessibility()
                }
                if controller.recordingError == nil, let message = controller.problem {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func copyLastText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.lastText, forType: .string)
    }
}
