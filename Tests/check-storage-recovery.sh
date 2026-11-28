#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/Store.swift" <<'SWIFT'
import Foundation
struct Database: Codable {
    var operations = [Int]()
    var accounts = [1]
    var obligations = [Int]()
    var scanImages: [String: Data]? = nil
    var scanFileHashes: [String: String]? = nil
    var appearanceRevision: String? = nil
    var preferences = "base"
}
struct DataFile { let data: Data }
@MainActor final class Store {
    var db = Database()
    var error: String?
    var ready = true
    var loading = false
    var mutationVersion: UInt64 = 0
    var backgroundCommitInProgress = false
    var writeBusyMessage = "busy"
    let url: URL
    var appearanceURL: URL { url.deletingLastPathComponent().appendingPathComponent("FinamiAppearance.json") }
    init(_ url: URL) { self.url = url }
    func save(_ copy: Database, force: Bool = false) -> Bool { write(copy, forceSnapshot: force) }
    func saveBackground(_ copy: Database, expected: UInt64) async throws -> Bool { await commitInBackground(copy, data: try JSONEncoder().encode(copy), expectedVersion: expected) }
SWIFT
# Compile actual production storage methods, not copies. Only UI/model dependencies are fixtures.
sed -n '/^  private func commitInBackground(/,/^  private func paymentIntegrityPreserved(/p' Finora/FinamiStore.swift | sed '$d' >> "$tmp/Store.swift"
sed -n '/^  private func write(_ copy: Database/,/^  func totals(/p' Finora/FinamiStore.swift | sed '$d' >> "$tmp/Store.swift"
sed -n '/^  func snapshotURLs()/,/^  func csv()/p' Finora/FinamiStore.swift | sed '$d' >> "$tmp/Store.swift"
echo '}' >> "$tmp/Store.swift"
cat > "$tmp/Harness.swift" <<'SWIFT'
import Foundation
func check(_ condition: Bool, _ label: String) {
    guard condition else { Swift.print("FAIL: " + label); exit(1) }
    Swift.print("PASS: " + label)
}
func fails(_ block: () throws -> Void) -> Bool { do { try block(); return false } catch { return true } }
@main struct Harness {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("Finora.json")
        let files = FinamiScanStorage.files(for: databaseURL)
        let one = Data([1,2,3,4]), two = Data([4,3,2,1]), three = Data([7,8,9])
        let h1 = try files.stage(one)
        let h2 = try files.stage(two)
        check(h1 != h2 && FinamiScanFiles.isValidHash(h1), "content hashes distinguish equal-sized JPEG data")
        #if canImport(CryptoKit)
        check(h1 == "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a", "production SHA-256 known vector")
        #else
        Swift.print("SKIP: SHA-256 vector requires CryptoKit (test-only digest injected)")
        #endif
        let same = try files.stage(one)
        let size = try files.usedBytes()
        check(same == h1 && size == 8, "identical content is deduplicated")
        check(try files.read(h1) == one && files.read(h2) == two, "old and new versions can coexist")
        check(fails { _ = try files.read("../Finora.json") } && fails { _ = try files.stage(Data()) }, "invalid path and empty attachment rejected")
        let small = FinamiScanFiles(folder: files.folder, quota: 8)
        check(fails { _ = try small.stage(three) }, "new attachment rejected at quota")
        check(try small.stage(one) == h1, "existing content usable at quota")
        let corruptURL = try files.fileURL(h2)
        try one.write(to: corruptURL)
        check(fails { _ = try files.read(h2) } && fails { _ = try files.stage(two) }, "corrupt blob rejected and never overwritten")
        check(try Data(contentsOf: corruptURL) == one, "corrupt blob original bytes preserved")
        try manager.removeItem(at: corruptURL)
        check(try files.stage(two) == h2, "restaging after explicit test removal works")
        var inline = ["first": one, "second": two, "empty": Data(), "conflict": two]
        var hashes = ["conflict": h1]
        files.externalize(inline: &inline, hashes: &hashes)
        check(inline == ["empty": Data(), "conflict": two] && hashes["first"] == h1 && hashes["second"] == h2 && hashes["conflict"] == h1, "migration preserves invalid and conflicting inline bytes")
        check(fails { _ = try files.materialize(inline: inline, hashes: hashes) }, "portable export refuses manifest conflict")
        inline.removeValue(forKey: "conflict")
        let portable = try files.materialize(inline: inline, hashes: hashes)
        check(portable["first"] == one && portable["second"] == two && portable["conflict"] == one && portable["empty"] == Data(), "portable export includes every manifest and inline entry")
        check(fails { _ = try files.materialize(inline: [:], hashes: ["missing": String(repeating: "0", count: 64)]) }, "missing attachment prevents partial portable backup")

