#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; sed -n '/^enum Kind:/,/^enum ObligationKind:/p' Finora/Finora.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ test: @autoclosure () -> Bool, _ label: String) { precondition(test(), label); print("PASS: " + label) }
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 26))!
let ops = [
 Operation(kind: .income, amount: 100000, date: day, account: "pumb"),
 Operation(kind: .expense, amount: 30000, date: day, account: "pumb"),
 Operation(kind: .refund, amount: 5000, date: day, account: "pumb"),
 Operation(kind: .transfer, amount: 10000, date: day, account: "otp", destination: "pumb"),
 Operation(kind: .transfer, amount: 20000, date: day, account: "pumb", destination: "privat"),
 Operation(kind: .movementIn, amount: 1000, date: day, account: "pumb"),
 Operation(kind: .movementOut, amount: 2000, date: day, account: "pumb"),
 Operation(kind: .unclassifiedCredit, amount: 3000, date: day, account: "pumb"),
 Operation(kind: .unclassifiedDebit, amount: 4000, date: day, account: "pumb"),
 Operation(kind: .creditDraw, amount: 50000, date: day, account: "pumb"),
 Operation(kind: .creditRepaymentIncoming, amount: 6000, date: day, account: "pumb"),
 Operation(kind: .creditRepayment, amount: 7000, date: day, account: "pumb")
]
let x = FinamiReportSnapshot(operations: ops, date: day, annual: true, account: nil, calendar: cal)
let p = x.accounts["pumb"]!
check(p.income == 100000 && p.expense == 25000 && p.refunds == 5000 && p.net == 75000, "PUMB income, net spending and refunds")
check(p.transfersIn == 11000 && p.transfersOut == 22000, "PUMB incoming and outgoing transfers by direction")
check(p.unclassifiedIn == 3000 && p.unclassifiedOut == 4000 && p.review == 2, "unclassified amounts visible, separate from income")
check(p.creditDraw == 50000 && p.creditTopUp == 6000 && p.creditRepayment == 7000, "credit flows kept separate")
check(x.accounts["privat"]?.transfersIn == 20000 && x.accounts["otp"]?.transfersOut == 10000, "transfer-only accounts included")
check(x.totals.count == ops.count && x.totals.transfersIn == 31000 && x.totals.transfersOut == 32000, "aggregate counts transfers once and both directions once")
check(x.accounts.values.reduce(0) { $0 + $1.expense } == x.totals.expense && x.periods.values.reduce(0) { $0 + $1.expense } == x.totals.expense, "account and monthly spending reconciliation")
check(x.accounts.values.reduce(0) { $0 + $1.income } == x.totals.income && x.periods.values.reduce(0) { $0 + $1.income } == x.totals.income, "account and monthly income reconciliation")
let filtered = FinamiReportSnapshot(operations: ops, date: day, annual: false, account: "pumb", calendar: cal)
check(filtered.accounts.keys.sorted() == ["pumb"] && filtered.totals.transfersIn == p.transfersIn && filtered.totals.transfersOut == p.transfersOut, "account filter respects destination and direction")
check(Set(filtered.reviewIDs) == Set([ops[7].id, ops[8].id]), "review IDs scoped to unresolved entries")
var edited = ops; edited[7].kind = .income
let revised = FinamiReportSnapshot(operations: edited, date: day, annual: true, account: nil, calendar: cal)
check(revised.totals.income == 103000 && revised.totals.unclassifiedIn == 0 && revised.totals.review == 1 && edited[7].signedNative == ops[7].signedNative, "confirmed income updates report without changing balance")
let salary = try captureMessage("Зарплата 1000.00 UAH; Баланс 2000 UAH", account: "auto")
let cashback = try captureBankNotification(title: "Кешбек", body: "25.50 UAH", account: "auto")
let pension = try captureMessage("Надходження: пенсія 1500 UAH", account: "auto")
check([salary,cashback,pension].allSatisfy { $0.incoming && $0.incomeHint == true && !$0.clearPurchase }, "explicit income labels suggest review type, never automatic purchase")
let deposit = try captureMessage("Поповнення 1000 UAH", account: "auto")
check(deposit.incoming && deposit.incomeHint == nil, "ordinary deposit not income")
check(!finamiExplicitIncome("Кешбек до 100 UAH") && !finamiExplicitIncome("Зарплата переказ 100 UAH") && !finamiExplicitIncome("Купівля 100 UAH кешбек"), "ads and ambiguous movements not income hints")
check(bankKind(signed: 1000, note: "Переказ", mcc: nil, operationType: "Дохід", creditAccount: true) == "unclassifiedCredit", "transfer not income even with conflicting explicit label")
let bank = pumbRow(["2026-11-26 09:00:00", "100.00 UAH", "100.00 UAH", "0.00 UAH", "", "Зарплата", "Дохід"])!
check(bank.signed == 10000 && bankKind(signed: bank.signed, note: bank.note, mcc: nil, operationType: bank.operationType, creditAccount: true) == "income", "explicit PUMB income statement row")
let data = try JSONEncoder().encode(deposit)
let legacy = try JSONDecoder().decode(CapturedPayment.self, from: data)
check(legacy.incomeHint == nil && legacy == deposit, "old queued events decode without income hint")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/FinamiReportCore.swift Finora/BankCore.swift Finora/AutomationCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
