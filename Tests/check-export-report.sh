#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(),name); print("PASS: " + name) }
let date = Date(timeIntervalSince1970: 1800000000)
let ops = [Operation(kind:.income,amount:10000,date:date,category:"Salary",account:"a"), Operation(kind:.expense,amount:2500,date:date,category:"Food",note:"=TEST()",account:"a"), Operation(kind:.refund,amount:500,date:date,category:"Food",account:"a"), Operation(kind:.transfer,amount:1000,date:date,account:"a",destination:"b"), Operation(kind:.unclassifiedCredit,amount:700,date:date,account:"a")]
let report = FinamiExportReport(operations:ops,account:nil,accountNames:["a":"Example","b":"Other"],includeAmounts:true,includeNotes:true)
let sheets = Dictionary(uniqueKeysWithValues:report.sheets.map{($0.name,$0.rows)})
check(report.sheets.count == 6 && report.operationRows.count == 6,"actual report builder produces six base sheets")
check(sheets["Доходи"]?.count == 2 && sheets["Витрати"]?.count == 3,"income sheet excludes transfers; expenses include refunds")
check(sheets["Підсумок"]?[1][1].text == "100" && sheets["Підсумок"]?[2][1].text == "122" && sheets["Підсумок"]?[3][1].text == "20" && sheets["Підсумок"]?[4][1].text == "80","report totals match ledger report semantics")
check(sheets["Категорії"]?[1][1].text == "25" && sheets["Місяці"]?[1][3].text == "20","gross category and net month totals preserved")
check(report.operationRows[2][2].numeric && report.operationRows[2][6].text == "=TEST()","numeric amounts and original notes preserved")
check(String(data:report.csvData,encoding:.utf8)?.contains("'=TEST()") == true,"CSV protects formula-like descriptions")
let hidden = FinamiExportReport(operations:ops,account:nil,accountNames:["a":"Рахунок 1"],includeAmounts:false,includeNotes:false)
check(hidden.operationRows.dropFirst().allSatisfy{ !$0[2].numeric && $0[2].text == "—" && $0[6].text.isEmpty && $0[10].text.isEmpty },"privacy hides amounts, notes and rate")
let empty = FinamiExportReport(operations:[],account:nil,accountNames:[:],includeAmounts:true,includeNotes:true)
check(empty.sheets.count == 6 && empty.operationRows.count == 1,"empty period exports header without error")
let account = FinamiExportReport(operations:[ops[3]],account:"b",accountNames:[:],includeAmounts:true,includeNotes:false)
check(account.sheets[0].rows[2][1].text == "10" && account.sheets[0].rows[1][1].text == "0","destination account transfer not counted as income")
check(sheets["Категорії"]?[1][2].text == "20", "net category agrees with summary while gross remains available")
let mixed = FinamiExportReport(operations:ops,account:"b",accountNames:[:],includeAmounts:true,includeNotes:true)
check(mixed.operationRows.count == 2 && mixed.sheets[4].rows.count == 1 && mixed.sheets[2].rows.count == 1, "account-filtered export excludes unrelated rows and categories")
check(hidden.sheets[2].rows.dropFirst().allSatisfy { $0[1].text == "—" && $0[2].text == "—" }, "both gross and net category columns respect masking")
check(report.operationRows[3][11].text == "-5" && hidden.operationRows[3][11].text == "—", "refund contribution explicit and privacy preserved")
let parts = finamiWorkbookParts(report.sheets)
check(parts["xl/worksheets/sheet5.xml"] != nil,"real prepared report generates workbook XML")
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/FinamiReportCore.swift Finora/FinamiExportCore.swift Finora/FinamiExportReport.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
