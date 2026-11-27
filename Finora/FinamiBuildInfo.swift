import Foundation

enum FinamiBuildInfo {
    static let edition = "Quality 2.0 · Balance UI Hotfix"
    static var version: String {
        let b = Bundle.main
        let version = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return version + " (" + build + ")"
    }
}
