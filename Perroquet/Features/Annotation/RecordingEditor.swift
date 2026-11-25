import SwiftUI

/// Player, text editor and actions for one recording: independent of how recordings are queued.
struct RecordingEditor: View {
    let recording: DatasetRecording
    @Binding var text: String
    /// Whether to start playing on arrival; called once per recording.
    let shouldAutoplay: () -> Bool
    let onDelete: () throws -> Void
    let onValidate: () throws -> Void

    @State private var player = AudioPlayer()
    @State private var peaks: [Float]?
    @State private var actionError: String?
    @AppStorage("autoplay") private var autoplay = true
    @AppStorage("playbackRate") private var rate = 1.0
    @FocusState private var editorFocused: Bool

    private static let rates = [0.75, 1, 1.5, 2, 2.5, 3]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            playerRow
            TextEditor(text: $text)
                .font(.title3)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .focused($editorFocused)
            if let message = actionError ?? player.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            bottomBar
        }
        .padding()
        .task(id: recording.id) { await arrive() }
        .onChange(of: rate) { player.setRate(rate) }
        .onDisappear { player.stop() }
    }

    private var playerRow: some View {
        HStack(spacing: 12) {
            Button(action: player.togglePlayPause) {
                Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
            }
            .keyboardShortcut(.space, modifiers: .control)
            .help(player.isPlaying ? "Pause (⌃Space)" : "Play (⌃Space)")
            WaveformView(
                peaks: peaks,
                progress: player.duration > 0 ? player.currentTime / player.duration : 0
            ) { fraction in
                player.seek(to: fraction * player.duration)
            }
            Text(verbatim: "\(Self.format(player.currentTime)) / \(Self.format(player.duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            speedMenu
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: $rate) {
                ForEach(Self.rates, id: \.self) { Text("\(Self.format(rate: $0))×").tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Autoplay", isOn: $autoplay)
        } label: {
            Text("\(Self.format(rate: rate))×").monospacedDigit()
        }
        .menuStyle(.button)
        .fixedSize()
    }

    private var bottomBar: some View {
        HStack {
            Button("Delete") { perform(onDelete) }
            Spacer()
            Button("Validate") { perform(onValidate) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Validate (⌘↩)")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func arrive() async {
        actionError = nil
        peaks = nil
        player.setRate(rate)
        player.load(recording.audio, autoplay: autoplay && shouldAutoplay())
        editorFocused = true
        let computed = await Waveform.peaks(of: recording.audio)
        if !Task.isCancelled { peaks = computed.isEmpty ? nil : computed }
    }

    private static func format(rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
