#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
source Tests/model-safety-fixture.sh
finami_safety_models > "$tmp/Models.swift"
sed -n '/^enum OperationSort:/,/^func ruleKey/p' Finora/IzanamiFeatures.swift | sed '$d' >> "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
let input = ["ПриватБанк", "Оплата частинами", "Загальна сума: 12000 ₴", "Поточний залишок: 8000 ₴", "Щомісячний платіж: 4000 ₴", "Перший внесок", "4000 ₴", "Загальна комісія: 120 ₴", "Щомісячна комісія: 40 ₴", "Кількість платежів: 3", "Сплачено платежів: 1", "Дата оформлення: 10.10.2026", "Дата завершення: 10.01.2027", "Наступний платіж: 0 ₴", "Дата наступного платежу: 10.12.2026"]
let draft = FinamiScanParser.installment(input)
check(draft.name == "ПриватБанк · Оплата частинами", "explicit bank/product title suggestion")
check(draft.firstContribution == 400000 && draft.totalBankFee == 12000 && draft.monthlyBankFee == 4000, "first contribution, total and monthly fee remain separate")
check(draft.paymentCount == 3 && draft.paidCount == 1, "explicit contract payment counts")
check(draft.opened == bankDate("10.10.2026") && draft.finalDue == bankDate("10.01.2027"), "contract dates remain separate")
check(draft.nextAmount == 0 && draft.monthly == 400000 && draft.due == nil, "zero next payment never replaces regular amount or guesses date")
check(FinamiScanParser.installment(["Загальна комісія: 1%", "Комісія банку: 42 ₴"]).totalBankFee == nil, "percentage and ambiguous fee are not a total fee")
check(FinamiScanParser.installment(["Перший внесок 500 ₴", "Перший внесок 600 ₴"]).firstContribution == nil, "conflicting first contribution omitted")
check(FinamiScanParser.installment(["Щомісячна комісія: 5 USD"]).foreignCurrency, "foreign fee blocks UAH import")
let conflicting = finamiMergeInstallments([draft, FinamiScanParser.installment(["Загальна комісія: 20 ₴"])])
check(conflicting.draft.totalBankFee == nil && conflicting.conflicts.contains("Загальна комісія"), "cross-pass fee conflict cannot be silently resolved")
let rows = finamiScheduleRows(["10.12.2026 4000 ₴", "Комісія 10.12.2026 120 ₴", "Перший внесок 10.10.2026 4000 ₴"])
check(rows.count == 1 && rows[0].amount == 400000, "fee and initial contribution not imported as schedule rows")
var obligation = Obligation(kind: .installment, target: 1200000, paid: 400000, monthly: 400000)
obligation.bankContractSnapshot = .init(capturedAt: Date(), firstContribution: draft.firstContribution, totalBankFee: draft.totalBankFee, monthlyBankFee: draft.monthlyBankFee, paymentCount: draft.paymentCount, paidCount: draft.paidCount, nextAmount: draft.nextAmount, bankNextDue: draft.bankNextDue, opened: draft.opened, finalDue: draft.finalDue)
let decoded = try JSONDecoder().decode(Obligation.self, from: JSONEncoder().encode(obligation))
check(decoded.bankContractSnapshot == obligation.bankContractSnapshot && decoded.remaining == 800000 && decoded.nextCharge == 400000, "bank facts persist without changing financial principal")
let legacy = Obligation(kind: .installment, target: 1200000, monthly: 400000)
let legacyDecoded = try JSONDecoder().decode(Obligation.self, from: JSONEncoder().encode(legacy))
check(legacyDecoded.bankContractSnapshot == nil, "old obligations decode without bank evidence")
var database = Database(); database.obligations = [obligation]
check((try? FinamiDatabaseSafety.validate(database)) != nil, "validator accepts confirmed historical bank facts")
database.obligations[0].bankContractSnapshot?.totalBankFee = Int64.max
check((try? FinamiDatabaseSafety.validate(database)) == nil, "validator rejects unsafe historical fee")
check(bankMinor("1.005") == 101 && bankMinor("-1.005") == -101, "manual decimal rounding is symmetric")
check(finamiMinorText(Int64.min) == "-92233720368547758.08" && finamiMinorText(1) == "0.01", "exact minor-unit formatting including Int64.min")
let malformed = BankRow(source: "fixture", date: Date(timeIntervalSince1970: .infinity), signed: Int64.min, note: "fixture")
check(malformed.key.contains("invalid-date"), "invalid statement date cannot crash key generation")
check(bankReconcile(BankBatch(rows: [malformed, malformed]), debit: Int64.min, credit: 0).contains("не збігаються"), "bank reconciliation cannot overflow malformed signed amounts")
let xml = BankXML(shared: false)
try xml.parse(Data(("<worksheet><row><c r=\"" + String(repeating: "Z", count: 1000) + "1\"><v>1</v></c><c r=\"A1\"><v>2</v></c></row></worksheet>").utf8))
check(xml.rows == [["2"]], "oversized spreadsheet column is skipped without overflow")
let invalidMono = MonoItem(id:"bad",time:Int64.max,description:"test",mcc:1,amount:-100,operationAmount:-100,currencyCode:980,commissionRate:Int64.min)
check(monoRows([invalidMono],account:"a").rejected == 1, "malformed bank API time and fee are rejected")
let query = FinamiHistoryQuery(kind:"all",account:"all",category:"all",search:"",sort:.newest,hideAmounts:false)
check(query.apply(to:[Operation(amount:100)],names:[:],isCancelled:{true}).isEmpty, "cancelled search returns no results")
let snapshot = FinamiWidgetSnapshot(ownUAH:100,dueAmount:nil,dueCurrency:nil,dueDate:nil,updated:Date())
let bytes = try JSONEncoder().encode(snapshot)
check(FinamiWidgetSnapshot.decode(bytes,now:Date()) != nil, "widget schema v1 readable")
var future = snapshot; future.schemaVersion = 2
let futureBytes = try JSONEncoder().encode(future)
check(FinamiWidgetSnapshot.decode(futureBytes,now:Date()) == nil, "unknown widget schema not displayed")
check(FinamiWidgetSnapshot.decode(Data(repeating: 0,count:16_385),now:Date()) == nil, "oversized widget payload rejected")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift Finora/FinamiDatabaseSafety.swift Finora/FinamiHistoryQuery.swift WidgetShared/FinamiWidgetData.swift "$tmp/main.swift" -o "$tmp/test"
TZ=Europe/Kyiv "$tmp/test"
