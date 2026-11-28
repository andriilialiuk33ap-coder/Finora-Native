#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
struct Snapshot: Codable { var accounts: [Account]; var operations: [Operation]; var preferences: AppearancePreferences }
let date = Date(timeIntervalSince1970: 1_800_000_000)
let credit = Account(id: "qa-design-credit", name: "QA Credit Card", opening: -10000, accountType: "credit", creditLimit: 100000)
let debit = Account(id: "qa-design-debit", name: "QA Debit", opening: 50000, accountType: "debit")
let old = Operation(id: "old", kind: .expense, amount: 1500, date: date.addingTimeInterval(-1), account: credit.id)
let net = CardPosition.netFrom(own: 0, used: 25000)!
let updated = finamiAnchoredAccount(credit, operations: [old], net: net, at: date, estimated: false, now: date)!
check(updated.id == credit.id && updated.limit == credit.limit && updated.isCredit && updated.opening == -23500, "anchor keeps account identity, credit limit and exact adjusted opening")
check(updated.reconciliationDate == date && updated.reconciliationNet == -25000 && updated.reconciliationEstimated == false, "complete confirmed anchor")
var p = AppearancePreferences(); p.modernAccountGrid = true; p.designLayout = "grid"; p.accountsMode = "all"
let snapshot = Snapshot(accounts: [updated, debit], operations: [old], preferences: p)
let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
defer { try? FileManager.default.removeItem(at: file) }
try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
let restored = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
let a = restored.accounts[0]
let balance = FinamiLedgerIndex(operations: restored.operations, accounts: restored.accounts).balance(a)
let position = CardPosition(net: balance, limit: a.limit)
check(balance == -25000 && position.used == 25000 && position.unused == 75000, "atomic JSON roundtrip: -250 net, 250 used, 750 available")
check(a.reconciliationDate == date && a.reconciliationNet == -25000 && a.reconciliationEstimated == false, "saved control point survives reload")
check(restored.operations == [old] && restored.accounts[1].opening == debit.opening, "history and other accounts unchanged")
check(restored.preferences.finamiLayout == "grid" && restored.preferences.accountsMode == "all", "layout and account filter survive same roundtrip")
let historical = Operation(kind: .expense, amount: 3000, date: date.addingTimeInterval(-2), account: a.id)
let later = Operation(kind: .expense, amount: 1000, date: date.addingTimeInterval(1), account: a.id)
check(FinamiLedgerIndex(operations: [old, historical], accounts: [a]).balance(a) == -25000, "late historical imports do not alter control balance")
check(FinamiLedgerIndex(operations: [old, later], accounts: [a]).balance(a) == -26000, "new payments after control date still change balance")
check(finamiAnchoredAccount(credit, operations: [], net: net, at: date.addingTimeInterval(1), estimated: false, now: date) == nil, "future anchor rejected")
check(finamiAnchoredAccount(credit, operations: [], net: Int64.max, at: date, estimated: false, now: date) == nil, "out of range anchor rejected")
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiStatementMatch.swift Finora/FinamiBalanceCore.swift Finora/FinamiDesignPolicy.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
