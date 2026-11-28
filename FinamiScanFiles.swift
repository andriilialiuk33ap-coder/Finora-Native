import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Immutable, content-addressed attachments. A screenshot ID is not a content hash
/// of the saved JPEG (compression can change); snapshots refer to the JPEG digest.
struct FinamiScanFiles {
    static let folderName = "FinamiScans"
    static let defaultQuota: Int64 = 64 * 1024 * 1024
    let folder: URL
    let digest: (Data) -> String
    var quota: Int64 = Self.defaultQuota

    #if canImport(CryptoKit)
    init(folder: URL, quota: Int64 = Self.defaultQuota) {
        self.folder = folder
        self.quota = quota
        self.digest = { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }
    #endif

    init(folder: URL, quota: Int64 = Self.defaultQuota, digest: @escaping (Data) -> String) {
        self.folder = folder
        self.quota = quota
        self.digest = digest
    }

    enum Failure: LocalizedError {
        case invalid, missing, integrity, quotaExceeded
        var errorDescription: String? {
            switch self {
            case .invalid: return "Некоректний ідентифікатор або порожнє вкладення."
            case .missing: return "Файл вкладення відсутній. Перевір резервну копію."
            case .integrity: return "Контрольна сума вкладення не збігається. Файл не перезаписано."
            case .quotaExceeded: return "Досягнуто ліміту сховища чеків (64 МіБ). Збережи операцію без нового фото. Наявні вкладення не видаляються автоматично."
            }
        }
    }

    static func isValidHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    func fileURL(_ hash: String) throws -> URL {
        guard Self.isValidHash(hash) else { throw Failure.invalid }
        return folder.appendingPathComponent(hash + ".jpg", isDirectory: false)
    }

    func read(_ hash: String) throws -> Data {
        let url = try fileURL(hash)
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.missing }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.integrity }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, digest(data) == hash else { throw Failure.integrity }
        return data
    }

    func usedBytes() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: folder.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [])
        var total: Int64 = 0
        for file in files {
            let v = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v.isRegularFile == true {
                let (sum, overflow) = total.addingReportingOverflow(Int64(v.fileSize ?? 0))
                guard !overflow else { throw Failure.quotaExceeded }
                total = sum
            }
        }
        return total
    }

    /// Store is serialized on the main actor, except startup migration before it is ready.
    /// Never overwrite a blob, even if its checksum is wrong.
    func stage(_ data: Data) throws -> String {
        guard !data.isEmpty else { throw Failure.invalid }
        let hash = digest(data)
        let url = try fileURL(hash)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try read(hash) == data else { throw Failure.integrity }
            return hash
        }
        let (sum, overflow) = try usedBytes().addingReportingOverflow(Int64(data.count))
        guard !overflow, sum <= quota else { throw Failure.quotaExceeded }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        guard try read(hash) == data else { throw Failure.integrity }
        return hash
    }

    /// Migration is best-effort: each failed image stays inline, byte-for-byte.
    /// Never replace an existing, conflicting manifest entry automatically.
    func externalize(inline: inout [String: Data], hashes: inout [String: String]) {
        for (id, data) in inline {
            guard !id.isEmpty, !data.isEmpty else { continue }
            let hash = digest(data)
            guard hashes[id] == nil || hashes[id] == hash else { continue }
            guard let stored = try? stage(data) else { continue }
            hashes[id] = stored
            inline.removeValue(forKey: id)
        }
    }

    /// Portable exports must contain every manifest blob. Missing/corrupt files
    /// or conflicts fail explicitly instead of silently exporting a partial backup.
    func materialize(inline: [String: Data], hashes: [String: String]) throws -> [String: Data] {
        var result = inline
        for (id, hash) in hashes {
            let data = try read(hash)
            if let existing = result[id], existing != data { throw Failure.integrity }
            result[id] = data
        }
        return result
    }
}
