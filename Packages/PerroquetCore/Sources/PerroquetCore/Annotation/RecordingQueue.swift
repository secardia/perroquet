import Foundation
import Observation

/// Shared machinery of a list of recordings of one status: paging, lazy row details, guarded reload,
/// navigation and the autoplay request.
@MainActor
@Observable
final class RecordingQueue {
    /// Loaded recordings, newest first.
    var recordings: [DatasetRecording] { page.recordings }
    /// Number of recordings of the status, from the folder listing.
    var count: Int { page.ids.count }
    /// Whether more recordings can be loaded into the list.
    var hasMore: Bool { page.hasMore }
    /// Lazily read row details.
    let rows = RecordingRows()

    private var page: RecordingPage
    @ObservationIgnored private let dataset: DatasetStore
    @ObservationIgnored private let scan: @Sendable (DatasetStore) async -> [String]
    @ObservationIgnored private var lastSignature: [Date?]?
    @ObservationIgnored private var autoplayRequested = false
    @ObservationIgnored private var generation = 0

    /// Starts empty: the first `reload` lists the folder. `scan` lists the ids of `status` newest first.
    init(
        dataset: DatasetStore,
        status: RecordingStatus,
        pageSize: Int,
        scan: (@Sendable (DatasetStore) async -> [String])? = nil
    ) {
        self.dataset = dataset
        self.scan = scan ?? { await RecordingQueue.scanOffMain($0, status: status) }
        page = RecordingPage(dataset: dataset, status: status, size: pageSize)
    }

    /// Lists the ids of `status` newest first on a background task.
    nonisolated static func scanOffMain(_ dataset: DatasetStore, status: RecordingStatus) async -> [String] {
        await Task.detached { dataset.ids(in: status) }.value
    }

    /// Re-reads the dataset off the main actor; does nothing when the folders did not change or when a mutation
    /// happened during the scan. Reloads the page up to `keeping`, then calls `apply` with the listed ids and the
    /// ids known before.
    func reload(keeping: () -> String?, apply: (_ listed: [String], _ known: Set<String>) -> Void) async {
        let signature = dataset.signature()
        guard signature != lastSignature else { return }
        let startedAt = generation
        let listed = await scan(dataset)
        guard generation == startedAt else { return }
        lastSignature = signature
        let known = Set(page.ids)
        page.reset(ids: listed, keeping: keeping())
        rows.keep(Set(listed))
        apply(listed, known)
    }

    /// Loads the next page.
    func loadMore() {
        page.loadMore()
    }

    /// The newest recording older than `id`, loading further pages when needed.
    func older(than id: String) -> DatasetRecording? {
        page.older(than: id)
    }

    /// The loaded recording `id`, if any.
    func recording(id: String?) -> DatasetRecording? {
        recordings.first { $0.id == id }
    }

    /// Drops a recording from the list after it left the status folder.
    func remove(_ id: String) {
        page.remove(id)
        rows.remove(id)
        generation += 1
    }

    /// Records that the dataset changed by a local action, which cancels any reload scan in flight.
    func markChanged() {
        generation += 1
    }

    /// Asks the editor to autoplay the recording just reached, when `requested`.
    func requestAutoplay(_ requested: Bool) {
        autoplayRequested = requested
    }

    /// Returns whether an autoplay was requested, then clears the request.
    func takeAutoplayRequest() -> Bool {
        defer { autoplayRequested = false }
        return autoplayRequested
    }
}
