import Foundation
import Observation

/// The microphone chosen by the user, persisted by CoreAudio UID.
@MainActor
@Observable
final class MicrophoneSelection {
    /// One row of the picker.
    struct Option: Identifiable, Equatable {
        /// UID of the device, nil for the system default.
        let uid: String?
        /// Text shown in the picker.
        let title: String

        var id: String { uid ?? "" }
    }

    private static let uidKey = "microphoneUID"
    private static let nameKey = "microphoneName"

    /// Connected input devices as of the last `refresh()`.
    private(set) var devices: [InputDevice]
    /// UID of the chosen device, nil for the system default.
    private(set) var selectedUID: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let listDevices: () -> [InputDevice]

    /// Restores the choice from `defaults`; `listDevices` can be replaced in tests.
    init(defaults: UserDefaults = .standard, listDevices: @escaping () -> [InputDevice] = InputDevices.available) {
        self.defaults = defaults
        self.listDevices = listDevices
        devices = listDevices()
        selectedUID = defaults.string(forKey: Self.uidKey)
    }

    /// "System default", then the connected devices, plus the chosen device flagged as disconnected when absent.
    var options: [Option] {
        var result = [Option(uid: nil, title: "System default")]
        result += devices.map { Option(uid: $0.uid, title: $0.name) }
        if let uid = selectedUID, !devices.contains(where: { $0.uid == uid }) {
            let name = defaults.string(forKey: Self.nameKey) ?? uid
            result.append(Option(uid: uid, title: "\(name) (disconnected)"))
        }
        return result
    }

    /// Re-reads the connected devices.
    func refresh() {
        let current = listDevices()
        if current != devices { devices = current }
    }

    /// Chooses a device by UID, or the system default with nil.
    func select(_ uid: String?) {
        selectedUID = uid
        if let uid {
            defaults.set(uid, forKey: Self.uidKey)
            if let device = devices.first(where: { $0.uid == uid }) { defaults.set(device.name, forKey: Self.nameKey) }
        } else {
            defaults.removeObject(forKey: Self.uidKey)
            defaults.removeObject(forKey: Self.nameKey)
        }
    }
}
