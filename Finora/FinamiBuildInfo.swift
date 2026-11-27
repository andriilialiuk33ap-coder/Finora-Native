import Foundation

enum FinamiBuildInfo {
    static let edition = "Optimization 3.0 · Core Preview"
    static var version: String {
        let b = Bundle.main
        let version = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return version + " (" + build + ")"
    }
}
