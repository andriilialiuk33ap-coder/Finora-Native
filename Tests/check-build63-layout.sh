#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^enum DashboardKind:/,/^extension DashboardKind/p' Finora/IzanamiFeatures.swift | sed '$d'; sed -n '/^enum DashboardSize:/,/^struct DashboardSettings:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
var old = DashboardItem.defaults
old.swapAt(0, 1); old[0].enabled = true; old[0].size = .small; old[0].template = "Glass"; old[0].hideAmounts = false
let preset = FinamiDashboardLayoutPreset.capture(old, collapsed: [old[0].id])
let data = try JSONEncoder().encode(preset)
let decoded = try JSONDecoder().decode(FinamiDashboardLayoutPreset.self, from: data)
var current = DashboardItem.defaults
let i = current.firstIndex { $0.id == old[0].id }!
current[i].hideAmounts = true; current[i].categorySelection = ["Private"]; current[i].showPaymentNames = false
let result = decoded.applying(to: current, collapsed: [])
check(result.items.map(\.id) == old.map(\.id), "layout order restored")
check(result.items[0].enabled && result.items[0].size == .small && result.items[0].template == "Glass", "layout style restored")
check(result.items[0].hideAmounts == true && result.items[0].showPaymentNames == false, "layout cannot override privacy")
check(result.items[0].categorySelection == ["Private"], "layout retains live category filters")
check(result.collapsed == [old[0].id], "layout collapse restored")
var partial = decoded; partial.blocks = [decoded.blocks[0],decoded.blocks[0]]; partial.collapsed += ["unknown"]
let restored = partial.applying(to: current, collapsed: [current.last!.id])
check(restored.items.count == current.count && Set(restored.items.map(\.id)).count == current.count, "duplicate and unknown layout IDs cannot lose blocks")
check(restored.collapsed.contains(current.last!.id) && !restored.collapsed.contains("unknown"), "new blocks retain live collapse state")
SWIFT
swiftc "$tmp/Models.swift" Finora/FinamiDashboardLayoutCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
