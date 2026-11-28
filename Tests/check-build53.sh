#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(),label); print("PASS: " + label) }
let date = Date(timeIntervalSince1970: 1700000000)
let bank = Account(id:"bank", name:"Bank")
let purchase = Operation(id:"purchase",kind:.expense,amount:10000,date:date,category:"Food",note:"Shop",account:bank.id,bankKey:"import-key",sourceBank:"PUMB",importBatch:"batch",scanFingerprint:"photo",tags:["home"])
let income = Operation(id:"income",kind:.income,amount:20000,date:date.addingTimeInterval(1),category:"Salary",account:bank.id)
let refund = Operation(id:"refund",kind:.refund,amount:2500,date:date.addingTimeInterval(2),category:"Food",account:bank.id)
let transfer = Operation(id:"transfer",kind:.transfer,amount:9000,date:date.addingTimeInterval(3),account:bank.id,destination:"cash")
let fee = Operation(id:"fee",kind:.movementOut,amount:1100,date:date.addingTimeInterval(4),account:bank.id,sourceBank:"А-БАНК",originalAmount:1000,originalCurrency:"UAH",bankFee:100)
let rows = [purchase,income,refund,transfer,fee]
let metrics = FinamiDashboardMetrics(operations:rows)
check(metrics.income == 20000, "income counts only true income")
check(metrics.expense == 7600, "refund and eligible fee retained, transfer excluded")
check(metrics.categories.map(\.key) == ["Food","🏦 Комісії"] && metrics.categories.map(\.value) == [7500,100], "category net amounts retained")
check(metrics.recent.map(\.id) == ["fee","transfer","refund","income","purchase"], "latest five sorted")
let empty = FinamiDashboardMetrics(operations:[])
check(empty.income == 0 && empty.expense == 0 && empty.categories.isEmpty && empty.recent.isEmpty, "empty overview")
let negative = FinamiDashboardMetrics(operations:[refund])
check(negative.expense == -2500 && negative.categories.isEmpty, "negative net retained, positive category filtering unchanged")
let next = FinamiRepeatDraft.make(purchase,accounts:[bank],masked:false,now:date.addingTimeInterval(100))!
check(next.id != purchase.id && next.date != purchase.date && next.amount == purchase.amount && next.category == purchase.category && next.note == purchase.note && next.tags == purchase.tags, "repeat creates a fresh manual draft with intended fields")
check(next.bankKey == nil && next.sourceBank == nil && next.importBatch == nil && next.scanFingerprint == nil && next.destination.isEmpty && next.groupedBankParts == nil, "repeat never copies import identity or links")
check(FinamiRepeatDraft.make(purchase,accounts:[bank],masked:true) == nil, "global privacy blocks repeat")
var hidden = bank; hidden.hideAmounts = true
check(FinamiRepeatDraft.make(purchase,accounts:[hidden],masked:false) == nil, "account privacy blocks repeat")
check(FinamiRepeatDraft.make(purchase,accounts:[],masked:false) == nil, "missing account blocks repeat")
var usd = bank; usd.currency = "USD"
check(FinamiRepeatDraft.make(purchase,accounts:[usd],masked:false) == nil, "foreign currency excluded from repeat")
check(FinamiRepeatDraft.make(transfer,accounts:[bank],masked:false) == nil && FinamiRepeatDraft.make(refund,accounts:[bank],masked:false) == nil && FinamiRepeatDraft.make(fee,accounts:[bank],masked:false) == nil, "complex operations excluded from repeat")
let large = (0..<50000).map { i -> Operation in
    var o = rows[i % rows.count]; o.id = String(i); o.date = date.addingTimeInterval(Double(i)); return o
}
let start = Date()
let largeMetrics = FinamiDashboardMetrics(operations:large)
let elapsed = Date().timeIntervalSince(start) * 1000
let refIncome = large.reduce(Int64(0)) { $0 + ($1.kind == .income ? $1.amount : 0) }
let refExpense = large.reduce(Int64(0)) { $0 + $1.expenseValue }
let refCategories = Dictionary(grouping:large.filter { $0.expenseValue != 0 },by: { $0.expenseGroup }).mapValues { $0.reduce(Int64(0)) { $0 + $1.expenseValue } }.filter { $0.value > 0 }
check(largeMetrics.income == refIncome && largeMetrics.expense == refExpense, "50k rows match previous totals")
check(Dictionary(uniqueKeysWithValues:largeMetrics.categories.map { ($0.key,$0.value) }) == refCategories, "50k category totals match previous calculation")
check(largeMetrics.recent.map(\.id) == Array(large.sorted { $0.date > $1.date }.prefix(5)).map(\.id), "50k latest records match full sort")
print("BENCH: 50,000 synthetic records, metrics only: \(elapsed) ms (Linux, not iPhone)")
SWIFT
swiftc -O -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/FinamiQualityCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
