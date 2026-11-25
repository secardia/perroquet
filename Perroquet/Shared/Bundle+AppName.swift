import Foundation

extension Bundle {
    /// The app's display name, so the dev and prod builds each name themselves.
    var appName: String {
        let name = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
        guard let name else {
            preconditionFailure("Info.plist has neither CFBundleDisplayName nor CFBundleName")
        }
        return name
    }
}
