import Foundation
import Observation

/// Annotation session over the Perroquet dataset.
///
/// Walks recordings newest first: "next" means the next older pending one, "previous" steps back to
/// the next newer recording regardless of status. Saving validates a recording, deleting removes it
/// from the dataset.
@MainActor
@Observable
final class AnnotationStore {
    /// Every recording of the dataset, newest first.
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

    /// Number of validated recordings.
    var validatedCount: Int { recordings.filter { $0.status == .validated }.count }
    /// Whether the current recording was already validated.
    var isValidated: Bool { current?.status == .validated }

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
        recordings = dataset.list().reversed()
        moveTo(recordings.first { $0.status == .pending }, explicit: false)
    }

    /// Lists the dataset newest first on a background task.
    nonisolated static func scanOffMain(_ dataset: DatasetStore) async -> [DatasetRecording] {
        await Task.detached { Array(dataset.list().reversed()) }.value
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
        let newest = listed.first { $0.status == .pending }
        let hasNewPending = listed.contains { $0.status == .pending && !known.contains($0.id) }
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
        replace(try dataset.validate(id: current.id, text: text))
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

    /// Goes back one recording in the newest-first order, whatever its status. No-op on the newest one;
    /// from the all-done state goes to the oldest recording.
    func previous() {
        guard !recordings.isEmpty else { return }
        guard let current, let index = recordings.firstIndex(where: { $0.id == current.id }) else {
            moveTo(recordings.last, explicit: true)
            return
        }
        if index > 0 { moveTo(recordings[index - 1], explicit: true) }
    }

    private func replace(_ updated: DatasetRecording) {
        if let index = recordings.firstIndex(where: { $0.id == updated.id }) {
            recordings[index] = updated
        }
    }

    private func advance(after id: String) {
        let pending = recordings.filter { $0.status == .pending }
        moveTo(pending.first { $0.id < id } ?? pending.first, explicit: true)
    }

    private func moveTo(_ recording: DatasetRecording?, explicit: Bool) {
        autoplayRequested = explicit && recording != nil && recording?.id != current?.id
        current = recording
        currentText = recording?.readTranscription() ?? ""
    }
}
