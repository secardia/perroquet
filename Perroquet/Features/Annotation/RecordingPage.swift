import Foundation

/// The ids of one status folder, newest first, of which only a growing prefix is resolved into recordings.
struct RecordingPage {
    /// Number of recordings resolved per page.
    static let defaultSize = 50

    /// Every id of the folder, newest first; the source of the counts.
    private(set) var ids: [String] = []
    /// Resolved recordings of the loaded prefix, newest first; ids without audio are skipped.
    private(set) var recordings: [DatasetRecording] = []

    private let dataset: DatasetStore
    private let status: RecordingStatus
    private let size: Int
    private var consumed = 0

    /// An empty page over the `status` folder of `dataset`, `size` recordings at a time.
    init(dataset: DatasetStore, status: RecordingStatus, size: Int = RecordingPage.defaultSize) {
        self.dataset = dataset
        self.status = status
        self.size = size
    }

    /// Whether ids remain beyond the loaded prefix.
    var hasMore: Bool { consumed < ids.count }

    /// Replaces the ids and reloads the prefix: at least one page, everything already loaded, and up to `keeping`.
    mutating func reset(ids newIDs: [String], keeping id: String?) {
        let known = Dictionary(recordings.map { ($0.id, $0) }) { first, _ in first }
        let wanted = max(size, consumed, id.flatMap { newIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        ids = newIDs
        recordings = []
        consumed = 0
        load(upTo: wanted, known: known)
    }

    /// Resolves the next page.
    mutating func loadMore() {
        load(upTo: consumed + size, known: [:])
    }

    /// Drops a recording, wherever it is.
    mutating func remove(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            if index < consumed { consumed -= 1 }
            ids.remove(at: index)
        }
        recordings.removeAll { $0.id == id }
    }

    /// The newest loaded recording older than `id`, loading further pages when needed.
    mutating func older(than id: String) -> DatasetRecording? {
        while true {
            if let found = recordings.first(where: { $0.id < id }) { return found }
            guard hasMore else { return nil }
            loadMore()
        }
    }

    private mutating func load(upTo limit: Int, known: [String: DatasetRecording]) {
        let end = min(limit, ids.count)
        guard consumed < end else { return }
        for id in ids[consumed..<end] {
            if let recording = known[id] ?? dataset.recording(id: id, status: status) {
                recordings.append(recording)
            }
        }
        consumed = end
    }
}
