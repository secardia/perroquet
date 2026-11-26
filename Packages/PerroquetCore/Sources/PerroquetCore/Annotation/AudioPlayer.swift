import AVFoundation
import Observation

/// Plays one recording at a time at an adjustable, pitch-corrected speed; loading a new file stops the previous one.
@MainActor
@Observable
public final class AudioPlayer {
    /// Whether audio is currently playing.
    public private(set) var isPlaying = false
    /// Set when the file could not be opened; cleared on the next `load`.
    public private(set) var errorMessage: String?
    /// Length of the loaded recording in seconds; 0 until the file is read or when nothing is loaded.
    public private(set) var duration: TimeInterval = 0
    /// Position in seconds of audio (not wall time); refreshed about 30 times a second while playing.
    public private(set) var currentTime: TimeInterval = 0
    /// When set, only the speech is played: playback jumps over each silence it reaches. Kept across `load`.
    @ObservationIgnored public var skippedSilences: SpeechSpans?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var rate: Float = 1

    public init() {}

    /// Stops the current playback, opens `url` and starts playing it when `autoplay` is true.
    public func load(_ url: URL, autoplay: Bool) {
        stop()
        // Without precise timing, AVFoundation estimates FLAC positions from the bitrate: a seek to 33 s could
        // start playing 0.8 s early, out of step with the waveform and the time shown.
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        let next = AVPlayer(playerItem: item)
        next.defaultRate = rate
        player = next
        timeObserver = next.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                let now = min(max(time.seconds, 0), self.duration)
                if !self.skipSilence(at: now) { self.currentTime = now }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
        if autoplay { play() }
        Task {
            do {
                let length = try await asset.load(.duration)
                guard player === next else { return }
                duration = length.seconds
            } catch {
                guard player === next else { return }
                errorMessage = String(localized: "Cannot open \(url.lastPathComponent): \(error.localizedDescription)", bundle: .module)
                stop(keepingError: true)
            }
        }
    }

    /// Pauses when playing, plays otherwise.
    public func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            play()
        }
    }

    /// Moves the playback position to `time` seconds of audio, clamped to the recording; keeps the play/pause state.
    public func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), duration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    /// Moves to `time` seconds of audio and plays from there, even when paused or finished.
    public func play(from time: TimeInterval) {
        seek(to: time)
        if !isPlaying { play() }
    }

    /// Sets the speed (1 is normal) for the current and every later recording, applied immediately while playing.
    public func setRate(_ value: Double) {
        rate = Float(value)
        player?.defaultRate = rate
        if isPlaying { player?.rate = rate }
    }

    /// Stops playback and unloads the file.
    public func stop() {
        stop(keepingError: false)
    }

    private func stop(keepingError: Bool) {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        duration = 0
        currentTime = 0
        if !keepingError { errorMessage = nil }
    }

    private func play() {
        skipSilence(at: currentTime)
        player?.play()
        isPlaying = player != nil
    }

    /// When silences are skipped and `time` falls in one, seeks to the next speech, or ends after the last one;
    /// returns whether it moved.
    @discardableResult
    private func skipSilence(at time: TimeInterval) -> Bool {
        guard let speech = skippedSilences else { return false }
        guard let next = speech.playableTime(from: time) else {
            player?.pause()
            finished()
            return true
        }
        guard next > time + SpeechSpans.skipTolerance else { return false }
        seek(to: next)
        return true
    }

    private func finished() {
        isPlaying = false
        currentTime = 0
        player?.seek(to: .zero)
    }
}
