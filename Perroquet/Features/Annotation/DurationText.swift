import Foundation

extension TimeInterval {
    /// Minutes and seconds (`m:ss`), the seconds rounded down.
    var clockText: String {
        Duration.seconds(rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
