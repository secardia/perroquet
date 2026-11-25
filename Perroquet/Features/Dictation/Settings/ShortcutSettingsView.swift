import KeyboardShortcuts
import SwiftUI

/// Shortcuts page: dictation and cancel shortcuts and the recording mode.
struct ShortcutSettingsView: View {
    @Environment(DictationController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Form {
            Section {
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
        }
        .formStyle(.grouped)
    }
}
