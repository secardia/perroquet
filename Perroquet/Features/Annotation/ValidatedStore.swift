import Foundation
import Observation

/// Validated recordings of the Perroquet dataset, newest first, with one selected for correction.
///
/// The list is read from the dataset folder listing only; the text of each row is read lazily by `RecordingRows`.
@MainActor
@Observable
final class ValidatedStore {
    /// Loaded validated recordings, newest first.
    var recordings: [DatasetRecording] { queue.recordings }
    /// Id of the selected recording; nil when the list is empty.
    private(set) var selectedID: String?
    /// Text of the selected recording, read verbatim.
    private(set) var currentText = ""
    /// Lazily read row details.
    var rows: RecordingRows { queue.rows }
    /// Number of validated recordings, from the folder listing.
    var validatedCount: Int { queue.count }
    /// Whether more validated recordings can be loaded into the list.
    var hasMore: Bool { queue.hasMore }
    /// The selected recording.
    var current: DatasetRecording? { queue.recording(id: selectedID) }

    @ObservationIgnored private let dataset: DatasetStore
    @ObservationIgnored private let queue: RecordingQueue

    /// Starts empty: the first `reload()` lists the dataset. `scan` lists validated ids newest first.
    init(
        dataset: DatasetStore,
        pageSize: Int = RecordingPage.defaultSize,
        scan: (@Sendable (DatasetStore) async -> [String])? = nil
    ) {
        self.dataset = dataset
        queue = RecordingQueue(dataset: dataset, status: .validated, pageSize: pageSize, scan: scan)
    }

    /// Loads the next page of validated recordings.
    func loadMore() {
        queue.loadMore()
    }

    /// Re-reads the dataset off the main actor; does nothing when the folders did not change or when a save or
    /// delete happened during the scan. Keeps the selection when it still exists, otherwise selects the newest.
    func reload() async {
        await queue.reload(keeping: { selectedID }) { listed, _ in
            if let selectedID, listed.contains(selectedID) { return }
            moveTo(queue.recordings.first?.id, explicit: false)
        }
    }

    /// Selects a recording by a user action.
    func select(_ id: String) {
        guard id != selectedID else { return }
        moveTo(id, explicit: true)
    }

    /// Returns whether the selection changed by a user action and should autoplay, then clears the request.
    func takeAutoplayRequest() -> Bool {
        queue.takeAutoplayRequest()
    }

    /// Writes `text` as the transcription of the selected recording and selects the next older one.
    /// Throws on failure, leaving the selection unchanged.
    func save(_ text: String) throws {
        guard let current else { return }
        try dataset.saveText(id: current.id, text: text)
        queue.rows.setText(text, for: current.id)
        queue.markChanged()
        if let older = queue.older(than: current.id) {
            moveTo(older.id, explicit: true)
        } else {
            currentText = text
        }
    }

    /// Deletes the selected recording from disk and selects the next older one, else the next newer one.
    /// Throws on failure, leaving the selection unchanged.
    func delete() throws {
        guard let current else { return }
        try dataset.delete(id: current.id)
        queue.remove(current.id)
        moveTo((queue.older(than: current.id) ?? queue.recordings.last)?.id, explicit: true)
    }

    private func moveTo(_ id: String?, explicit: Bool) {
        queue.requestAutoplay(explicit && id != nil && id != selectedID)
        selectedID = id
        currentText = current?.readTranscription() ?? ""
    }
}
