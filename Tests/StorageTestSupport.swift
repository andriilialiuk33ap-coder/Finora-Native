import Foundation

#if !canImport(CryptoKit)
extension FinamiScanFiles {
    // Deterministic non-cryptographic test double. Production uses CryptoKit SHA-256.
    init(folder: URL, quota: Int64 = Self.defaultQuota) {
        self.init(folder: folder, quota: quota, digest: { data in
            var h: UInt64 = 14695981039346656037
            for byte in data { h = (h ^ UInt64(byte)) &* 1099511628211 }
            return String(repeating: String(format: "%016llx", h), count: 4)
        })
    }
}
#endif

extension URL {
    var resourceValuesDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}
