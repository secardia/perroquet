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
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: ControlCorners.card, style: .continuous)
                        .fill(AppColors.card))
                .focused($editorFocused)
            if let message = actionError ?? player.errorMessage {
                Text(message).foregroundStyle(AppColors.error)
            }
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .task(id: recording.id) { await arrive() }
        .onChange(of: rate) { player.setRate(rate) }
        .onDisappear { player.stop() }
    }

    private var playerRow: some View {
        HStack(spacing: 12) {
            Button(action: player.togglePlayPause) {
                Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                            .fill(AppColors.accentMuted))
                    .contentShape(RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: .control)
            .help(player.isPlaying ? "Pause (⌃Space)" : "Play (⌃Space)")
            WaveformView(
                peaks: peaks,
                progress: player.duration > 0 ? player.currentTime / player.duration : 0
            ) { fraction in
                player.seek(to: fraction * player.duration)
            }
            Text(verbatim: "\(player.currentTime.clockText) / \(player.duration.clockText)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(AppColors.textSecondary)
            speedMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ControlCorners.card, style: .continuous)
                .fill(AppColors.card))
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
            Text("\(Self.format(rate: rate))×")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                        .fill(AppColors.button))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Delete") { perform(onDelete) }
                .buttonStyle(.appNeutral)
            Button {
                perform(onValidate)
            } label: {
                HStack(spacing: 6) {
                    Text("Validate")
                    Text(verbatim: "⌘↩").foregroundStyle(AppColors.accent.opacity(0.6))
                }
            }
            .buttonStyle(.appPrimary)
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
}
