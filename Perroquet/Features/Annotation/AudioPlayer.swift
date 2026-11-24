import AVFoundation
import Observation

/// Plays one recording at a time at an adjustable, pitch-corrected speed; loading a new file stops the previous one.
@MainActor
@Observable
final class AudioPlayer {
    /// Whether audio is currently playing.
    private(set) var isPlaying = false
    /// Set when the file could not be opened; cleared on the next `load`.
    private(set) var errorMessage: String?
    /// Length of the loaded recording in seconds; 0 until the file is read or when nothing is loaded.
    private(set) var duration: TimeInterval = 0
    /// Position in seconds of audio (not wall time); refreshed about 15 times a second while playing.
    private(set) var currentTime: TimeInterval = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var rate: Float = 1

    /// Stops the current playback, opens `url` and starts playing it when `autoplay` is true.
    func load(_ url: URL, autoplay: Bool) {
        stop()
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        let next = AVPlayer(playerItem: item)
        next.defaultRate = rate
        player = next
        timeObserver = next.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 15), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.currentTime = min(max(time.seconds, 0), self.duration)
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
                errorMessage = "Cannot open \(url.lastPathComponent): \(error.localizedDescription)"
                stop(keepingError: true)
            }
        }
    }

    /// Pauses when playing, plays otherwise.
    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            play()
        }
    }

    /// Moves the playback position to `time` seconds of audio, clamped to the recording; keeps the play/pause state.
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), duration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    /// Sets the speed (1 is normal) for the current and every later recording, applied immediately while playing.
    func setRate(_ value: Double) {
        rate = Float(value)
        player?.defaultRate = rate
        if isPlaying { player?.rate = rate }
    }

    /// Stops playback and unloads the file.
    func stop() {
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
        player?.play()
        isPlaying = player != nil
    }

    private func finished() {
        isPlaying = false
        currentTime = 0
        player?.seek(to: .zero)
    }
}