        var legacy = Database(operations: [11,22], scanImages: ["receipt": one, "archived": two])
        legacy.appearanceRevision = "old-revision"
        try JSONEncoder().encode(legacy).write(to: databaseURL)
        let (migrated, warning) = FinamiScanStorage.migrateOnLoad(legacy, file: databaseURL)
        check(warning == nil && migrated.scanImages == nil && migrated.scanFileHashes == ["receipt": h1, "archived": h2], "startup migration externalizes legacy photos")
        let disk = try JSONDecoder().decode(Database.self, from: Data(contentsOf: databaseURL))
        check(disk.operations == legacy.operations && disk.appearanceRevision == legacy.appearanceRevision && disk.scanFileHashes == migrated.scanFileHashes, "migration persists financial data and appearance revision unchanged")
        let snapshots = try manager.contentsOfDirectory(at: FinamiLocalSnapshots.folder(for: databaseURL), includingPropertiesForKeys: nil)
        check(snapshots.count == 1 && snapshots[0].lastPathComponent.hasPrefix("protected-"), "migration has a protected pre-migration snapshot")
        let old = try JSONDecoder().decode(Database.self, from: Data(contentsOf: snapshots[0]))
        check(old.scanImages == legacy.scanImages && old.scanFileHashes == nil, "pre-migration snapshot contains original bytes")
        let (_, repeatWarning) = FinamiScanStorage.migrateOnLoad(disk, file: databaseURL)
        check(repeatWarning == nil, "migration is idempotent")
        let export = try FinamiScanStorage.portable(disk, file: databaseURL)
        check(export.scanImages == legacy.scanImages && export.scanFileHashes == nil, "JSON export remains self-contained and legacy-compatible")
        let target = root.appendingPathComponent("other", isDirectory: true).appendingPathComponent("Finora.json")
        let restored = FinamiScanStorage.externalized(export, file: target)
        check(try FinamiScanStorage.portable(restored, file: target).scanImages == legacy.scanImages, "portable backup restores in a new directory")

        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try manager.createDirectory(at: blocked, withIntermediateDirectories: true)
        let blockedDB = blocked.appendingPathComponent("Finora.json")
        let originalBytes = try JSONEncoder().encode(legacy)
        try originalBytes.write(to: blockedDB)
        try Data([9]).write(to: blocked.appendingPathComponent(FinamiScanFiles.folderName))
        let (notMoved, blockedWarning) = FinamiScanStorage.migrateOnLoad(legacy, file: blockedDB)
        check(notMoved.scanImages == legacy.scanImages && blockedWarning != nil, "unwritable attachment directory leaves legacy bytes inline")
        check(try Data(contentsOf: blockedDB) == originalBytes, "failed migration preserves on-disk original")
        let blocked2 = root.appendingPathComponent("blocked-snapshot", isDirectory: true)
        try manager.createDirectory(at: blocked2, withIntermediateDirectories: true)
        let blocked2DB = blocked2.appendingPathComponent("Finora.json")
        try originalBytes.write(to: blocked2DB)
        try Data([8]).write(to: FinamiLocalSnapshots.folder(for: blocked2DB))
        let (notCommitted, backupWarning) = FinamiScanStorage.migrateOnLoad(legacy, file: blocked2DB)
        check(notCommitted.scanImages == legacy.scanImages && backupWarning != nil, "failure to snapshot aborts migration commit")
        check(try Data(contentsOf: blocked2DB) == originalBytes, "staged blobs do not remove inline source if snapshot fails")

