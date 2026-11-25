#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; sed -n '/^enum DashboardKind:/,/^extension DashboardKind/p' Finora/IzanamiFeatures.swift | sed '$d'; sed -n '/^enum DashboardSize:/,/^struct DashboardSettings:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let old = Data(#"{"theme":"Crimson","mode":"system","font":"default","largeIcons":true,"glow":true}"#.utf8)
var p = try JSONDecoder().decode(AppearancePreferences.self,from:old)
precondition(p.accountsLayout == nil && p.homeTitle == nil && p.voiceHideHint == nil)
p.accountsLayout="split";p.homeTitle="Головна";p.voiceHideHint=true;p.operationsFilter="all"
let round = try JSONDecoder().decode(AppearancePreferences.self,from:JSONEncoder().encode(p))
precondition(round.accountsLayout=="split" && round.homeTitle=="Головна" && round.voiceHideHint==true && round.operationsFilter=="all")
let legacy = Data(#"{"kind":"accounts","enabled":true,"size":"Великий"}"#.utf8)
var item = try JSONDecoder().decode(DashboardItem.self,from:legacy)
precondition(item.hideAmounts == nil)
item.hideAmounts=true
let copy = try JSONDecoder().decode(DashboardItem.self,from:JSONEncoder().encode(item))
precondition(copy.hideAmounts==true && copy.kind == .accounts && copy.enabled)
precondition(DashboardItem.merged([copy]).first?.hideAmounts==true)
print("PASS: Preview 2 legacy preferences, dashboard privacy and settings roundtrip")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/preview2-tests"
"$tmp/preview2-tests"
