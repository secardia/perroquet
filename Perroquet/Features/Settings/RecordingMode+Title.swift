import Foundation
import PerroquetCore

extension RecordingMode {
    /// Label shown in the mode picker.
    var title: LocalizedStringResource {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        }
    }
}
