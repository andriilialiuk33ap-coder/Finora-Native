#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
source Tests/model-safety-fixture.sh
finami_safety_models > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ label: String, _ condition: @autoclosure () -> Bool) { precondition(condition(), label); print("PASS: " + label) }
func valid(_ db: Database) -> Bool { (try? FinamiDatabaseSafety.validate(db)) != nil }
var db = Database()
db.accounts.append(Account(id: "bank", name: "Bank", opening: 100_000, accountType: "credit", creditLimit: 50_000))
db.operations = [Operation(id: "expense", amount: 10_000, account: "bank"), Operation(id:"transfer",kind:.transfer,amount:5000,account:"bank",destination:cash)]
db.obligations = [Obligation(kind:.installment, name:"Parts", target:30_000, paid:13_000, monthly:10_000, currentDuePaid:3000)]
db.subscriptions = [SubscriptionRecord(name:"Test",amount:500)]
check("production financial validator accepts ordinary ledger, partial installment and subscription", valid(db))
func bad(_ label: String, _ change: (inout Database) -> Void) { var copy = db; change(&copy); check(label, !valid(copy)) }
bad("reject Int64.min before negating native balances") { $0.accounts[0].opening = Int64.min }
bad("reject oversized credit limit") { $0.accounts[0].creditLimit = Int64.max }
bad("reject invalid anchored balance") { $0.accounts[0].reconciliationNet = Int64.max }
bad("reject zero operation") { $0.operations[0].amount = 0 }
bad("reject negative source minor") { $0.operations[0].sourceMinor = Int64.min }
bad("reject oversized fee before neutralFee calculation") { $0.operations[0].bankFee = Int64.max }
bad("reject duplicate operation identifiers") { $0.operations.append($0.operations[0]) }
bad("reject duplicate account identifiers") { $0.accounts.append($0.accounts[0]) }
bad("reject duplicate schedule identifiers across modules") { $0.subscriptions?[0].id = $0.obligations[0].id }
bad("reject paid principal above target") { $0.obligations[0].paid = 30_001 }
bad("reject invalid partial progress") { $0.obligations[0].currentDuePaid = 10_000 }
bad("reject confirmed schedule with inconsistent outstanding balance") { $0.obligations[0].currentDuePaid = nil; $0.obligations[0].confirmedSchedule = [.init(date:$0.obligations[0].due,amount:1)] }
var confirmedDB = db
confirmedDB.obligations[0].currentDuePaid = nil
confirmedDB.obligations[0].confirmedSchedule = [.init(date:confirmedDB.obligations[0].due,amount:17_000)]
check("validator accepts exact outstanding confirmed schedule", valid(confirmedDB))
bad("reject oversized imported schedule row") { $0.obligations[0].importedSchedule = [.init(date:Date(),amount:Int64.max)] }
bad("reject oversized subscription history") { $0.subscriptions?[0].payments = [.init(date:Date(),amount:Int64.max,currency:"UAH",through:Date())] }
bad("reject invalid foreign exchange values") { $0.exchangeDiary = [FinamiExchangeRecord(units:Int64.max)] }
bad("reject malformed bank date") { $0.operations[0].date = Date(timeIntervalSinceReferenceDate: .infinity) }
bad("reject oversized budget") { $0.budget = Int64.max }
// Build 89: enforce the same ledger invariants on every entry path.
let t = Date(timeIntervalSince1970: 1_800_000_000)
var fxDB = Database()
fxDB.accounts.append(Account(id: "usd", name: "USD", opening: 20_000, currency: "USD"))
fxDB.currencyPreferences = .init(usdRate: "42")
let grouped = Operation(id: "fx", kind: .transfer, amount: 42_000, date: t, account: "usd", destination: cash,
    groupedBankParts: [.init(key: "part1", date: t, amount: 20_000, note: "A"), .init(key: "part2", date: t.addingTimeInterval(1), amount: 22_000, note: "B")],
    sourceMinor: 1_000, destinationMinor: 42_000, entryCurrency: "USD", exchangeRate: "42")
