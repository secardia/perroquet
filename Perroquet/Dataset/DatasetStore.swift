import CryptoKit
import Foundation

/// Reads and writes the on-disk fine-tuning dataset.
///
/// Layout: `<root>/{Pending,Validated,Rejected}_Recordings/<id>/` holding
/// `audio.wav`, `transcription_raw.txt`, `transcription.txt`, `infos.json`, `metadata.json`.
struct DatasetStore: Sendable {
    /// Errors raised by dataset operations.
    enum StoreError: Error, Equatable {
        /// No readable recording with this id exists in any folder.
        case recordingNotFound(String)
        /// A recording with the same id already exists at the destination.
        case destinationExists(URL)
    }

    /// Sample rate of stored audio, in Hz.
    static let sampleRate = 16_000

    /// Dataset root folder.
    let root: URL
    private var fileManager: FileManager { .default }

    /// Default location: `~/Library/Application Support/Perroquet/FineTuningDataset`.
    static var defaultRoot: URL {
        URL.applicationSupportDirectory
            .appending(path: "Perroquet", directoryHint: .isDirectory)
            .appending(path: "FineTuningDataset", directoryHint: .isDirectory)
    }

    /// Creates a store on the given root; folders are created on demand.
    init(root: URL = DatasetStore.defaultRoot) {
        self.root = root
    }

    /// Stores a new pending recording and returns it.
    ///
    /// Files are written to a hidden temporary folder renamed at the end, so a failure never
    /// leaves a half-written recording behind.
    @discardableResult
    func addPending(
        samples: [Float],
        transcription: TranscriptionRecord,
        date: Date = Date(),
        id: String? = nil
    ) throws -> DatasetRecording {
        let id = id ?? RecordingID.make(date: date)
        let folder = folderURL(id: id, status: .pending)
        let temp = folder.deletingLastPathComponent().appending(path: ".\(id).writing", directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: folder.path) else { throw StoreError.destinationExists(folder) }
        try? fileManager.removeItem(at: temp)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            let wav = WAVEncoder.encode(samples: samples, sampleRate: Self.sampleRate)
            try wav.write(to: temp.appending(path: "audio.wav"))
            try write(transcription.text, to: temp.appending(path: "transcription_raw.txt"))
            try write(transcription.text, to: temp.appending(path: "transcription.txt"))
            try writeJSON(
                RecordingInfos(transcription, date: date, md5: md5Hex(wav)),
                to: temp.appending(path: "infos.json"))
            try writeJSON(RecordingMetadata(transcription, date: date), to: temp.appending(path: "metadata.json"))
            try fileManager.moveItem(at: temp, to: folder)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
        return DatasetRecording(
            id: id, status: .pending, folder: folder, audio: folder.appending(path: "audio.wav"))
    }

    /// Lists recordings of all three folders, sorted by id.
    func list() -> [DatasetRecording] {
        RecordingStatus.allCases
            .flatMap { recordings(in: $0) }
            .sorted { $0.id < $1.id }
    }

    /// The recording with the greatest id, found from the folder listings without reading any recording.
    func latest() -> DatasetRecording? {
        RecordingStatus.allCases
            .flatMap { status in folders(in: status).map { (status, $0) } }
            .sorted { $0.1.lastPathComponent > $1.1.lastPathComponent }
            .lazy
            .compactMap { recording(at: $0.1, status: $0.0) }
            .first
    }

    /// Modification dates of the three status folders; changes whenever a recording is added, moved or removed.
    func signature() -> [Date?] {
        RecordingStatus.allCases.map {
            let url = root.appending(path: $0.folderName, directoryHint: .isDirectory)
            return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    /// Writes `text` as the current transcription and moves the recording to Validated.
    @discardableResult
    func validate(id: String, text: String) throws -> DatasetRecording {
        let moved = try move(try locate(id: id), to: .validated)
        try write(text, to: moved.folder.appending(path: "transcription.txt"))
        return moved
    }

    /// Moves the recording to Rejected, leaving its texts untouched.
    @discardableResult
    func reject(id: String) throws -> DatasetRecording {
        try move(try locate(id: id), to: .rejected)
    }

    private func folderURL(id: String, status: RecordingStatus) -> URL {
        root.appending(path: status.folderName, directoryHint: .isDirectory)
            .appending(path: id, directoryHint: .isDirectory)
    }

    private func folders(in status: RecordingStatus) -> [URL] {
        let directory = root.appending(path: status.folderName, directoryHint: .isDirectory)
        return (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles)) ?? []
    }

    private func recordings(in status: RecordingStatus) -> [DatasetRecording] {
        folders(in: status).compactMap { recording(at: $0, status: status) }
    }

    private func recording(at folder: URL, status: RecordingStatus) -> DatasetRecording? {
        guard let audio = ["audio.wav", "audio.flac"]
            .map({ folder.appending(path: $0) })
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        else { return nil }
        return DatasetRecording(
            id: folder.lastPathComponent, status: status, folder: folder, audio: audio)
    }

    private func locate(id: String) throws -> DatasetRecording {
        for status in RecordingStatus.allCases {
            let folder = folderURL(id: id, status: status)
            if let found = recording(at: folder, status: status) { return found }
        }
        throw StoreError.recordingNotFound(id)
    }

    private func move(_ source: DatasetRecording, to status: RecordingStatus) throws -> DatasetRecording {
        if source.status == status { return recording(at: source.folder, status: status) ?? source }
        let destination = folderURL(id: source.id, status: status)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw StoreError.destinationExists(destination)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: source.folder, to: destination)
        guard let moved = recording(at: destination, status: status) else {
            throw StoreError.recordingNotFound(source.id)
        }
        return moved
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeJSON(_ value: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }

    private func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// `infos.json` content; unknown values are left nil and omitted.
private struct RecordingInfos: Encodable {
    let provider = "local"
    let modelIdentifier: String
    let duration: TimeInterval
    /// Seconds since the Foundation reference date, as in Oriloq.
    let createdAt: TimeInterval
    let confidence: Double
    let textLength: Int
    let md5: String
    let words: Int?

    init(_ record: TranscriptionRecord, date: Date, md5: String) {
        modelIdentifier = record.modelIdentifier
        duration = record.duration
        createdAt = date.timeIntervalSinceReferenceDate
        confidence = record.confidence
        textLength = record.text.count
        self.md5 = md5
        words = record.words?.count
    }
}

/// `metadata.json` content; unknown values are left nil and omitted.
private struct RecordingMetadata: Encodable {
    struct Word: Encodable {
        let word: String
        let startMs: Int
        let endMs: Int

        enum CodingKeys: String, CodingKey {
            case word
            case startMs = "start_ms"
            case endMs = "end_ms"
        }
    }

    let text: String
    let audioDurationMs: Int
    let processingTime: TimeInterval
    let avgConfidence: Double
    let timestamp: Date
    let words: [Word]?

    enum CodingKeys: String, CodingKey {
        case text
        case audioDurationMs = "audio_duration_ms"
        case processingTime = "processing_time"
        case avgConfidence = "avg_confidence"
        case timestamp
        case words
    }

    init(_ record: TranscriptionRecord, date: Date) {
        text = record.text
        audioDurationMs = Int((record.duration * 1000).rounded())
        processingTime = record.processingTime
        avgConfidence = record.confidence
        timestamp = date
        words = record.words?.map { Word(word: $0.text, startMs: $0.startMs, endMs: $0.endMs) }
    }
}
