import Foundation

/// Database glue. JSON backups remain self-contained and compatible with old
/// readers; local database/snapshot manifests reference immutable JPEG blobs.
enum FinamiScanStorage {
    static func files(for databaseURL: URL) -> FinamiScanFiles {
        FinamiScanFiles(folder: databaseURL.deletingLastPathComponent().appendingPathComponent(FinamiScanFiles.folderName, isDirectory: true))
    }

    static func externalized(_ database: Database, file: URL) -> Database {
        guard var inline = database.scanImages, !inline.isEmpty else { return database }
        var copy = database
        var hashes = copy.scanFileHashes ?? [:]
        files(for: file).externalize(inline: &inline, hashes: &hashes)
        copy.scanImages = inline.isEmpty ? nil : inline
        copy.scanFileHashes = hashes.isEmpty ? nil : hashes
        return copy
    }

    static func portable(_ database: Database, file: URL) throws -> Database {
        var copy = database
        let images = try files(for: file).materialize(inline: copy.scanImages ?? [:], hashes: copy.scanFileHashes ?? [:])
        copy.scanImages = images.isEmpty ? nil : images
        copy.scanFileHashes = nil
        return copy
    }

    /// Atomic database replacement only after staging every moved blob and
    /// creating a verified pre-migration snapshot. Interrupted migration leaves
    /// the original inline database (or the complete new database) readable.
    static func migrateOnLoad(_ database: Database, file: URL) -> (Database, String?) {
        guard FileManager.default.fileExists(atPath: file.path), let inline = database.scanImages, !inline.isEmpty else { return (database, nil) }
        let candidate = externalized(database, file: file)
        guard candidate.scanImages != database.scanImages else { return (database, "Фото залишено в базі: не вдалося безпечно перенести вкладення.") }
        do {
            try FinamiLocalSnapshots.create(database: database, file: file, protected: true)
            let bytes = try JSONEncoder().encode(candidate)
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return (candidate, candidate.scanImages == nil ? nil : "Частина фото залишилася в базі: перенесено лише перевірені файли.")
        } catch {
            return (database, "Фото залишено в базі: міграцію не завершено. " + error.localizedDescription)
        }
    }
}

/// Local snapshots do not bundle JPEGs again. Their manifest is immutable;
/// this release deliberately does not collect any JPEG blobs automatically.
enum FinamiLocalSnapshots {
    static func folder(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent("IzanamiSnapshots", isDirectory: true)
    }

    static func create(database: Database, file: URL, protected: Bool, persistedBytes: Data? = nil) throws {
        let folder = folder(for: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snapshot = folder.appendingPathComponent((protected ? "protected-" : "") + UUID().uuidString + ".json")
        let data = try persistedBytes ?? JSONEncoder().encode(database)
        _ = try JSONDecoder().decode(Database.self, from: data)
        try data.write(to: snapshot, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try Data(contentsOf: snapshot) == data else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.setAttributes([.creationDate: Date()], ofItemAtPath: snapshot.path)
    }

    /// Preserve unreadable original bytes before restoring a healthy backup.
    /// Quarantine is intentionally outside automatic retention.
    static func quarantine(file: URL, appearance: URL) throws {
        let folder = folder(for: file).appendingPathComponent("Corrupt", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for source in [file, appearance] where FileManager.default.fileExists(atPath: source.path) {
            let bytes = try Data(contentsOf: source)
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            try bytes.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            guard try Data(contentsOf: destination) == bytes else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    static func urls(for file: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(for: file), includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted {
            let lhs = $0.resourceValuesDate ?? .distantPast
            let rhs = $1.resourceValuesDate ?? .distantPast
            return lhs == rhs ? $0.lastPathComponent < $1.lastPathComponent : lhs > rhs
        }
    }

    /// Shared synchronous disk transaction; the Store owns the single-writer
    /// reservation. This method does not touch observable state. After the atomic
    /// ledger replacement, housekeeping failures cannot turn success into failure.
    static func persist(before: Database, candidate: Database, bytes: Data, file: URL, appearance: URL, healthy: Bool, forceSnapshot: Bool) throws {
        let manager = FileManager.default
        var createdSnapshot = false
        if manager.fileExists(atPath: file.path) {
            if healthy {
                let age = urls(for: file).first?.resourceValuesDate.map { Date().timeIntervalSince($0) }
                let destructive = candidate.operations.count < before.operations.count || candidate.accounts.count != before.accounts.count
                    || candidate.obligations.count < before.obligations.count || abs(candidate.operations.count - before.operations.count) >= 5
                let should = forceSnapshot || FinamiSnapshotPolicy.shouldSnapshot(newestAge: age,
                    operationsBefore: before.operations.count, operationsAfter: candidate.operations.count,
                    accountsBefore: before.accounts.count, accountsAfter: candidate.accounts.count,
                    obligationsBefore: before.obligations.count, obligationsAfter: candidate.obligations.count)
                if should {
                    let persisted = manager.fileExists(atPath: appearance.path) ? nil : try Data(contentsOf: file)
                    try create(database: before, file: file, protected: forceSnapshot || destructive, persistedBytes: persisted)
                    createdSnapshot = true
                }
            } else {
                guard forceSnapshot else { throw CocoaError(.fileWriteUnknown) }
                try quarantine(file: file, appearance: appearance)
            }
        }
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try? manager.removeItem(at: appearance)
        if createdSnapshot { prune(urls(for: file)) }
    }

    static func prune(_ urls: [URL], now: Date = Date()) {
        let entries = urls.map { (id: $0.lastPathComponent, date: $0.resourceValuesDate ?? now) }
        let keep = FinamiSnapshotPolicy.snapshotsToKeep(entries, now: now)
        for url in urls where url.resourceValuesDate != nil && !keep.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
