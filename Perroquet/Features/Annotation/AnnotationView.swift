import AppKit
import SwiftUI

/// Annotation tab: review pending dictations and validate or reject them.
struct AnnotationView: View {
    @Environment(AnnotationStore.self) private var store
    /// Whether this tab is the visible one; shortcuts and playback only act then.
    let isActive: Bool

    @State private var player = AudioPlayer()
    @State private var draft = ""
    @State private var saveError: String?
    @State private var scrubTime: TimeInterval?
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("playbackRate") private var rate = 1.0
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let current = store.current {
                editor(for: current)
            } else {
                Text("Nothing left to annotate")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message = saveError ?? player.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            buttons
        }
        .padding()
        .task(id: isActive) { if isActive { await store.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if isActive { Task { await store.reload() } }
        }
        .task(id: store.current?.id) { arrive() }
        .onChange(of: isActive) {
            if isActive {
                load(autoplay: false)
            } else {
                player.stop()
            }
        }
        .onDisappear { player.stop() }
        .onChange(of: rate) { player.setRate(rate) }
    }

    private var title: String {
        guard let id = store.current?.id else { return "Done" }
        return RecordingID.date(from: id)?.formatted(date: .abbreviated, time: .standard) ?? id
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline).textSelection(.enabled)
            if store.isProcessed, let status = store.current?.status {
                Text(status == .validated ? "validated" : "rejected")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .background((status == .validated ? Color.green : Color.orange).opacity(0.25), in: Capsule())
            }
            Spacer()
            Text("\(store.processedCount) / \(store.recordings.count) processed")
                .foregroundStyle(.secondary)
        }
    }

    private func editor(for recording: DatasetRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                shortcutButton(player.isPlaying ? "Pause" : "Play", .space, .control, glyph: "Space") {
                    player.togglePlayPause()
                }
                Toggle("Autoplay", isOn: $autoplay)
                Picker("Speed", selection: $rate) {
                    ForEach(Self.rates, id: \.self) { Text("\(Self.format(rate: $0))×").tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            HStack {
                Text(Self.format(scrubTime ?? player.currentTime)).monospacedDigit()
                Slider(
                    value: Binding(
                        get: { scrubTime ?? player.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(player.duration, 0.1)
                ) { editing in
                    if !editing, let time = scrubTime {
                        player.seek(to: time)
                        scrubTime = nil
                    }
                }
                .disabled(player.duration == 0)
                Text(Self.format(player.duration)).monospacedDigit()
            }
            TextEditor(text: $draft)
                .font(.title3)
                .focused($editorFocused)
        }
    }

    private static let rates = [0.75, 1, 1.5, 2, 2.5, 3]

    private static func format(rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }

    private var buttons: some View {
        HStack {
            shortcutButton("Previous", .leftArrow, .command, glyph: "←") { navigate { store.previous() } }
            Spacer()
            if store.current != nil {
                shortcutButton("Reject", .delete, .command, glyph: "⌫") { navigate { try store.reject() } }
                shortcutButton("Save & Next", .return, .command, glyph: "↩") { navigate { try store.save(draft) } }
            }
        }
    }

    private func shortcutButton(
        _ title: String, _ key: KeyEquivalent, _ modifiers: EventModifiers, glyph: String,
        action: @escaping () -> Void
    ) -> some View {
        let symbol = (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.command) ? "⌘" : "")
        return Button(action: action) {
            Text("\(title)  \(Text("\(symbol)\(glyph)").foregroundStyle(.secondary))")
        }
        .keyboardShortcut(isActive ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }

    private func navigate(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func arrive() {
        draft = store.currentText
        saveError = nil
        let requested = store.takeAutoplayRequest()
        load(autoplay: autoplay && requested)
    }

    private func load(autoplay: Bool) {
        if let current = store.current, isActive {
            player.setRate(rate)
            player.load(current.audio, autoplay: autoplay)
            editorFocused = true
        } else {
            player.stop()
        }
    }
}
