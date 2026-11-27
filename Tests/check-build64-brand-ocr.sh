#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ test: @autoclosure () -> Bool, _ label: String) { precondition(test(), label); print("PASS: " + label) }
let names: [(String, FinamiBrand)] = [("ПУМБ кредит",.pumb),("MONOBANK black",.mono),("Приват24",.privat),("А-Банк",.abank),("Onlyy.One Spotify",.spotify),("NETFLIX.COM",.netflix),("SILPO 0342",.silpo),("АТБ-МАРКЕТ",.atb),("YouTube Premium",.youtube),("iCloud+",.icloud)]
for (text, brand) in names { check(FinamiBrand.match(text) == brand, "brand alias " + brand.rawValue) }
check(FinamiBrand.match("monopoly") == nil && FinamiBrand.match("atbxyz") == nil, "no substring collision")
check(FinamiBrand.match("ПУМБ Monobank") == nil, "ambiguous brand not guessed")
check(FinamiBrand.match("Spotify", banksOnly: true) == nil, "account match excludes merchants")
check(FinamiBrand.match("ПУМБ SILPO", merchantsOnly: true) == .silpo, "merchant filter excludes banks")
let suite = "finami.tests.ocr." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let p = FinamiOCRProfiles.self
check(p.banks.count == 7 && p.rules(nil, defaults: defaults).isEmpty, "seven profiles and universal fallback")
let fields = ["Сума оформленої розстрочки 14 499,00 ₴", "Залишок за тілом кредиту 9 666,00 ₴", "Щомісячний внесок за розстрочкою 1 208,25 ₴"]
let rewritten = fields.map { p.rewrite($0, rules: p.rules("ПУМБ", defaults: defaults)) }
let draft = FinamiScanParser.installment(rewritten)
check(draft.total == 1449900 && draft.remaining == 966600 && draft.monthly == 120825, "three explicit profile amounts")
check(p.rewrite(fields[0], rules: p.rules("monobank", defaults: defaults)) == fields[0], "profile isolated by bank")
check(p.rewrite("Сума оформленої розстрочки 100 USD", rules: p.rules("ПУМБ", defaults: defaults)).contains("USD"), "no FX conversion")
check(p.label("Щомісячний платіж 18:00") == nil && p.label("Номер кредиту 1234") == nil && p.label("Кредитний ліміт 100 ₴") == nil, "time and card/limit labels cannot train")
let custom = "Сума регулярного внеску 1 234,56 ₴"
p.learn(bank: "ПУМБ", raw: custom, field: .monthly, defaults: defaults)
check(p.learned("ПУМБ", defaults: defaults)["сума регулярного внеску"] == .monthly, "confirmed label learned")
check(p.learned("monobank", defaults: defaults).isEmpty, "learned rules isolated by bank")
let saved = String(data: defaults.data(forKey: p.storageKey)!, encoding: .utf8)!
check(!saved.contains("234") && !saved.contains("56"), "no transaction amount stored in rule")
check(p.rewrite("Сума регулярного внеску 2 000 UAH", rules: p.rules("ПУМБ", defaults: defaults)) == "Щомісячний платіж: 2000,00 ₴", "learned label applies next time with UAH")
p.learn(bank: "ПУМБ", raw: custom, field: .total, defaults: defaults)
check(p.learned("ПУМБ", defaults: defaults)["сума регулярного внеску"] == .monthly, "conflicting correction does not silently replace rule")
p.learn(bank: "ПУМБ", raw: "Щомісячний платіж 500 ₴", field: .total, defaults: defaults)
check(p.learned("ПУМБ", defaults: defaults)["щомісячний платіж"] == nil, "known monthly field cannot be learned as total")
p.learn(bank: "ПУМБ", raw: "12 000 ₴", field: .total, defaults: defaults)
check(p.learned("ПУМБ", defaults: defaults).count == 1, "unlabelled money cannot train")
func region(_ text: String, _ x: Double, _ y: Double) -> ScanTextRegion { .init(text: text, bounds: CGRect(x:x,y:y,width:0.32,height:0.025)) }
let regions = [region("Дата наступного платежу",0.05,0.80),region("07.12.2026",0.58,0.80)]
check(FinamiScanParser.installmentLayout(regions).due == bankDate("07.12.2026"), "spatial date recognition")
let mixed = finamiMergeInstallments([FinamiScanParser.installment(["Загальна сума: 1000 ₴"]), FinamiScanParser.installment(["Загальна сума: 2000 ₴"]), FinamiScanParser.installment(["Загальна сума: 1000 ₴"])])
check(mixed.draft.total == nil && mixed.conflicts.contains("Загальний кредит"), "third pass cannot resurrect conflicting amount")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift Finora/FinamiBrandCore.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
