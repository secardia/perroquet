import AppKit
import PerroquetCore
import SwiftUI

/// General page: status, launch and language settings, last dictation and permissions.
struct GeneralSettingsView: View {
    @Environment(DictationController.self) private var controller
    @Environment(Transcriber.self) private var transcriber
    @Environment(Permissions.self) private var permissions
    @Environment(LaunchAtLogin.self) private var launchAtLogin
    @State private var language = AppLanguage.atLaunch
    @State private var relaunchFailed = false

    var body: some View {
        @Bindable var controller = controller
        PageScaffold(title: "General") {
            statusPill
        } content: {
            Card("Dictation") {
                CardRow {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
                }
                if let message = launchAtLogin.errorMessage {
                    CardRow { Text(message).foregroundStyle(AppColors.error) }
                }
                CardRow {
                    Toggle(isOn: $controller.saveRecordings) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save recordings")
                            Text("Keeps your dictations on this Mac so you can annotate them for fine-tuning.")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                CardRow {
                    HStack {
                        Text("Language")
                        Spacer()
                        Picker("Language", selection: $language) {
                            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: language) { language.store() }
                    }
                }
                if language != AppLanguage.atLaunch {
                    CardRow {
                        HStack {
                            Text("Takes effect the next time \(Bundle.main.appName) opens")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Button("Relaunch", action: relaunch).buttonStyle(.appNeutral)
                        }
                    }
                    if relaunchFailed {
                        CardRow {
                            Text("Couldn't relaunch \(Bundle.main.appName). Quit it and open it again.")
                                .foregroundStyle(AppColors.error)
                        }
                    }
                }
            }
            if !controller.lastText.isEmpty {
                Card("Last dictation") {
                    CardRow {
                        HStack {
                            Text(controller.lastText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Copy", action: controller.copyLastText).buttonStyle(.appNeutral)
                        }
                    }
                }
            }
            Card("Permissions") {
                PermissionRow(
                    title: "Microphone",
                    detail: "Records your voice while you dictate. The audio is transcribed on this Mac and never sent anywhere.",
                    granted: permissions.isMicrophoneGranted
                ) {
                    permissions.beginGrant()
                    if permissions.canRequestMicrophone {
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
                    CardRow { Text(message).foregroundStyle(AppColors.error) }
                }
            }
        }
        .toggleStyle(.app)
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

    private func relaunch() {
        Task {
            do {
                try await AppLanguage.relaunch()
            } catch {
                relaunchFailed = true
            }
        }
    }

    @ViewBuilder private var statusPill: some View {
        if controller.state == .recording {
            StatusPill("Listening", tone: .active)
        } else {
            StatusPill(verbatim: transcriber.state.summary, tone: transcriber.isReady ? .active : .neutral)
        }
    }
}
