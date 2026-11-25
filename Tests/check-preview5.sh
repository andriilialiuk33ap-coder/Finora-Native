#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let legacy = Data(#"{"theme":"Crimson","mode":"system","font":"default","largeIcons":true,"glow":true}"#.utf8)
var p = try JSONDecoder().decode(AppearancePreferences.self, from: legacy)
precondition(p.reportsHiddenSections == nil)
p.reportsHiddenSections = ["flow", "categories"]
p.noCharts = true
let restored = try JSONDecoder().decode(AppearancePreferences.self, from: JSONEncoder().encode(p))
precondition(restored.reportsHiddenSections == ["flow", "categories"] && restored.noCharts == true)
print("PASS: Preview 5 legacy preferences and independent report privacy")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/tests"
"$tmp/tests"
