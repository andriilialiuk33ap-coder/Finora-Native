#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; sed -n '/^enum OperationSort:/,/^func ruleKey/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(),label); print("PASS: " + label) }
let names = ["bank":"ПУМБ", "cash":"Готівка", "mono":"Monobank"]
let expense = Operation(id:"e",kind:.expense,amount:125050,category:"Продукти",note:"Сільпо",account:"bank",tags:["дім"])
let transfer = Operation(id:"t",kind:.transfer,amount:77725,note:"Власний переказ",account:"bank",destination:"mono")
let ops = [expense, transfer]
func search(_ term: String, hidden: Bool = false, masked: Set<String> = []) -> [String] {
    FinamiHistoryQuery(kind:"all",account:"all",category:"all",search:term,sort:.newest,hideAmounts:hidden).apply(to:ops,names:names,maskedAccounts:masked).map(\.id)
}
check(search("1250,50") == ["e"], "Ukrainian decimal amount")
check(search("1 250,50") == ["e"], "grouped Ukrainian amount")
check(search("1\u{202F}250,50") == ["e"], "narrow no-break thousands separator")
check(search("1250.50") == ["e"], "legacy dot amount")
check(search("  СІЛЬПО  ") == ["e"], "trim and case-insensitive merchant")
check(search("Продукти 1250.50") == ["e"], "legacy combined category and amount")
check(search("дім") == ["e"], "tag search")
check(search("Monobank") == ["t"], "destination account search")
check(search("777,25",masked:["mono"]).isEmpty, "destination mask hides amount")
check(search("1250,50",masked:["bank"]).isEmpty, "source mask hides amount")
check(search("1250,50",hidden:true).isEmpty, "global mask hides amount")
check(search("Сільпо",hidden:true) == ["e"], "masked merchant still searchable")
check(Set(search("   ")) == Set(["e","t"]), "blank search returns all")
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/FinamiHistoryQuery.swift Finora/MoneyCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
