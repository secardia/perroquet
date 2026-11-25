import Foundation
import Observation

/// Review session over the pending recordings of the Perroquet dataset.
///
/// The queue holds pending recordings only, newest first, loaded page by page. Validating a recording takes
/// it out of the queue, deleting removes it from the dataset.
@MainActor
@Observable
final class AnnotationStore {
    /// Loaded pending recordings, newest first.
    var recordings: [DatasetRecording] { queue.recordings }
    /// Recording being reviewed; nil when no recording is pending (all-done state).
    private(set) var current: DatasetRecording?
    /// Text to edit for the current recording: its `transcription.txt`, read verbatim.
    private(set) var currentText: String = ""
    /// Lazily read row details.
    var rows: RecordingRows { queue.rows }
    /// Number of recordings waiting for review, from the folder listing.
    var pendingCount: Int { queue.count }
    /// Whether more pending recordings can be loaded into the list.
    var hasMore: Bool { queue.hasMore }

    @ObservationIgnored private let dataset: DatasetStore
    @ObservationIgnored private let queue: RecordingQueue

    /// Opens a session on `dataset`, empty until the first `reload()` lists the pending folder.
    ///
    /// `scan` lists the pending ids newest first for `reload()`; tests replace it to control timing.
    init(
        dataset: DatasetStore,
        pageSize: Int = RecordingPage.defaultSize,
        scan: (@Sendable (DatasetStore) async -> [String])? = nil
    ) {
        self.dataset = dataset
        queue = RecordingQueue(dataset: dataset, status: .pending, pageSize: pageSize, scan: scan)
    }

    /// Loads the next page of pending recordings.
    func loadMore() {
        queue.loadMore()
    }

    /// Returns whether the current recording was reached by an explicit action (save, delete,
    /// select) and should autoplay, then clears the request.
    func takeAutoplayRequest() -> Bool {
        queue.takeAutoplayRequest()
    }

    /// Re-reads the dataset off the main actor so new dictations show up; does nothing when the dataset
    /// folders did not change or when a save or delete happened during the scan. When a pending recording
    /// appeared, jumps to the newest pending one; otherwise keeps the current recording, or, when none is
    /// current (all done), opens the first pending one if any.
    func reload() async {
        await queue.reload(keeping: { current?.id }) { listed, known in
            let newest = queue.recordings.first
            let hasNewPending = listed.contains { !known.contains($0) }
            if hasNewPending, let newest {
                moveTo(newest, explicit: false)
            } else if let id = current?.id, let refreshed = queue.recording(id: id) {
                current = refreshed
            } else {
                moveTo(newest, explicit: false)
            }
        }
    }

    /// Writes `text` as the transcription of the current recording, moves it to Validated and
    /// advances to the next pending one. Throws on failure, leaving the position unchanged.
    func save(_ text: String) throws {
        guard let current else { return }
        try dataset.validate(id: current.id, text: text)
        queue.remove(current.id)
        advance(after: current.id)
    }

    /// Deletes the current recording from disk and advances to the next pending one. Throws on
    /// failure, leaving the position unchanged.
    func delete() throws {
        guard let current else { return }
        try dataset.delete(id: current.id)
        queue.remove(current.id)
        advance(after: current.id)
    }

    /// Goes to the pending recording `id` by a user action. No-op when it is the current one or not pending.
    func select(_ id: String) {
        guard id != current?.id, let recording = queue.recording(id: id) else { return }
        moveTo(recording, explicit: true)
    }

    private func advance(after id: String) {
        moveTo(queue.older(than: id) ?? queue.recordings.first, explicit: true)
    }

    private func moveTo(_ recording: DatasetRecording?, explicit: Bool) {
        queue.requestAutoplay(explicit && recording != nil && recording?.id != current?.id)
        current = recording
        currentText = recording?.readTranscription() ?? ""
    }
}
