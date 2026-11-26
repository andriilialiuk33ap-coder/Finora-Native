#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; sed -n '/^enum Kind:/,/^struct Database:/p' Finora/Finora.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func require(_ condition: @autoclosure () -> Bool, _ label: String) { if !condition() { fatalError(label) }; print("PASS: " + label) }
let p = FinamiScanParser.self
require(p.money("АТБ −450,00 ₴") == ScanMoney(minor:-45000,currency:"UAH",signed:true), "signed UAH expense")
require(p.money("+ 1\u{202F}250,50 грн")?.minor == 125050, "narrow space thousands and decimal comma")
require(p.money("USD 12.34")?.currency == "USD" && p.money("USD 12.34")?.minor == 1234, "USD prefix")
require(p.money("01.12.2026") == nil && p.money("01.12.2026", allowBare:true) == nil, "date not interpreted as money")
require(p.money("450 ₴ / 12 USD") == nil, "ambiguous two currencies skipped")
require(p.money("12%", allowBare:true) == nil, "percentage not a money amount")
require(p.money("100 EUR", allowBare:true) == nil && p.installment(["Загальний кредит 100 EUR"]).foreignCurrency, "unsupported currency not converted silently")
require(p.transactions(["Кредитний ліміт", "50 000 ₴", "АТБ −450 ₴"]).count == 1, "separate balance amount not a transaction")
require(p.date("Дата 31.02.2026") == nil && p.date("25.11.2026 14:25") != nil, "calendar validation")
let rows = p.transactions(["monobank", "25.11.2026", "Баланс 10 000 ₴", "АТБ −450 ₴", "Кав'ярня", "-95,00 грн", "+ 2000 ₴", "Доступно 50000 грн"])
require(rows.count == 3 && rows[0].money?.minor == -45000 && rows[1].note == "Кав'ярня" && rows[2].money?.minor == 200000, "multiple transaction drafts, skip balance and credit")
require(rows.allSatisfy { $0.date == p.date("25.11.2026") }, "inherit date header for draft review")
let bare = p.transactions(["АТБ", "−450,00", "Доступно", "−5000,00", "Кава", "-95.50", "1234", "25.11.2026"])
require(bare.count == 2 && bare[0].money == ScanMoney(minor:-45000,currency:nil,signed:true) && bare[0].note == "АТБ" && bare[1].money?.minor == -9550, "signed currency-less rows remain drafts; balance and unsigned numbers ignored")
let inst = p.installment(["monobank", "Назва: Телефон", "Загальний кредит", "30 000,00 ₴", "Поточний залишок 15 000 ₴", "Щомісячний платіж 2 500 грн", "Наступний платіж 01.12.2026", "Вже сплачено 15 000 ₴"])
require(inst.total == 3000000 && inst.remaining == 1500000 && inst.monthly == 250000 && inst.due == p.date("01.12.2026") && inst.name == "Телефон", "installment labelled and next-line fields")
require(p.installment(["Загальна сума 1000 ₴", "Загальна сума 2000 ₴"]).total == nil, "conflicting fields not guessed")
require(p.installment(["Загальний кредит 100 USD"]).foreignCurrency, "foreign currency installment flagged")
require(p.validInstallment(total:3000,remaining:2000,monthly:500) && !p.validInstallment(total:1000,remaining:2000,monthly:500), "remaining constraints")
require(p.validInstallment(total:3000,remaining:0,monthly:0) && !p.validInstallment(total:3000,remaining:2000,monthly:0), "completed and active installments")
let balance = p.balance(["Власні кошти 500 ₴", "Кредитний ліміт 10000 ₴", "Доступно 10500 ₴", "Використано кредиту 0 ₴"])
require(balance.own?.minor == 50000 && balance.limit?.minor == 1000000 && balance.used?.minor == 0 && balance.net == nil, "balance fields distinct from available credit")
require(p.bank("Виписка ПУМБ") == "ПУМБ" && p.bank("monobank ПУМБ") == nil, "bank recognition and ambiguity")
let day = p.date("25.11.2026")!, later = p.date("25.11.2026 19:30")!
require(p.samePayment(account:"a",signed:-100,date:day,otherAccount:"a",otherSigned:-100,otherDate:later), "same-day same-account same-direction duplicate")
require(!p.samePayment(account:"a",signed:-100,date:day,otherAccount:"a",otherSigned:100,otherDate:later), "opposite directions not duplicates")
require(!p.samePayment(account:"a",signed:-100,date:day,otherAccount:"b",otherSigned:-100,otherDate:later), "different accounts not duplicates")
let oldOp = Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8)
var operation = try JSONDecoder().decode(Operation.self, from: oldOp)
require(operation.scanImageID == nil && operation.scanFingerprint == nil, "legacy operation decode")
operation.scanImageID = "image"; operation.scanFingerprint = "row"
let op = try JSONDecoder().decode(Operation.self, from: JSONEncoder().encode(operation))
require(op.scanImageID == "image" && op.scanFingerprint == "row" && op.amount == 1234, "operation scan metadata roundtrip")
let oldOb = Data(#"{"id":"a","kind":"installment","name":"Phone","target":3000,"paid":1000,"monthly":500,"due":0}"#.utf8)
var obligation = try JSONDecoder().decode(Obligation.self, from: oldOb)
require(obligation.scanImageID == nil && obligation.remaining == 2000, "legacy installment decode")
obligation.scanImageID = "image"; obligation.scanFingerprint = "image"
let updated = try JSONDecoder().decode(Obligation.self, from: JSONEncoder().encode(obligation))
require(updated.scanImageID == "image" && updated.scanFingerprint == "image" && updated.remaining == 2000, "installment metadata roundtrip")
let alternate = p.installment(["ПУМБ", "Назва товару:", "Ноутбук", "Сума покупки: 24 000,00", "Залишилось погасити: 18 000 грн", "Розмір платежу: 2 000 ₴", "Дата списання: 5 грудня 2026"])
require(alternate.name == "Ноутбук" && alternate.total == 2400000 && alternate.remaining == 1800000 && alternate.monthly == 200000 && alternate.due == p.date("05.12.2026"), "P8 alternate labels, colon, next-line name and Ukrainian date")
require(p.installment(["Сума наступного платежу", "2 000", "Дата наступного платежу", "5/12/2026"]).monthly == 200000 && p.installmentDate("5/12/2026") == p.date("05.12.2026"), "P8 separate amounts and slash date")
require(p.installment(["Наступний платіж 01.12"]).monthly == nil, "P8 short date not interpreted as payment")
require(p.installment(["Загальна сума 2000 ₴ Залишок боргу 1500 ₴"]).total == nil, "P8 ambiguous combined fields not guessed")
require(p.installmentCandidateAmount("2 500,00 ₴") == 250000 && p.installmentCandidateAmount("5 грудня 2026") == nil, "P8 source amount selection")
require(p.installment(["Сума кредиту 10000 ₴", "Погашено основного боргу 2500 ₴"]).remaining == 750000, "P8 derive remaining from explicitly paid principal")
require(p.installment(["Сума кредиту 10000 ₴", "Вже сплачено 2500 ₴"]).remaining == nil, "P8 no generic paid derivation with unknown fees")
let reverse = p.installment(["Назва: Телефон", "30 000 ₴", "Загальний кредит", "15 000 ₴", "Поточний залишок", "2 500 ₴", "Щомісячний платіж", "01.12.2026", "Дата наступного платежу"])
require(reverse.total == 3000000 && reverse.remaining == 1500000 && reverse.monthly == 250000 && reverse.due == p.date("01.12.2026"), "QA: amounts and date above labels retain correct fields")
let forward = p.installment(["Назва: Телефон", "Загальний кредит", "30 000 ₴", "Поточний залишок", "15 000 ₴", "Щомісячний платіж", "2 500 ₴", "Дата наступного платежу", "01.12.2026"])
require(forward.total == 3000000 && forward.remaining == 1500000 && forward.monthly == 250000 && forward.due == p.date("01.12.2026"), "QA: amounts and date below labels retain correct fields")
let ambiguous = p.installment(["Загальний кредит", "15 000 ₴", "Поточний залишок"])
require(ambiguous.total == nil && ambiguous.remaining == nil, "QA: a value between two unmatched labels is not guessed")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/preview4-tests"
TZ=Europe/Kyiv "$tmp/preview4-tests"