fxDB.operations = [grouped]
check("valid grouped conversion accepted by shared validator", valid(fxDB))
func badFX(_ label: String, _ change: (inout Database) -> Void) { var copy = fxDB; change(&copy); check(label, !valid(copy)) }
badFX("group total mismatch rejected before index creation") { $0.operations[0].destinationMinor = 41_999 }
badFX("group report amount must match native UAH destination") { $0.operations[0].amount = 41_999 }
badFX("empty grouped legs rejected") { $0.operations[0].groupedBankParts = [] }
badFX("repeated group key rejected") { $0.operations[0].groupedBankParts?[1].key = "part1" }
badFX("group cannot also have a separate destination key") { $0.operations[0].destinationBankKey = "other" }
badFX("group source key cannot reuse a destination leg") { $0.operations[0].bankKey = "part1" }
badFX("non-transfer cannot carry group legs") { $0.operations[0].kind = .expense }
badFX("missing USD native amount rejected") { $0.operations[0].sourceMinor = nil }
badFX("missing USD operation rate rejected") { $0.operations[0].exchangeRate = nil }
badFX("missing USD portfolio rate rejected") { $0.currencyPreferences = nil }
badFX("orphaned source rejected") { $0.operations[0].account = "missing" }
badFX("orphaned destination rejected") { $0.operations[0].destination = "missing" }
badFX("self transfer rejected") { $0.operations[0].destination = "usd" }
badFX("incomplete anchor rejected") { $0.accounts[0].reconciliationDate = t }
badFX("unsupported account currency rejected") { $0.accounts[0].currency = "EUR" }
var refundDB = db
let expense = Operation(id: "original", kind: .expense, amount: 1000, date: t, account: cash)
let refund = Operation(id: "refund", kind: .refund, amount: 400, date: t, account: cash, refundOriginalID: expense.id)
let compensation = Operation(id: "compensation", kind: .receipt, amount: 600, date: t, account: "bank", refundOriginalID: expense.id, receiptTreatment: .reimbursement)
refundDB.operations = [expense, refund, compensation]
check("same currency refund and cross-account compensation share exact purchase cap", valid(refundDB))
var badRefund = refundDB; badRefund.operations[2].amount = 601
check("combined refund and compensation above original rejected on load/save", !valid(badRefund))
badRefund = refundDB; badRefund.operations.removeFirst()
check("orphaned refund and compensation rejected", !valid(badRefund))
badRefund = refundDB; badRefund.operations[1].account = "bank"
check("bank refund on wrong account rejected", !valid(badRefund))
badRefund = refundDB; badRefund.accounts[1].currency = "USD"; badRefund.currencyPreferences = .init(usdRate: "42")
badRefund.operations[2].sourceMinor = 600; badRefund.operations[2].exchangeRate = "42"
check("USD account cannot masquerade as UAH compensation", !valid(badRefund))
var huge = Database(); huge.operations = (0..<19_000).map { Operation(id:String($0), amount: FinamiDatabaseSafety.amountLimit) }
check("aggregate envelope rejects extreme individually valid rows before arithmetic", !valid(huge))
var large = Database(); large.operations = (0..<100_000).map { Operation(id:String($0),amount:10_000) }
let start = Date(); check("100000 ordinary operations remain supported", valid(large)); print("MEASURE: safety validator 100000 rows: \(Date().timeIntervalSince(start)*1000) ms (host only)")
check("hidden subscription never enters widget payment payload", !FinamiWidgetPrivacyPolicy.showsPayment(subscription:true,id:"sub",hiddenSubscriptions:["sub"]))
check("visible subscription remains eligible", FinamiWidgetPrivacyPolicy.showsPayment(subscription:true,id:"other",hiddenSubscriptions:["sub"]))
check("same identifier does not hide non-subscription payment", FinamiWidgetPrivacyPolicy.showsPayment(subscription:false,id:"sub",hiddenSubscriptions:["sub"]))
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at:dir) }
var event = try captureWallet(amount:1,merchant:"Test",account:cash,currency:"UAH")
event.id = "../Finora"
check("capture writer rejects unsafe path before touching disk", (try? CaptureInbox.enqueue(event,in:dir)) == nil && !FileManager.default.fileExists(atPath:dir.path))
let zero = CapturedPayment(account:cash,currency:"UAH",minor:0,merchant:"Test",source:"Apple Pay",incoming:false,clearPurchase:true)
check("capture writer rejects zero amount", (try? CaptureInbox.enqueue(zero,in:dir)) == nil)
event.id = UUID().uuidString; try CaptureInbox.enqueue(event,in:dir)
let scan = try CaptureInbox.scan(in:dir)
check("valid capture still round-trips", scan.events == [event] && scan.unreadable == 0)
let link = dir.appendingPathComponent(UUID().uuidString + ".json")
try FileManager.default.createSymbolicLink(at:link,withDestinationURL:dir.appendingPathComponent(event.id + ".json"))
let withLink = try CaptureInbox.scan(in:dir)
check("symbolic link is isolated, valid capture stays readable", withLink.events == [event] && withLink.unreadable == 1)
let big = dir.appendingPathComponent(UUID().uuidString + ".json")
try Data(repeating: 0, count: 65_537).write(to:big)
let withBig = try CaptureInbox.scan(in:dir)
check("oversized queue file remains isolated without blocking valid event", withBig.events == [event] && withBig.unreadable == 2 && FileManager.default.fileExists(atPath:big.path))
SWIFT
swiftc -O -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift Finora/FinamiDatabaseSafety.swift WidgetShared/FinamiWidgetData.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
