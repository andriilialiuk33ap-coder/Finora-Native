#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ b: @autoclosure () -> Bool, _ name: String) { precondition(b(),name); print("PASS: " + name) }
let p = FinamiScanParser.self
let rows = ["14 499,00 ₴", "Вносьте платіж самостійно до 18:00, або ми спишемо кошти", "з картки ••1336 протягом дня, якщо там буде необхідна"]
check(p.installmentCandidateAmount(rows[0]) == 1449900,"visible amount preserved exactly")
check(p.installmentCandidates(rows) == [rows[0]],"time and masked card not offered as amounts")
let unknown = p.installment(rows)
check(unknown.total == nil && unknown.remaining == nil && unknown.monthly == nil,"unlabelled amount not silently assigned to contract fields")
let labels = p.installment(["ПУМБ", "Назва товару:", "Телефон 15", "Повна сума кредиту: 14 499,00 ₴", "Залишок за договором: 12 000,00 ₴", "Сума щомісячного платежу: 1 200,00 ₴", "Дата щомісячного платежу: 15.12.2026"])
check(labels.name == "Телефон 15" && labels.total == 1449900 && labels.remaining == 1200000 && labels.monthly == 120000 && labels.due == bankDate("15.12.2026"),"additional explicit PUMB-style labels and product number")
check(p.installment(["Початкова сума кредиту", "14 499,00 ₴", "Залишок за договором", "12 000,00 ₴", "Щомісячна сума", "1 200,00 ₴"]).monthly == 120000,"separate label/value rows")
check(p.installmentCandidateAmount("Графік: 12 платежів") == nil,"schedule count excluded")
check(p.installmentCandidateAmount("Картка ••1336") == nil,"card suffix excluded")
check(p.installmentCandidateAmount("Дата платежу: 18:00") == nil,"time excluded")
let merged = finamiMergeInstallments([labels, p.installment(["Повна сума кредиту 14999 ₴"])])
check(merged.draft.total == nil && merged.draft.remaining == 1200000 && !merged.conflicts.isEmpty,"dual OCR conflicting sum not guessed")
check(p.installmentCandidateAmount("14 499,00 USD") == nil,"foreign amount not used as UAH")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
