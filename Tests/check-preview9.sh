#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func require(_ b: @autoclosure () -> Bool, _ label: String) { if !b() { fatalError(label) }; print("PASS: " + label) }
let p = FinamiScanParser.self
let reference = bankDate("26.11.2026")!
// Transcribed screenshot layouts, with replaced product names and card masks. No raw image included.
let a = p.installment(["09:39", "Протеїн тестовий", "сироватковий TNT… 0%", "Розстрочка на 1 515.00 ₴", "5 із 10 757.50 ₴", "Платежів сплачено Залишилось", "Подивитися графік платежів", "7 грудня", "151.50 ₴", "Наступний платіж", "Деталі замовлення"], reference: reference)
require(a.total == 151500 && a.remaining == 75750 && a.monthly == 15150 && a.due == bankDate("07.12.2026") && a.name.contains("Протеїн"), "screenshot layout A: merged columns and yearless date")
let b = p.installment(["Маршрутизатор тестовий", "Розстрочка на 1 859.00 ₴", "1 із 5", "1 487.20 ₴", "Платежів сплачено", "Залишилось", "Подивитися графік платежів", "8 грудня", "371.80 ₴", "••1234", "Наступний платіж", "Дострокове закриття"], reference: reference)
require(b.total == 185900 && b.remaining == 148720 && b.monthly == 37180 && b.due == bankDate("08.12.2026"), "screenshot layout B: separate columns and card digits")
require(p.nextPaymentDate("7 січня", reference: reference) == bankDate("07.01.2027"), "next-year rollover")
require(p.nextPaymentDate("31 лютого", reference: reference) == nil, "impossible date rejected")
require(p.installmentCandidateAmount("7 грудня") == nil, "day never used as money")
let ambiguous = p.installment(["Товар", "Розстрочка на 2000 ₴", "900 ₴", "800 ₴", "Залишилось", "7 грудня", "100 ₴", "200 ₴", "Наступний платіж"], reference: reference)
require(ambiguous.remaining == nil && ambiguous.monthly == nil, "conflicting screenshot values not guessed")
let text = "Купівля\n20.00UAH\nEASYPAY*LIFECELL KYIV UA\n26-11-2026 09:47\nКредитна картка: *1234..."
let event = try captureMessage(text, account: "test-pumb")
require(event.minor == 2000 && event.merchant == "EASYPAY*LIFECELL KYIV UA" && event.clearPurchase && !event.incoming, "PUMB push: amount and merchant, credit card is not repayment")
let separated = try captureBankNotification(title: "Купівля", body: "20.00UAH\nEASYPAY*LIFECELL KYIV UA\n26-11-2026 09:47\nКредитна картка: *1234...", account: "test-pumb")
require(separated.minor == event.minor && separated.merchant == event.merchant && separated.messageFingerprint == event.messageFingerprint, "title and body supplied separately in Shortcuts")
require(event.date == bankDate("26.11.2026 09:47"), "PUMB push date, not import time")
let second = try captureMessage("Оплата\n10.00UAH\n26-11-2026 09:46\nРахунок: *1234\nДоступно: 34104.79UAH", account: "test-pumb")
require(second.minor == 1000 && !second.clearPurchase && second.merchant.isEmpty, "PUMB ambiguous payment: balance excluded, manual review")
let compact = try captureMessage("Купівля 20.00UAH EASYPAY*LIFECELL KYIV UA…", account: "test-pumb")
require(compact.minor == 2000 && !compact.clearPurchase, "truncated push remains draft")
let rows = p.transactions(["09:48", "Мобільний зв'язок", "EASYPAY*LIFECELL KYIV UA", "-20,00 ₴", "Кредитна картка •• 1234", "Баланс після 12 283,60 ₴", "Власні кошти 0,00 ₴", "Дата транзакції 26.11.2026 09:47"])
require(rows.count == 1 && rows[0].money?.minor == -2000 && rows[0].note == event.merchant && rows[0].date == event.date, "PUMB detail screenshot: amount, merchant, date, no balance")
let replay = try captureMessage(text, account: "test-pumb")
require(captureRepeatedMessage(replay, handled: captureRememberMessage(event, handled: [])), "same push cannot auto-post twice")
let otp = try captureMessage("OTP Bank: Оплата 100 грн; Магазин: Cafe", account: "test-otp")
require(otp.minor == 10000, "OTP bank name does not trigger security-code filter")
do { _ = try captureMessage("OTP Bank: Код підтвердження оплати 100 грн", account: "test-otp"); fatalError("security code accepted") } catch { print("PASS: security-code messages still rejected") }
require(finamiSharedShortcutURL("https://www.icloud.com/shortcuts/0123456789abcdef0123456789abcdef") != nil, "shared shortcut URL syntax")
require(finamiSharedShortcutURL("shortcuts://") == nil && finamiSharedShortcutURL("https://www.icloud.com.evil.invalid/shortcuts/0123456789abcdef0123456789abcdef") == nil && finamiSharedShortcutURL("https://www.icloud.com/shortcuts/placeholder") == nil, "invalid and spoofed shortcut URLs rejected")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/preview9-tests"
TZ=Europe/Kyiv "$tmp/preview9-tests"
