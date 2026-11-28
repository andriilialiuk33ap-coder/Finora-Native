#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
source Tests/model-safety-fixture.sh
finami_safety_models > "$tmp/Models.swift"
cat > "$tmp/Load.swift" <<'SWIFT'
import Foundation
@MainActor final class Store {
  var db = Database()
  var error: String?
  var ready = true
  var loading = true
  var loadingStarted = false
  let url: URL
  var appearanceURL: URL { url.deletingLastPathComponent().appendingPathComponent("FinamiAppearance.json") }
  init(_ url: URL) { self.url = url }
SWIFT
# Compile the actual production method, not a duplicate implementation.
sed -n '/^  func loadDatabase() async {/,/^  @discardableResult func change/p' Finora/FinamiStore.swift | sed '$d' >> "$tmp/Load.swift"
cat >> "$tmp/Load.swift" <<'SWIFT'
}
@main struct Harness {
  @MainActor static func main() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Finora.json")
    let fresh = Store(url)
    await fresh.loadDatabase()
    precondition(fresh.ready && !fresh.loading && fresh.error == nil)
    print("PASS: fresh database opens")
    var db = Database(); db.budget = 42
    try JSONEncoder().encode(db).write(to: url)
    let valid = Store(url)
    await valid.loadDatabase()
    precondition(valid.ready && !valid.loading && valid.error == nil && valid.db.budget == 42)
    print("PASS: existing database opens and retains data")
    let broken = Data("invalid JSON".utf8)
    try broken.write(to: url)
    let invalid = Store(url)
    await invalid.loadDatabase()
    precondition(!invalid.ready && !invalid.loading && invalid.error?.contains("Запис заблоковано") == true)
    let unchanged = try Data(contentsOf: url)
    precondition(unchanged == broken)
    print("PASS: corrupt database reports error, blocks writes and preserves original file")
    var unsafe = db
    unsafe.accounts[0].opening = Int64.min
    let unsafeBytes = try JSONEncoder().encode(unsafe)
    try unsafeBytes.write(to: url)
    let unsafeStore = Store(url)
    await unsafeStore.loadDatabase()
    precondition(!unsafeStore.ready && !unsafeStore.loading && unsafeStore.error?.contains("Запис заблоковано") == true)
    let unsafeUnchanged = try Data(contentsOf: url)
    precondition(unsafeUnchanged == unsafeBytes)
    print("PASS: valid JSON with unsafe money blocked before publication; original preserved")
    var inconsistent = db
    inconsistent.accounts.append(Account(id: "usd", name: "USD", currency: "USD"))
    inconsistent.currencyPreferences = .init(usdRate: "42")
    inconsistent.operations = [Operation(kind: .transfer, amount: 4200, account: "usd", destination: cash,
      groupedBankParts: [.init(key: "leg", date: Date(), amount: 4199, note: "Test")],
      sourceMinor: 100, destinationMinor: 4200, entryCurrency: "USD", exchangeRate: "42")]
    let inconsistentBytes = try JSONEncoder().encode(inconsistent)
    try inconsistentBytes.write(to: url)
    let inconsistentStore = Store(url)
    await inconsistentStore.loadDatabase()
    precondition(!inconsistentStore.ready && !inconsistentStore.loading && inconsistentStore.error?.contains("Запис заблоковано") == true)
    precondition(inconsistentStore.error?.contains("Операція №1") == true)
    precondition(inconsistentStore.error?.contains(inconsistent.operations[0].id) == true)
    let unchangedGroup = try Data(contentsOf: url)
    precondition(unchangedGroup == inconsistentBytes)
    print("PASS: inconsistent grouped conversion blocked at startup; original bytes preserved")
    db.appearanceRevision = "rev"
    db.preferences = AppearancePreferences()
    try JSONEncoder().encode(db).write(to: url)
    try broken.write(to: valid.appearanceURL)
    let sidecar = Store(url)
    await sidecar.loadDatabase()
    precondition(sidecar.ready && !sidecar.loading && sidecar.db.budget == 42 && sidecar.error?.contains("Налаштування оформлення") == true)
    print("PASS: corrupt appearance settings do not prevent financial data loading")
    try FileManager.default.removeItem(at: valid.appearanceURL)
    db.scanImages = ["legacy-photo": Data([12, 34, 56])]
    try JSONEncoder().encode(db).write(to: url)
    let migrated = Store(url)
    await migrated.loadDatabase()
    precondition(migrated.ready && !migrated.loading && migrated.error == nil && migrated.db.budget == 42)
    precondition(migrated.db.scanImages == nil && migrated.db.scanFileHashes?["legacy-photo"] != nil)
    let exported = try FinamiScanStorage.portable(migrated.db, file: url)
    precondition(exported.scanImages == db.scanImages && exported.scanFileHashes == nil)
    print("PASS: actual startup migrates legacy photos and portable backup preserves original bytes")
    let reopened = Store(url)
    await reopened.loadDatabase()
    precondition(reopened.db.scanFileHashes == migrated.db.scanFileHashes && reopened.db.scanImages == nil)
    print("PASS: actual startup reopens migrated database without remigration")
  }
}
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift Finora/FinamiDatabaseSafety.swift Finora/FinamiAppearanceStorage.swift Finora/FinamiScanFiles.swift Finora/FinamiScanStorage.swift Finora/FinamiSnapshotPolicy.swift Tests/StorageTestSupport.swift "$tmp/Load.swift" -o "$tmp/load"
"$tmp/load"
