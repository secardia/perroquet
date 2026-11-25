import Foundation

/// Builds recording identifiers: `yyyyMMdd-HHmmss-<UUID>` in UTC.
///
/// Identifiers sort chronologically when compared as strings, whatever the time zone of the machine.
enum RecordingID {
    private static let prefixLength = "yyyyMMdd-HHmmss".count

    private static let prefixFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Creates an identifier for the given date and UUID.
    static func make(date: Date = Date(), uuid: UUID = UUID()) -> String {
        "\(prefixFormatter.string(from: date))-\(uuid.uuidString.uppercased())"
    }

    /// Parses the UTC date and time from the `yyyyMMdd-HHmmss` prefix of an identifier; nil when malformed.
    static func date(from id: String) -> Date? {
        let prefix = String(id.prefix(prefixLength))
        guard prefix.count == prefixLength else { return nil }
        return prefixFormatter.date(from: prefix)
    }
}