        let store = Store(databaseURL)
        store.db = disk
        check(try store.backup().data.count > 0 && store.scanImageData("receipt") == one, "production Store backup and attachment reader wired")
        var edited = disk; edited.operations.append(33)
        check(store.save(edited), "ordinary ledger save succeeds")
        let afterOrdinary = store.snapshotURLs().count
        edited = store.db; edited.operations.append(44)
        check(store.save(edited) && store.snapshotURLs().count == afterOrdinary, "rapid small edits do not create extra snapshots")
        check(try files.read(h1) == one && files.read(h2) == two, "ordinary ledger commits leave attachment blobs intact")
        edited = store.db; edited.scanFileHashes?["receipt"] = h2; edited.operations.append(55)
        check(store.save(edited, force: true), "forced import/update creates recovery point")
        check(store.snapshotURLs().count > afterOrdinary, "forced snapshot is not rate-limited")
        let versions = try store.snapshotURLs().map { try JSONDecoder().decode(Database.self, from: Data(contentsOf: $0)) }
        guard let oldVersion = versions.first(where: { $0.scanFileHashes?["receipt"] == h1 }) else { throw CocoaError(.fileReadCorruptFile) }
        check(try FinamiScanStorage.portable(oldVersion, file: databaseURL).scanImages?["receipt"] == one, "old snapshot retains prior attachment after update")
        try two.write(to: try files.fileURL(h1))
        check(store.scanImageData("archived") == two && !fails { _ = try store.backupData() }, "unrelated historical corrupt blob does not block current valid backup")
        check(fails { _ = try FinamiScanStorage.portable(oldVersion, file: databaseURL) }, "corrupted historical blob blocks restoration")
        try manager.removeItem(at: try files.fileURL(h1)); _ = try files.stage(one)
        let beforeCorrupt = store.db
        let raw = Data("damaged financial JSON".utf8)
        try raw.write(to: databaseURL)
        store.ready = false
        check(!store.save(beforeCorrupt), "blocked database cannot be overwritten by normal save")
        check(try Data(contentsOf: databaseURL) == raw, "blocked normal save preserves corrupt bytes")
        check(store.save(beforeCorrupt, force: true), "recovery commit preserves corrupt source then replaces database")
        let quarantine = FinamiLocalSnapshots.folder(for: databaseURL).appendingPathComponent("Corrupt")
        let runs = try manager.contentsOfDirectory(at: quarantine, includingPropertiesForKeys: nil)
        check(runs.count == 1 && (try? Data(contentsOf: runs[0].appendingPathComponent("Finora.json"))) == raw, "unreadable original quarantined byte-for-byte")
        store.ready = false
        check(fails { _ = try store.backupData() }, "blocked database cannot export empty or misleading backup")
        store.ready = true
        var background = store.db; background.operations.append(123)
        let stale = try await store.saveBackground(background, expected: 1)
        check(!stale, "background write refuses obsolete revision")
        store.backgroundCommitInProgress = true
        let busy = try await store.saveBackground(background, expected: 0)
        check(!busy, "background write refuses a competing writer")
        store.backgroundCommitInProgress = false
        let saved = try await store.saveBackground(background, expected: 0)
        let onDisk = try JSONDecoder().decode(Database.self, from: Data(contentsOf: databaseURL))
        check(saved && store.db.operations == background.operations && onDisk.operations == background.operations, "background write publishes exactly the persisted candidate")
        check(!store.backgroundCommitInProgress, "background writer reservation released")


        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries = (0..<20).map { (id: "recent-\($0)", date: now.addingTimeInterval(-Double($0) * 60)) }
        entries += (1...100).map { (id: "day-\($0)", date: now.addingTimeInterval(-Double($0) * 86400)) }
        entries += (0..<12).map { (id: "protected-\($0)", date: now.addingTimeInterval(-Double($0 + 40) * 86400)) }
        let keep = FinamiSnapshotPolicy.snapshotsToKeep(entries, now: now, calendar: calendar)
        check((0..<12).allSatisfy { keep.contains("recent-\($0)") } && !keep.contains("recent-19"), "retention keeps latest 12 plus calendar buckets")
        check((1...13).allSatisfy { keep.contains("day-\($0)") }, "daily retention preserves two weeks including current day")
        check((0..<8).allSatisfy { keep.contains("protected-\($0)") } && !keep.contains("protected-11"), "protected points survive edit bursts (bounded to 8)")
        check(keep.count <= 38, "retention bounded by recent, daily, weekly and protected buckets")
        let kept = entries.filter { keep.contains($0.id) }
        check(FinamiSnapshotPolicy.snapshotsToKeep(kept, now: now, calendar: calendar) == keep, "retention idempotent")
        check(FinamiSnapshotPolicy.shouldSnapshot(newestAge: 30, operationsBefore: 10, operationsAfter: 9, accountsBefore: 1, accountsAfter: 1, obligationsBefore: 1, obligationsAfter: 1), "destructive edits bypass snapshot rate limit")
        check(!FinamiSnapshotPolicy.shouldSnapshot(newestAge: 30, operationsBefore: 10, operationsAfter: 11, accountsBefore: 1, accountsAfter: 1, obligationsBefore: 1, obligationsAfter: 1), "ordinary rapid edits are rate-limited")
    }
}
SWIFT
swiftc -swift-version 5 -warnings-as-errors Finora/FinamiScanFiles.swift Finora/FinamiScanStorage.swift Finora/FinamiSnapshotPolicy.swift Tests/StorageTestSupport.swift "$tmp/Store.swift" "$tmp/Harness.swift" -o "$tmp/storage"
"$tmp/storage"
# Verify production wiring for OCR, secure backup, and CI entry points.
test "$(grep -c 'hashes\[photo.id\] = attachmentHash' Finora/FinamiScan.swift)" = 2
grep -Fq 'let raw = try s.backupData()' Finora/FinamiSmart.swift
grep -Fq 's.restoreSnapshot(selected)' Finora/IzanamiFeatures.swift
grep -Fq 'uses: ./.github/workflows/simulator.yml' .github/workflows/build.yml
grep -Fq 'workflow_call:' .github/workflows/simulator.yml
echo 'PASS: scan, encrypted backup, snapshot restore and release gate production call sites'
