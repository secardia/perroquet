import AppKit
import KeyboardShortcuts
import SwiftUI

/// Dictation tab: settings, status and last result.
struct DictationView: View {
    @Environment(DictationController.self) private var controller
    @Environment(Transcriber.self) private var transcriber
    @Environment(Permissions.self) private var permissions
    @Environment(MicrophoneSelection.self) private var microphone
    @Environment(LaunchAtLogin.self) private var launchAtLogin

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("General") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) }))
                if let message = launchAtLogin.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Dictation shortcut", name: .toggleDictation)
                KeyboardShortcuts.Recorder("Cancel shortcut", name: .cancelDictation) { _ in
                    DictationHotkey.syncCancelShortcut(with: controller.state)
                }
                Picker("Mode", selection: $controller.mode) {
                    ForEach(RecordingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Microphone") {
                Picker(
                    "Input device",
                    selection: Binding(get: { microphone.selectedUID }, set: { microphone.select($0) })
                ) {
                    ForEach(microphone.options) { Text($0.title).tag($0.uid) }
                }
            }
            Section("Status") {
                LabeledContent("Model", value: Transcriber.modelDisplayName)
                LabeledContent("Model state", value: transcriber.state.summary)
                LabeledContent("Microphone") {
                    permissionRow(granted: permissions.microphone == .authorized) {
                        permissions.beginGrant()
                        if permissions.microphone == .notDetermined {
                            Task { await permissions.requestMicrophone() }
                        } else {
                            permissions.openMicrophoneSettings()
                        }
                    }
                }
                LabeledContent("Accessibility") {
                    permissionRow(granted: permissions.accessibilityTrusted) {
                        permissions.beginGrant()
                        permissions.requestAccessibilityAndRefresh()
                        permissions.openAccessibilitySettings()
                    }
                }
                if let message = controller.message {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshSettings)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSettings()
        }
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshSettings() {
        launchAtLogin.refresh()
        microphone.refresh()
    }

    @ViewBuilder
    private func permissionRow(granted: Bool, action: @escaping () -> Void) -> some View {
        if granted {
            Text("Granted")
        } else {
            HStack {
                Text("Not granted")
                Button("Grant…", action: action)
            }
        }
    }
}
