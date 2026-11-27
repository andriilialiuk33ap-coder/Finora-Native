import Foundation

enum FinamiBuildInfo {
    static let edition = "Functional Audit · Inbox & OCR navigation"
    static var version: String {
        let b = Bundle.main
        let version = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return version + " (" + build + ")"
    }
}
