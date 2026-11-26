#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func require(_ result: @autoclosure () -> Bool, _ name: String) { precondition(result(), name); print("PASS: " + name) }
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: dir) }
var writes = 0
func handle(_ title: String?, _ body: String?, _ account: String? = "auto", _ bank: String? = nil) -> FinamiNotificationStatus {
    finamiHandleNotification(title: title, body: body, account: account, bank: bank) { e in writes += 1; try CaptureInbox.enqueue(e, in: dir) }
}
require(handle(nil, nil) == .empty, "manual run without input is silent")
require(handle(nil, "  \n") == .empty, "whitespace input ignored")
require(handle(nil, "Сповіщення") == .missingPaymentType, "literal placeholder not a payment")
require(handle(nil, "Баланс 1234 UAH") == .missingPaymentType, "balance not a payment")
require(handle("Код підтвердження", "Оплата 20 грн 123456") == .ignored, "security code not queued")
require(handle("Оплата", "100 грн відхилена") == .ignored, "declined payment not queued")
require(handle("Оплата", "100 грн / 2 USD") == .ambiguous, "multiple currencies not queued")
require(handle(nil, "20.00UAH\nEASYPAY*LIFECELL KYIV UA\n26-11-2026 09:47\nКредитна картка: *1234") == .missingPaymentType, "missing notification title not guessed")
require(handle("Оплата", "100000000000.00 UAH") == .ambiguous, "oversize payment not queued")
require(handle("Оплата", "ПУМБ 20 грн", "auto", "Приват") == .ambiguous, "conflicting bank not queued")
require(writes == 0 && !FileManager.default.fileExists(atPath: dir.path), "rejected events never touch inbox")
let body = "20.00UAH\nEASYPAY*LIFECELL KYIV UA\n26-11-2026 09:47\nКредитна картка: *1234"
require(handle("Купівля", body, " Auto ", "ПУМБ") == .queued, "split PUMB notification accepted")
require(handle(nil, "Оплата\n10.00UAH\n26-11-2026 09:46\nРахунок: *5678\nДоступно: 34104.79UAH", nil, "ПУМБ") == .queued, "second PUMB payment accepted for review")
let events = try CaptureInbox.read(in: dir)
require(events.count == 2 && writes == 2, "accepted events persisted to actual temporary inbox")
let first = events.first { $0.minor == 2000 }!
require(first.account == "auto" && first.bankHint == "pumb" && first.cardSuffix == "1234" && first.clearPurchase, "auto normalized and purchase metadata correct")
require(first.merchant == "EASYPAY*LIFECELL KYIV UA" && first.date == bankDate("26.11.2026 09:47"), "merchant and date preserved")
let second = events.first { $0.minor == 1000 }!
require(second.reportedAvailable == 3410479 && !second.clearPurchase, "available balance separated; merchantless payment reviewed")
let accounts = [FinamiCaptureAccount(id: "pumb-test", currency: "UAH", suffix: "1234", bank: "pumb")]
require(finamiCaptureRoute(first, accounts: accounts) == "pumb-test", "configured bank and card route correctly")
let failed = finamiHandleNotification(title: "Купівля", body: body, account: "auto", bank: "ПУМБ") { _ in throw CaptureError.storage }
require(failed == .storageError, "storage failure has separate diagnostic")
require(finamiNotificationSelfTest(), "read-only sample test passes")
require(writes == 2, "self-test creates no queued payment")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/AutomationCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
