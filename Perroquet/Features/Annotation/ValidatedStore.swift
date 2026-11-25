import Foundation
import Observation

/// Validated recordings of the Perroquet dataset, newest first, with one selected for correction.
///
/// The list is read from the dataset folder listing only; the text of each row is read lazily by `loadText`.
@MainActor
@Observable
final class ValidatedStore {
    /// Validated recordings, newest first.
    private(set) var recordings: [DatasetRecording] = []
    /// Id of the selected recording; nil when the list is empty.
    private(set) var selectedID: String?
    /// Text of the selected recording, read verbatim.
    private(set) var currentText = ""
    /// Row texts read so far, by recording id.
    private(set) var texts: [String: String] = [:]

    @ObservationIgnored private let dataset: DatasetStore
    @ObservationIgnored private let scan: @Sendable (DatasetStore) async -> [DatasetRecording]
    @ObservationIgnored private var lastSignature: [Date?]?
    @ObservationIgnored private var autoplayRequested = false
    @ObservationIgnored private var generation = 0

    /// Number of validated recordings.
    var validatedCount: Int { recordings.count }
    /// The selected recording.
    var current: DatasetRecording? { recordings.first { $0.id == selectedID } }

    /// Starts empty: the first `reload()` lists the dataset. `scan` lists validated recordings newest first.
    init(
        dataset: DatasetStore,
        scan: @escaping @Sendable (DatasetStore) async -> [DatasetRecording] = { await ValidatedStore.scanOffMain($0) }
    ) {
        self.dataset = dataset
        self.scan = scan
    }

    /// Lists the validated recordings newest first on a background task.
    nonisolated static func scanOffMain(_ dataset: DatasetStore) async -> [DatasetRecording] {
        await Task.detached { Array(dataset.list(in: .validated).reversed()) }.value
    }

    /// Re-reads the dataset off the main actor; does nothing when the folders did not change or when a save or
    /// delete happened during the scan. Keeps the selection when it still exists, otherwise selects the newest.
    func reload() async {
        let signature = dataset.signature()
        guard signature != lastSignature else { return }
        let startedAt = generation
        let listed = await scan(dataset)
        guard generation == startedAt else { return }
        lastSignature = signature
        recordings = listed
        let ids = Set(listed.map(\.id))
        texts = texts.filter { ids.contains($0.key) }
        if let selectedID, ids.contains(selectedID) { return }
        moveTo(listed.first?.id, explicit: false)
    }

    /// Reads the text of a row once and caches it.
    func loadText(for recording: DatasetRecording) async {
        guard texts[recording.id] == nil else { return }
        let text = await Task.detached { recording.readTranscription() }.value
        if texts[recording.id] == nil { texts[recording.id] = text }
    }

    /// Selects a recording by a user action.
    func select(_ id: String?) {
        guard id != selectedID else { return }
        moveTo(id, explicit: true)
    }

    /// Returns whether the selection changed by a user action and should autoplay, then clears the request.
    func takeAutoplayRequest() -> Bool {
        defer { autoplayRequested = false }
        return autoplayRequested
    }

    /// Writes `text` as the transcription of the selected recording and selects the next older one.
    /// Throws on failure, leaving the selection unchanged.
    func save(_ text: String) throws {
        guard let current else { return }
        try dataset.saveText(id: current.id, text: text)
        texts[current.id] = text
        generation += 1
        if let older = recordings.first(where: { $0.id < current.id }) {
            moveTo(older.id, explicit: true)
        } else {
            currentText = text
        }
    }

    /// Deletes the selected recording from disk and selects the next older one, else the next newer one.
    /// Throws on failure, leaving the selection unchanged.
    func delete() throws {
        guard let current, let index = recordings.firstIndex(where: { $0.id == current.id }) else { return }
        try dataset.delete(id: current.id)
        recordings.remove(at: index)
        texts[current.id] = nil
        generation += 1
        let next = index < recordings.count ? recordings[index] : recordings.last
        moveTo(next?.id, explicit: true)
    }

    private func moveTo(_ id: String?, explicit: Bool) {
        autoplayRequested = explicit && id != nil && id != selectedID
        selectedID = id
        currentText = current?.readTranscription() ?? ""
    }
}
