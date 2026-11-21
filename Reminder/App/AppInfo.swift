import Foundation

/// Build metadata read from the bundle's Info.plist.
enum AppInfo {
    static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    /// When the signing certificate / profile expires (set in project.yml); the app stops launching after it.
    static let signingExpiry: CivilDate? =
        (Bundle.main.object(forInfoDictionaryKey: "DDSigningExpiry") as? String).flatMap(CivilDate.init(string:))
}
