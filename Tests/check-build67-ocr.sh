#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
func check(_ test: @autoclosure () -> Bool, _ message: String) { precondition(test(), message); print("PASS: " + message) }
let p = FinamiScanParser.self
// Synthetic values and dates; no private screenshot or original transaction data.
let rows = ["Сплачуйте частинами", "ПУМБ", "12 000,00 ₴", "Оформлено 15.10.2026", "Внесено 2 з 3 щомісячних платежів", "Наступний платіж Залишилося", "0,00 ₴ 4 000,00 ₴", "до 15.12.2026 до 15.01.2027", "Внести платіж Сплатити повністю", "Вносьте платіж до 18:00"]
let a = p.installment(rows)
check(a.pumbParts && a.name == "ПУМБ · Сплачуйте частинами", "PUMB product header and suggested name")
check(a.total == 1200000 && a.remaining == 400000 && a.monthly == 400000, "all three monetary fields from structured PUMB layout")
check(a.paymentCount == 3 && a.paidCount == 2 && a.monthlyEstimated, "payment count and explicit estimate provenance")
check(a.nextAmount == 0 && a.bankNextDue == bankDate("15.12.2026"), "zero charge and bank date distinct from monthly amount")
check(a.opened == bankDate("15.10.2026") && a.finalDue == bankDate("15.01.2027") && a.due == a.finalDue, "separate three dates and first nonzero charge")
check(p.validInstallment(total:a.total!,remaining:a.remaining!,monthly:a.monthly!), "structured fields accepted by installment form")
let separate = Array(rows.prefix(5)) + ["Наступний платіж", "0,00 ₴", "до 15.12.2026", "Залишилося", "4 000,00 ₴", "до 15.01.2027"]
let b = p.installment(separate)
check(b.total == a.total && b.remaining == a.remaining && b.monthly == a.monthly && b.due == a.due, "separate cells from OCR")
let uneven = p.installment(rows.map { $0.replacingOccurrences(of:"4 000,00 ₴",with:"3 500,00 ₴") })
check(uneven.remaining == 350000 && uneven.monthly == nil, "partial or irregular amounts do not invent monthly payment")
let multiple = p.installment(rows.map { $0.replacingOccurrences(of:"2 з 3",with:"1 з 3").replacingOccurrences(of:"4 000,00 ₴",with:"8 000,00 ₴") })
check(multiple.monthly == 400000 && multiple.due == nil, "multiple remaining periods with zero charge require schedule confirmation")
let complete = p.installment(rows.map { $0.replacingOccurrences(of:"2 з 3",with:"3 з 3").replacingOccurrences(of:"4 000,00 ₴",with:"0,00 ₴") })
check(complete.remaining == 0 && complete.monthly == 400000, "fully paid loan retains regular instalment")
let regular = p.installment(rows.map { $0.replacingOccurrences(of:"0,00 ₴ 4 000",with:"4 000,00 ₴ 4 000") })
check(regular.nextAmount == 400000 && regular.due == regular.bankNextDue, "positive next charge retains next date")
let conflicting = p.installment(Array(rows.prefix(3)) + ["10 000 ₴"] + Array(rows.dropFirst(3)))
check(conflicting.total == nil && conflicting.monthly == nil,"competing header amounts not guessed")
check(p.installment(rows.map { $0.replacingOccurrences(of:"0,00 ₴",with:"0,00 USD") }).foreignCurrency, "foreign currency in combined row blocks UAH import")
let candidates = p.installmentCandidates(["0,00 ₴ 4 000,00 ₴", "до 15.12.2026 до 15.01.2027", "до 18:00"])
check(candidates.contains("0,00 ₴") && candidates.contains("4 000,00 ₴") && candidates.contains("15.12.2026") && candidates.contains("15.01.2027"), "both amounts and dates offered for manual assignment")
check(!candidates.contains("до 18:00"), "time excluded")
let merged = finamiMergeInstallments([a,b])
check(merged.conflicts.isEmpty && merged.draft.monthly == 400000 && merged.draft.bankNextDue == a.bankNextDue && merged.draft.monthlyEstimated, "Vision passes preserve structured evidence")
check(p.installment(["12 000 ₴"]).total == nil, "unrelated screenshot not assumed PUMB")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
