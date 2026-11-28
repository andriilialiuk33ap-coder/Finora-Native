#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year:y,month:m,day:d))! }
let date = day(2026,11,25)
let ops = [
  Operation(kind:.income,amount:10000,date:date,account:"a"),
  Operation(kind:.expense,amount:4000,date:day(2026,11,1),category:"Food",account:"a"),
  Operation(kind:.refund,amount:1000,date:date,category:"Food",account:"a"),
  Operation(kind:.refund,amount:500,date:date,category:"Other",account:"a"),
  Operation(kind:.expense,amount:2000,date:date,category:"Car",account:"b",sourceMinor:50),
  Operation(kind:.transfer,amount:3000,date:date,account:"a",destination:"b"),
  Operation(kind:.creditRepayment,amount:1000,date:date,account:"a"),
  Operation(kind:.unclassifiedCredit,amount:900,date:date,account:"b"),
  Operation(kind:.expense,amount:100,date:day(2026,10,1),account:"a"),
  Operation(kind:.income,amount:200,date:day(2026,12,1),account:"b"),
  Operation(kind:.expense,amount:700,date:day(2025,12,31),account:"a")
]
let x = FinamiReportSnapshot(operations:ops,date:date,annual:false,account:nil,calendar:cal)
precondition(x.totals.income == 10000 && x.totals.expense == 4500 && x.totals.net == 5500 && x.totals.refunds == 1500 && x.totals.count == 8 && x.totals.review == 1)
print("PASS: monthly totals, net refunds, review, transfers and repayment exclusion")
precondition(x.previous.expense == 100 && x.previous.income == 0 && x.periods.count == 2)
precondition(x.categories.values.reduce(0,+) == x.totals.expense && x.sortedCategories.last?.value == -500)
print("PASS: previous month, half-open boundaries, signed category totals")
let a = FinamiReportSnapshot(operations:ops,date:date,annual:false,account:"a",calendar:cal)
let b = FinamiReportSnapshot(operations:ops,date:date,annual:false,account:"b",calendar:cal)
precondition(a.totals.expense == 2500 && a.totals.income == 10000 && b.totals.expense == 2000 && b.totals.income == 0 && b.totals.count == 3)
precondition(x.accounts["a"]?.expense == 2500 && x.accounts["b"]?.expense == 2000)
print("PASS: account filter, incoming transfers counted as activity only, recorded UAH amount")
let y = FinamiReportSnapshot(operations:ops,date:date,annual:true,account:nil,calendar:cal)
precondition(y.totals.income == 10200 && y.totals.expense == 4600 && y.previous.expense == 700 && y.periods.count == 3)
let empty = FinamiReportSnapshot(operations:[],date:date,annual:true,account:nil,calendar:cal)
precondition(empty.totals.count == 0 && empty.sortedCategories.isEmpty && empty.periods.isEmpty)
print("PASS: annual rollup and empty reports")
precondition(finamiReorderSubset(["a","hidden","b","c"],orderedSubset:["c","b","a"]) == ["c","hidden","b","a"])
precondition(finamiReorderSubset(["a","b"],orderedSubset:["a","a"]) == ["a","b"])
precondition(finamiReorderSubset(["a","b"],orderedSubset:["missing"]) == ["a","b"])
print("PASS: subset ordering preserves hidden slots and rejects invalid IDs")
let legacy = Data(#"{"theme":"Crimson","mode":"system","font":"default","largeIcons":true,"glow":true,"accountsLayout":"full"}"#.utf8)
var p = try JSONDecoder().decode(AppearancePreferences.self, from:legacy)
precondition(p.accountsHideOwn == nil && p.accountsHideCredit == nil && p.reportsPeriod == nil && p.accountsLayout == "full")
p.accountsHideOwn = true; p.accountsHideCredit = false; p.reportsPeriod = "month"; p.reportsAccount = "a"; p.reportsShowIncome = false; p.reportsCategoryLimit = 5
let restored = try JSONDecoder().decode(AppearancePreferences.self,from:JSONEncoder().encode(p))
precondition(restored.accountsHideOwn == true && restored.accountsHideCredit == false && restored.reportsPeriod == "month" && restored.reportsAccount == "a" && restored.reportsShowIncome == false && restored.reportsCategoryLimit == 5)
print("PASS: legacy preference compatibility and independent balance/report settings")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/FinamiReportCore.swift "$tmp/main.swift" -o "$tmp/tests"
"$tmp/tests"
