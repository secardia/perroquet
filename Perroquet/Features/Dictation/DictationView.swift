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
                ShortcutRecorder(
                    title: "Dictation shortcut",
                    name: .toggleDictation,
                    conflictsWith: .cancelDictation,
                    allowsBareKeys: false,
                    onCapturing: { DictationHotkey.setCapturing($0, controllerState: controller.state) })
                ShortcutRecorder(
                    title: "Cancel shortcut",
                    name: .cancelDictation,
                    conflictsWith: .toggleDictation,
                    allowsBareKeys: true,
                    onCapturing: { DictationHotkey.setCapturing($0, controllerState: controller.state) })
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
                LabeledContent {
                    permissionRow(granted: permissions.microphone == .authorized) {
                        permissions.beginGrant()
                        if permissions.microphone == .notDetermined {
                            Task { await permissions.requestMicrophone() }
                        } else {
                            permissions.openMicrophoneSettings()
                        }
                    }
                } label: {
                    Text("Microphone")
                    Text("Records your voice while you dictate. The audio is transcribed on this Mac and never sent anywhere.")
                }
                LabeledContent {
                    permissionRow(granted: permissions.accessibilityTrusted) {
                        permissions.beginGrant()
                        permissions.grantAccessibility()
                    }
                } label: {
                    Text("Accessibility")
                    Text("Lets \(Bundle.main.appName) paste the transcribed text into the app you are typing in.")
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
