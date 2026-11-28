#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
typealias F = FinamiAccountReportField
let old = Data(#"{"theme":"Crimson","mode":"system","font":"default","largeIcons":true,"glow":true}"#.utf8)
var p = try JSONDecoder().decode(AppearancePreferences.self, from: old)
check(p.reportsAccountFields == nil && F.selected(account: "pumb", preferences: p.reportsAccountFields) == F.allCases, "legacy preferences preserve detailed reports")
check(F.allCases.count == 13 && Set(F.allCases.map(\.rawValue)).count == 13, "13 unique independent report fields")
p.reportsAccountFields = F.updating(p.reportsAccountFields, account: "pumb", fields: F.compact)
check(F.selected(account: "pumb", preferences: p.reportsAccountFields) == [.expense, .income], "compact preset shows only expense and income")
check(F.selected(account: "otp", preferences: p.reportsAccountFields) == F.allCases, "other account retains detailed settings")
p.reportsAccountFields = F.updating(p.reportsAccountFields, account: "otp", fields: [])
check(F.selected(account: "otp", preferences: p.reportsAccountFields).isEmpty, "all fields can be hidden without resetting defaults")
check(F.selected(account: "pumb", preferences: p.reportsAccountFields) == F.compact, "editing second account leaves first unchanged")
let restored = try JSONDecoder().decode(AppearancePreferences.self, from: JSONEncoder().encode(p))
check(F.selected(account: "pumb", preferences: restored.reportsAccountFields) == F.compact && F.selected(account: "otp", preferences: restored.reportsAccountFields).isEmpty, "per-account settings survive JSON reload")
let custom = F.updating(restored.reportsAccountFields, account: "pumb", fields: [.net, .expense, .expense])
check(F.selected(account: "pumb", preferences: custom) == [.expense, .net], "custom selection uses stable order and removes duplicates")
check(F.selected(account: "pumb", preferences: ["pumb": ["unknownFutureField", "income"]]) == [.income], "unknown future field ignored safely")
var t = FinamiReportTotals(); t.income = 10000; t.expense = 2500; t.transfersIn = 300; t.review = 2
check(F.allCases.filter { $0.isVisible(in: t, showIncome: true) } == [.expense, .income, .transfersIn, .net, .review], "only nonzero optional movements and existing review action shown")
check(F.allCases.filter { $0.isVisible(in: t, showIncome: false) } == [.expense, .transfersIn, .review], "global income hiding overrides account preferences")
check(F.income.amount(t) == 10000 && F.expense.amount(t) == 2500 && F.net.amount(t) == 7500, "selected fields use original report totals")
check(F.review.amount(t) == nil && !F.review.isVisible(in: FinamiReportTotals(), showIncome: true), "review action only when needed")
let all = F.updating(custom, account: "pumb", fields: F.allCases)
check(F.selected(account: "pumb", preferences: all) == F.allCases && F.selected(account: "otp", preferences: all).isEmpty, "restore detailed preset for one account only")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/FinamiReportCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
