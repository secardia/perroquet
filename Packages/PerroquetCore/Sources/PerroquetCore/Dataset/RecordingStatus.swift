import Foundation

/// Review state of a dataset recording, mirrored by the folder it lives in.
enum RecordingStatus: CaseIterable, Sendable {
    case pending
    case validated

    /// Name of the dataset subfolder holding recordings in this state.
    var folderName: String {
        switch self {
        case .pending: "Pending_Recordings"
        case .validated: "Validated_Recordings"
        }
    }
}
