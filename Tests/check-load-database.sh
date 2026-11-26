#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/Load.swift" <<'SWIFT'
import Foundation
struct AppearancePreferences: Codable { var theme = "base" }
struct Database: Codable { var preferences: AppearancePreferences? = AppearancePreferences(); var appearanceRevision: String? = nil; var marker = 0 }
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
sed -n '/^  func loadDatabase() async {/,/^  @discardableResult func change/p' Finora/Finora.swift | sed '$d' >> "$tmp/Load.swift"
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
    var db = Database(); db.marker = 42
    try JSONEncoder().encode(db).write(to: url)
    let valid = Store(url)
    await valid.loadDatabase()
    precondition(valid.ready && !valid.loading && valid.error == nil && valid.db.marker == 42)
    print("PASS: existing database opens and retains data")
    let broken = Data("invalid JSON".utf8)
    try broken.write(to: url)
    let invalid = Store(url)
    await invalid.loadDatabase()
    precondition(!invalid.ready && !invalid.loading && invalid.error?.contains("Запис заблоковано") == true)
    let unchanged = try Data(contentsOf: url)
    precondition(unchanged == broken)
    print("PASS: corrupt database reports error, blocks writes and preserves original file")
    db.appearanceRevision = "rev"
    try JSONEncoder().encode(db).write(to: url)
    try broken.write(to: valid.appearanceURL)
    let sidecar = Store(url)
    await sidecar.loadDatabase()
    precondition(sidecar.ready && !sidecar.loading && sidecar.db.marker == 42 && sidecar.error?.contains("Налаштування оформлення") == true)
    print("PASS: corrupt appearance settings do not prevent financial data loading")
  }
}
SWIFT
swiftc -swift-version 5 -warnings-as-errors Finora/FinamiAppearanceStorage.swift "$tmp/Load.swift" -o "$tmp/load"
"$tmp/load"
