import PerroquetCore
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
    @State private var speech: SpeechSpans?
    @State private var actionError: String?
    @AppStorage("playbackRate") private var rate = 1.0
    /// Whether playback skips the silences, when the recording's speech is known.
    @AppStorage("skipsSilences") private var skipsSilences = true
    @FocusState private var editorFocused: Bool

    /// Speeds the speed button cycles through.
    private static let rates = [1, 1.5, 2]

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
        .onChange(of: skipsSilences) { player.skippedSilences = skipsSilences ? speech : nil }
        .onDisappear { player.stop() }
    }

    /// Full-width waveform above the transport controls, so the shaded silences stay readable.
    private var playerRow: some View {
        VStack(spacing: 8) {
            WaveformView(
                peaks: peaks,
                progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                silences: silenceFractions
            ) { fraction in
                player.play(from: fraction * player.duration)
            }
            HStack(spacing: 12) {
                playButton
                Text(verbatim: "\(player.currentTime.clockText) / \(player.duration.clockText)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                if speech != nil {
                    silenceSwitch
                    Spacer()
                }
                speedButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ControlCorners.card, style: .continuous)
                .fill(AppColors.card))
    }

    private var playButton: some View {
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
    }

    /// Silences as fractions of the recording, for the waveform; empty until the duration is known.
    private var silenceFractions: [Range<Double>] {
        guard let speech, player.duration > 0 else { return [] }
        return speech.silences(duration: player.duration).map {
            $0.lowerBound / player.duration..<$0.upperBound / player.duration
        }
    }

    private var silenceSwitch: some View {
        SegmentedGroup {
            silenceCell(skips: true, symbol: "waveform.badge.minus", label: "No silences")
            silenceCell(skips: false, symbol: "waveform", label: "Raw")
        }
        .fixedSize()
    }

    private func silenceCell(skips: Bool, symbol: String, label: LocalizedStringKey) -> some View {
        SegmentedCell(size: CGSize(width: 44, height: SegmentedMetrics.cell.height), isSelected: skipsSilences == skips) {
            skipsSilences = skips
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .accessibilityLabel(Text(label))
        }
        .help(Text(label))
    }

    /// Cycles through the speeds on each click; it keeps the widest speed's width, so the controls never shift.
    private var speedButton: some View {
        Button {
            rate = Self.rate(after: rate)
        } label: {
            ZStack {
                ForEach(Self.rates, id: \.self) { Text("\(Self.format(rate: $0))×").hidden() }
                Text("\(Self.format(rate: rate))×")
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(AppColors.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous)
                    .fill(AppColors.button))
            .contentShape(RoundedRectangle(cornerRadius: ControlCorners.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Playback speed")
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
        if !Self.rates.contains(rate) { rate = 1 }
        speech = recording.readSpeechSpans()
        player.skippedSilences = skipsSilences ? speech : nil
        player.setRate(rate)
        player.load(recording.audio, autoplay: shouldAutoplay())
        editorFocused = true
        let computed = await Waveform.peaks(of: recording.audio)
        if !Task.isCancelled { peaks = computed.isEmpty ? nil : computed }
    }

    /// The speed after `rate` in `rates`, back to the first after the last one.
    private static func rate(after rate: Double) -> Double {
        rates.first { $0 > rate } ?? rates[0]
    }

    private static func format(rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2)))
    }
}
