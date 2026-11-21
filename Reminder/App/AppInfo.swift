import Foundation

/// Build metadata read from the bundle's Info.plist.
enum AppInfo {
    static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
}
