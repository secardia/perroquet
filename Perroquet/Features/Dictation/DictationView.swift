import KeyboardShortcuts
import SwiftUI

/// Dictation tab: settings, status and last result.
struct DictationView: View {
    @Environment(DictationController.self) private var controller
    @Environment(Transcriber.self) private var transcriber
    @Environment(Permissions.self) private var permissions

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Dictation shortcut", name: .toggleDictation)
                Picker("Mode", selection: $controller.mode) {
                    ForEach(RecordingMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
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
            Section("Last dictation") {
                LastDictationCard(style: .formRow)
                    .listRowInsets(EdgeInsets())
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
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
