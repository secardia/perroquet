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
                Toggle("Save recordings", isOn: $controller.saveRecordings)
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
                Text(
                    microphone.selectedIsBluetooth
                        ? "Recording switches a Bluetooth headset to call mode: lower sound quality, interrupted playback and a delay before your first words are heard. Prefer your Mac's microphone."
                        : "System default skips Bluetooth headsets and uses your Mac's microphone instead: recording would switch them to call mode, lowering sound quality and interrupting playback."
                )
                .font(.subheadline)
                .foregroundStyle(microphone.selectedIsBluetooth ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                if let error = controller.recordingError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section("Status") {
                LabeledContent("Model", value: Transcriber.modelDisplayName)
                // Plain Text: with the selectable text of `LabeledContent(_:value:)`, "Ready" ended up left of the
                // right edge, apparently keeping the width of an earlier, longer state ("Loading…").
                LabeledContent("Model state") { Text(transcriber.state.summary) }
                permissionRow(
                    "Microphone",
                    detail: "Records your voice while you dictate. The audio is transcribed on this Mac and never sent anywhere. Dictations are kept on this Mac for the Annotation tab unless \"Save recordings\" is off.",
                    granted: permissions.microphone == .authorized
                ) {
                    permissions.beginGrant()
                    if permissions.microphone == .notDetermined {
                        Task { await permissions.requestMicrophone() }
                    } else {
                        permissions.openMicrophoneSettings()
                    }
                }
                permissionRow(
                    "Accessibility",
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

    /// A permission row styled like a two-line `LabeledContent`, but with the status centered on both lines
    /// (`LabeledContent` aligns its value with the title only).
    private func permissionRow(
        _ title: String, detail: String, granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Text("Not granted").foregroundStyle(.secondary)
                Button("Grant…", action: action)
            }
        }
    }
}
