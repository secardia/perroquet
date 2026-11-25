import AppKit
import SwiftUI

/// Microphone page: input device choice and the Bluetooth warning.
struct MicrophoneSettingsView: View {
    @Environment(DictationController.self) private var controller
    @Environment(MicrophoneSelection.self) private var microphone

    var body: some View {
        PageScaffold(title: "Microphone") {
            Card {
                CardRow {
                    HStack {
                        Text("Input device")
                        Spacer()
                        Picker(
                            "Input device",
                            selection: Binding(get: { microphone.selectedUID }, set: { microphone.select($0) })
                        ) {
                            ForEach(microphone.options) { Text($0.title).tag($0.uid) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                CardRow {
                    Text(
                        microphone.selectedIsBluetooth
                            ? "Recording switches a Bluetooth headset to call mode: lower sound quality, interrupted playback and a delay before your first words are heard. Prefer your Mac's microphone."
                            : "System default skips Bluetooth headsets and uses your Mac's microphone instead: recording would switch them to call mode, lowering sound quality and interrupting playback."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                }
                if let error = controller.recordingError {
                    CardRow {
                        Text(error).foregroundStyle(AppColors.error)
                    }
                }
            }
        }
        .onAppear { microphone.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone.refresh()
        }
    }
}
