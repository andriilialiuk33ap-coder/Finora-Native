#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ ok: @autoclosure () -> Bool, _ label: String) { precondition(ok(), label); print("PASS: " + label) }
let p = FinamiScanParser.self
// Transcribed layout; synthetic card suffix. No screenshot or personal card identifiers committed.
let lines = ["14:51", "YouTube Premium", "-179.00 UAH", "28.11.2026, 12:16", "Статус Успішно", "З картки", "1234 •••• •••• 5678", "Універсальна", "Залишок -178.88 UAH", "Категорія Цифрові товари", "Розділити оплату", "Допомога Онлайн"]
let rows = p.transactions(lines)
check(rows.count == 1, "one transaction, not account balance")
check(rows.first?.money == ScanMoney(minor: -17900, currency: "UAH", signed: true), "exact signed expense in minor units")
check(rows.first?.note == "YouTube Premium", "merchant recognized")
check(rows.first?.date == bankDate("28.11.2026 12:16"), "full timestamp including time")
check(p.date("28.11.2026,12:16") == rows.first?.date, "comma without space")
check(p.bank(lines.joined(separator: "\n")) == "ПриватБанк", "bank layout")
check(p.cardSuffix(lines) == "5678", "masked card suffix")
check(p.monthlySubscription(rows.first!.note) == "YouTube Premium", "subscription suggestion")
check(p.nextMonthlySubscriptionDate(rows.first!.date!) == bankDate("28.12.2026 12:16"), "next monthly due date")
check(p.monthlySubscription("YouTube") == nil, "plain merchant does not prove subscription")
check(p.transactions(lines.map { $0.replacingOccurrences(of: "Успішно", with: "Неуспішно") }).isEmpty, "failed payment not imported")
check(p.transactions(lines.map { $0.replacingOccurrences(of: "-179.00 UAH", with: "") }).isEmpty, "missing payment does not import balance")
check(p.transactions(lines.map { $0.replacingOccurrences(of: "Залишок -178.88 UAH", with: "Залишок\n-178.88 UAH") }.flatMap { $0.components(separatedBy: "\n") }).count == 1, "separate balance row")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
