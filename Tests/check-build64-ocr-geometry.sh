#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
func check(_ b: @autoclosure () -> Bool, _ label: String) { precondition(b(), label); print("PASS: " + label) }
let suite = "finami.ocr.geometry.test." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
func r(_ text: String, _ x: Double, _ y: Double) -> ScanTextRegion { .init(text: text, bounds: CGRect(x:x,y:y,width:0.25,height:0.025)) }
let first = [r("Загальна сума",0.05,0.8),r("Щомісячний платіж",0.05,0.5),r("14 499,00 ₴",0.6,0.8),r("1 200,00 ₴",0.6,0.5)]
let next = [r("Загальна сума",0.05,0.8),r("Щомісячний платіж",0.05,0.5),r("15 000,00 ₴",0.6,0.8),r("1 250,00 ₴",0.6,0.5)]
let p = FinamiOCRLayoutMemory.self
check(p.signature(bank: "ПУМБ", regions: first) == p.signature(bank: "ПУМБ", regions: next), "layout signature excludes amounts")
p.learn(bank: "ПУМБ", regions: first, chosen: first[2], field: .total, defaults: defaults)
p.learn(bank: "ПУМБ", regions: first, chosen: first[3], field: .monthly, defaults: defaults)
check(p.suggestions(bank: "ПУМБ", regions: next, defaults: defaults) == [.total:1500000,.monthly:125000], "same layout proposes current amounts")
check(p.suggestions(bank: "monobank", regions: next, defaults: defaults).isEmpty, "different bank cannot reuse learned positions")
check(p.suggestions(bank: "ПУМБ", regions: [next[0],r("Щомісячний платіж",0.05,0.2),next[2],next[3]], defaults: defaults).isEmpty, "changed anchors invalidate layout")
check(p.suggestions(bank: "ПУМБ", regions: [next[0],next[1],next[2],next[3],r("16 000 ₴",0.605,0.8)], defaults: defaults)[.total] == nil, "ambiguous position is not suggested")
p.learn(bank: "ПУМБ", regions: first, chosen: first[2], field: .remaining, defaults: defaults)
check(p.suggestions(bank: "ПУМБ", regions: next, defaults: defaults)[.remaining] == nil, "two fields cannot learn same position")
check(p.signature(bank: "ПУМБ", regions: [first[0],first[2]]) == nil, "insufficient structural evidence")
check(p.suggestions(bank: "ПУМБ", regions: next + [r("20 USD",0.05,0.2)], defaults: defaults).isEmpty, "foreign currency rejects position suggestion")
let data = String(data: defaults.data(forKey:p.storageKey)!, encoding:.utf8)!
check(!data.contains("14499") && !data.contains("1200"), "stored geometry contains no historical amounts")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift Finora/FinamiOCRLayoutCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
