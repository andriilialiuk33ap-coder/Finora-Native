#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
func check(_ b: @autoclosure () -> Bool, _ name: String) { precondition(b(), name); print("PASS: " + name) }
let p = FinamiScanParser.self
func r(_ text: String, _ x: Double, _ y: Double, _ w: Double = 0.27, _ h: Double = 0.025) -> ScanTextRegion {
    .init(text: text, bounds: CGRect(x:x, y:y, width:w, height:h))
}
let columns = [r("Загальна сума розстрочки", 0.05, 0.80, 0.43), r("30 000,00 ₴",0.60,0.80), r("Поточний залишок",0.05,0.68,0.43), r("15 000,00 ₴",0.60,0.68), r("Щомісячний платіж",0.05,0.56,0.43), r("2 500,00 ₴",0.60,0.56)]
let a = p.installmentLayout(columns)
check(a.total == 3000000 && a.remaining == 1500000 && a.monthly == 250000,"three labelled values across rows")
let stacked = [r("Загальна сума",0.04,0.90,0.42),r("14 499,00 ₴",0.04,0.86,0.35),r("Залишилось",0.55,0.90,0.36),r("12 000,00 ₴",0.55,0.86,0.36),r("Щомісячний платіж",0.04,0.70,0.43),r("1 200,00 ₴",0.04,0.75,0.33)]
let b = p.installmentLayout(stacked)
check(b.total == 1449900 && b.remaining == 1200000 && b.monthly == 120000,"stacked cards, reverse order and independent columns")
check(p.installmentLayout(stacked.reversed()).remaining == 1200000,"observation order independent")
let bare = p.installmentLayout([r("Залишок",0.10,0.70),r("12 000,50",0.10,0.66)])
check(bare.remaining == 1200050,"bare decimal amount near exact label")
let noisy = p.installmentLayout([r("Щомісячний платіж",0.10,0.70),r("18:00",0.10,0.66),r("1336",0.10,0.74),r("6 із 12",0.55,0.70),r("01.12",0.55,0.75)])
check(noisy.monthly == nil,"time, card suffix, count and short date never money")
let unlabeled = p.installmentLayout([r("14 499,00 ₴",0.10,0.70)])
check(unlabeled.total == nil && unlabeled.remaining == nil && unlabeled.monthly == nil,"no financial meaning invented for unlabelled amount")
let ambiguous = p.installmentLayout([r("Загальний кредит",0.1,0.74),r("15 000 ₴",0.1,0.70),r("Поточний залишок",0.1,0.66)])
check(ambiguous.total == nil && ambiguous.remaining == nil,"two equally close labels cannot share one amount")
let duplicate = p.installmentLayout([r("Загальний кредит",0.1,0.8),r("10 000 ₴",0.6,0.8),r("Загальний кредит",0.1,0.5),r("20 000 ₴",0.6,0.5)])
check(duplicate.total == nil,"contradictory values for same label stay unresolved")
check(p.installmentLayout([r("Залишок",0.1,0.8),r("100 USD",0.6,0.8)]).foreignCurrency,"foreign amount flagged")
check(p.installmentLayout([r("Дата щомісячного платежу",0.1,0.8),r("2500,00 ₴",0.6,0.8)]).monthly == nil,"date label not payment label")
check(p.installmentLayout([r("Загальний кредит",0.1,0.8),r("30 000 ₴",0.1,0.4)]).total == nil,"distant amount not linked")
let explicit = p.installment(["Загальна сума розстрочки: 14 499,00 ₴", "Залишок за розстрочкою: 12 000,00 ₴", "Щомісячний платіж за розстрочкою: 1 200,00 ₴"])
check(explicit.total == 1449900 && explicit.remaining == 1200000 && explicit.monthly == 120000,"additional explicit labels")
let combined = p.installment(["Загальна сума Залишилось", "14 499,00 ₴ 12 000,00 ₴", "Щомісячний платіж", "1 200,00 ₴"], regions: stacked)
check(combined.total == 1449900 && combined.remaining == 1200000 && combined.monthly == 120000,"full parser fills fields missed by linear reading")
let conflict = p.installment(["Загальний кредит 1000 ₴", "Загальний кредит 2000 ₴"], regions: columns)
check(conflict.total == nil,"layout must not override contradictory text values")
let moneyRow = "30 000,00 ₴ 15 000,00 ₴"
check(p.installmentSubregionRanges(moneyRow).map { String(moneyRow[$0]).trimmingCharacters(in: .whitespaces) } == ["30 000,00 ₴", "15 000,00 ₴"],"split two currency values for Vision substring coordinates")
let labelRow = "Загальна сума розстрочки Залишилось"
check(p.installmentSubregionRanges(labelRow).map { String(labelRow[$0]) } == ["Загальна сума розстрочки", "Залишилось"],"split two distinct labels without overlapping synonyms")
check(p.installmentSubregionRanges("Щомісячний платіж 2 500,00 ₴").isEmpty,"single label/value observation unchanged")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
