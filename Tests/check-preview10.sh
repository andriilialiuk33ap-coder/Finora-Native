#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func require(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS: " + name) }
let event = try captureMessage("ПУМБ Купівля 20 UAH EASYPAY 26-11-2026 09:47 Кредитна картка: *1234", account: "p1")
let accounts = [FinamiCaptureAccount(id:"p1",currency:"UAH",suffix:"9999",bank:"pumb"),FinamiCaptureAccount(id:"p2",currency:"UAH",suffix:"1234",bank:"pumb"),FinamiCaptureAccount(id:"o1",currency:"UAH",suffix:"1234",bank:"otp")]
require(event.cardSuffix == "1234" && event.bankHint == "pumb", "masked card and bank parsed")
require(finamiCaptureRoute(event, accounts: accounts) == "p2", "unique same-bank card routing")
require(finamiCaptureRoute(event, accounts: [accounts[0],accounts[2]]) == nil, "never route to different bank on suffix alone")
require(finamiCaptureRoute(event, accounts: accounts + [FinamiCaptureAccount(id:"p3",currency:"UAH",suffix:"1234",bank:"pumb")]) == nil, "duplicate card masks require review")
require(finamiCardSuffix("Рахунок: *1234 Картка: *4567") == nil, "multiple masks not guessed")
require(finamiCardSuffix("Картка: 1234567890123456") == nil, "full card number not retained")
let reference = bankDate("26.11.2026")!
let first = FinamiScanParser.installment(["Назва: Телефон", "Загальний кредит 3000 ₴"], reference: reference)
let second = FinamiScanParser.installment(["Поточний залишок 1500 ₴", "Щомісячний платіж 500 ₴"], reference: reference)
let merged = finamiMergeInstallments([first,second])
require(merged.draft.total == 300000 && merged.draft.remaining == 150000 && merged.draft.monthly == 50000 && merged.conflicts.isEmpty, "complementary screenshot fields combined")
var bad = second; bad.total = 200000
let conflict = finamiMergeInstallments([first,bad])
require(conflict.draft.total == nil && !conflict.conflicts.isEmpty, "conflicting contract amounts blank")
let schedule = finamiScheduleRows(["07.12.2026 500 ₴", "07.12.2026 500 ₴", "07.01.2027 500 ₴", "Залишок 07.02.2027 1500 ₴", "07.03.2027 500 ₴", "07.03.2027 700 ₴"], reference: reference)
require(schedule.count == 2 && schedule.allSatisfy { $0.amount == 50000 }, "schedule explicit rows, duplicate rows and conflicting dates excluded")
let ambiguous = try captureMessage("ПУМБ Оплата 10 UAH Картка: *1234 Рахунок: *9999 Доступно: 34104.79UAH", account: "p1")
require(ambiguous.ambiguousCard == true && finamiCaptureRoute(ambiguous, accounts: accounts) == nil, "multiple card masks block automatic routing")
require(ambiguous.reportedAvailable == 3410479 && ambiguous.minor == 1000, "bank available separated from actual transaction")
require(finamiReportedAvailable("Доступно: 100 USD", currency: "UAH") == nil, "balance currency mismatch rejected")
let old = Data(#"{"id":"test","date":0,"account":"cash","currency":"UAH","minor":123,"merchant":"Test","source":"Apple Pay","incoming":false,"clearPurchase":true}"#.utf8)
let decoded = try JSONDecoder().decode(CapturedPayment.self, from: old)
require(decoded.cardSuffix == nil && decoded.bankHint == nil, "legacy capture decodes")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
