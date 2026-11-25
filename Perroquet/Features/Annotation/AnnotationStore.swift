import Foundation
import Observation

/// Review session over the pending recordings of the Perroquet dataset.
///
/// The queue holds pending recordings only, newest first: `next()` goes to the next older one and
/// `previous()` to the next newer one, without saving. Validating a recording takes it out of the queue,
/// deleting removes it from the dataset.
@MainActor
@Observable
final class AnnotationStore {
    /// Pending recordings, newest first.
    private(set) var recordings: [DatasetRecording] = []
    /// Recording being reviewed; nil when no recording is pending (all-done state).
    private(set) var current: DatasetRecording?
    /// Text to edit for the current recording: its `transcription.txt`, read verbatim.
    private(set) var currentText: String = ""

    @ObservationIgnored private let dataset: DatasetStore
    @ObservationIgnored private let scan: @Sendable (DatasetStore) async -> [DatasetRecording]
    @ObservationIgnored private var lastSignature: [Date?] = []
    @ObservationIgnored private var autoplayRequested = false
    @ObservationIgnored private var generation = 0

    /// Number of recordings waiting for review.
    var pendingCount: Int { recordings.count }

    /// Opens a session on `dataset`, positioned on the first pending recording.
    ///
    /// `scan` lists the recordings newest first for `reload()`; tests replace it to control timing.
    init(
        dataset: DatasetStore,
        scan: @escaping @Sendable (DatasetStore) async -> [DatasetRecording] = { await AnnotationStore.scanOffMain($0) }
    ) {
        self.dataset = dataset
        self.scan = scan
        lastSignature = dataset.signature()
        recordings = dataset.list().reversed().filter { $0.status == .pending }
        moveTo(recordings.first, explicit: false)
    }

    /// Lists the dataset newest first on a background task.
    nonisolated static func scanOffMain(_ dataset: DatasetStore) async -> [DatasetRecording] {
        await Task.detached { dataset.list().reversed().filter { $0.status == .pending } }.value
    }

    /// Returns whether the current recording was reached by an explicit action (save, delete,
    /// previous) and should autoplay, then clears the request.
    func takeAutoplayRequest() -> Bool {
        defer { autoplayRequested = false }
        return autoplayRequested
    }

    /// Re-reads the dataset off the main actor so new dictations show up; does nothing when the dataset
    /// folders did not change or when a save or delete happened during the scan. When a pending recording
    /// appeared, jumps to the newest pending one; otherwise keeps the current recording, or, when none is
    /// current (all done), opens the first pending one if any.
    func reload() async {
        let signature = dataset.signature()
        guard signature != lastSignature else { return }
        let startedAt = generation
        let listed = await scan(dataset)
        guard generation == startedAt else { return }
        lastSignature = signature
        let known = Set(recordings.map(\.id))
        recordings = listed
        let newest = listed.first
        let hasNewPending = listed.contains { !known.contains($0.id) }
        if hasNewPending, let newest {
            moveTo(newest, explicit: false)
        } else if let id = current?.id, let refreshed = listed.first(where: { $0.id == id }) {
            current = refreshed
        } else {
            moveTo(newest, explicit: false)
        }
    }

    /// Writes `text` as the transcription of the current recording, moves it to Validated and
    /// advances to the next pending one. Throws on failure, leaving the position unchanged.
    func save(_ text: String) throws {
        guard let current else { return }
        _ = try dataset.validate(id: current.id, text: text)
        recordings.removeAll { $0.id == current.id }
        generation += 1
        advance(after: current.id)
    }

    /// Deletes the current recording from disk and advances to the next pending one. Throws on
    /// failure, leaving the position unchanged.
    func delete() throws {
        guard let current else { return }
        try dataset.delete(id: current.id)
        recordings.removeAll { $0.id == current.id }
        generation += 1
        advance(after: current.id)
    }

    /// Goes to the next newer pending recording, without saving. No-op on the newest one.
    func previous() {
        guard let index = currentIndex, index > 0 else { return }
        moveTo(recordings[index - 1], explicit: true)
    }

    /// Goes to the next older pending recording, without saving. No-op on the oldest one.
    func next() {
        guard let index = currentIndex, index + 1 < recordings.count else { return }
        moveTo(recordings[index + 1], explicit: true)
    }

    /// Whether a newer pending recording exists.
    var hasPrevious: Bool { currentIndex.map { $0 > 0 } ?? false }
    /// Whether an older pending recording exists.
    var hasNext: Bool { currentIndex.map { $0 + 1 < recordings.count } ?? false }

    private var currentIndex: Int? {
        guard let id = current?.id else { return nil }
        return recordings.firstIndex { $0.id == id }
    }

    private func advance(after id: String) {
        moveTo(recordings.first { $0.id < id } ?? recordings.first, explicit: true)
    }

    private func moveTo(_ recording: DatasetRecording?, explicit: Bool) {
        autoplayRequested = explicit && recording != nil && recording?.id != current?.id
        current = recording
        currentText = recording?.readTranscription() ?? ""
    }
}
