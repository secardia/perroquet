import KeyboardShortcuts
import SwiftUI

/// Shortcuts page: dictation and cancel shortcuts and the recording mode.
struct ShortcutSettingsView: View {
    @Environment(DictationController.self) private var controller

    var body: some View {
        PageScaffold(title: "Shortcuts") {
            Card {
                CardRow {
                    ShortcutRecorder(
                        title: "Dictation shortcut",
                        name: .toggleDictation,
                        conflictsWith: .cancelDictation,
                        allowsBareKeys: false,
                        onCapturing: { DictationHotkey.setCapturing($0, controllerState: controller.state) })
                }
                CardRow {
                    ShortcutRecorder(
                        title: "Cancel shortcut",
                        name: .cancelDictation,
                        conflictsWith: .toggleDictation,
                        allowsBareKeys: true,
                        onCapturing: { DictationHotkey.setCapturing($0, controllerState: controller.state) })
                }
                CardRow {
                    HStack {
                        Text("Mode")
                        Spacer()
                        SegmentedGroup {
                            ForEach(RecordingMode.allCases) { mode in
                                SegmentedCell(isSelected: controller.mode == mode) {
                                    controller.mode = mode
                                } label: {
                                    Text(mode.title)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
