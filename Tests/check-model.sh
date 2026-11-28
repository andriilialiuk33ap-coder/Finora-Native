#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let oldAccount = Data(#"{"id":"cash","name":"Cash","opening":10000}"#.utf8)
let oldOperation = Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8)
let a=try JSONDecoder().decode(Account.self,from:oldAccount)
let o=try JSONDecoder().decode(Operation.self,from:oldOperation)
precondition(a.code=="UAH" && a.opening==10000 && o.amount==1234 && o.sourceMinor==nil && o.bankKey==nil)
var newer=o;newer.sourceMinor=100;newer.originalAmount=100;newer.originalCurrency="USD";newer.entryCurrency="USD";newer.exchangeRate="42.35"
let copy=try JSONDecoder().decode(Operation.self,from:JSONEncoder().encode(newer))
precondition(copy.sourceMinor==100 && copy.exchangeRate=="42.35")
var card = a; card.accountType="credit"; card.creditLimit=3000000
let cardCopy = try JSONDecoder().decode(Account.self,from:JSONEncoder().encode(card))
precondition(cardCopy.isCredit && cardCopy.limit==3000000 && !a.isCredit)
var transaction=o; transaction.kind = .creditRepaymentIncoming
precondition(transaction.signedNative == 1234 && transaction.expenseValue == 0)
transaction.kind = .creditRepayment
precondition(transaction.signedNative == -1234 && transaction.expenseValue == 0)
transaction.kind = .refund
precondition(transaction.signedNative == 1234 && transaction.expenseValue == -1234)
transaction.kind = .unclassifiedCredit
precondition(transaction.kind.needsReview && transaction.expenseValue == 0)
let corrected=try JSONDecoder().decode(Operation.self,from:JSONEncoder().encode(transaction))
precondition(corrected.kind == .unclassifiedCredit && corrected.amount == o.amount && corrected.date == o.date)
precondition(o.captureSource == nil)
var captured = o; captured.captureSource = "Apple Pay"
let capturedCopy = try JSONDecoder().decode(Operation.self, from: JSONEncoder().encode(captured))
precondition(capturedCopy.captureSource == "Apple Pay")
print("PASS: legacy Account/Operation decode; currency, credit, classification and capture source roundtrip")
SWIFT
swiftc "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/model-test"
"$tmp/model-test"
# Compile the actual non-UI Store extension against a small in-memory persistence adapter.
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift Finora/Domain/PaymentModels.swift Finora/Domain/FinancialRecords.swift Finora/Domain/Database.swift; sed -n '/^struct CapturePreferences:/,/^struct AutomationCenter:/p' Finora/AutomationView.swift | sed '$d'; cat <<'SWIFT'
struct DashboardItem: Codable {}
struct AppearancePreferences: Codable {}
struct SubscriptionRecord: Codable {}
struct PersonalReminder: Codable {}
struct ForecastPreferences: Codable {}
func suggestedCategory(_ merchant: String,kind: Kind,database: Database) -> String {"Без категорії"}
@MainActor final class Store {
    var db=Database()
    var capturePending:[CapturedPayment]=[]
    var captureRefreshInProgress=false
    var captureWarning:String?=nil
    var currentRate:Decimal?=nil
    var failWrite=false
    var writes=0
    var databaseVersion: UInt64 { UInt64(writes) }
    var storageHealthy=true
    var loading=false
    func change(_ update:(inout Database)->Void)->Bool {
        if failWrite {return false}
        var copy=db;update(&copy);db=copy;writes += 1;return true
    }
}
SWIFT
} > "$tmp/CaptureModels.swift"
cat > "$tmp/CaptureHarness.swift" <<'SWIFT'
import Foundation
@main struct CaptureHarness {
    @MainActor static func main() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let s=Store();s.db.capturePreferences=CapturePreferences(walletAuto:true,messageAuto:true)
        let text="Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH"
        let first=try captureMessage(text,account:cash)
        var repeatEvent=try captureMessage(text,account:cash)
        repeatEvent.date=first.date.addingTimeInterval(60)
        try CaptureInbox.enqueue(first,in:dir);try CaptureInbox.enqueue(repeatEvent,in:dir)
        s.loading=true;s.refreshCaptures(inbox:dir)
        precondition(s.db.operations.isEmpty && s.capturePending.isEmpty)
        s.loading=false;s.storageHealthy=false;s.refreshCaptures(inbox:dir)
        precondition(s.db.operations.isEmpty && s.capturePending.isEmpty)
        s.storageHealthy=true
        print("PASS: capture queue waits for healthy loaded database")
        s.refreshCaptures(inbox:dir)
        precondition(s.db.operations.count==1 && s.capturePending.count==1 && s.captureRepeat(repeatEvent))
        let restarted=Store();restarted.db=try JSONDecoder().decode(Database.self,from:JSONEncoder().encode(s.db))
        restarted.refreshCaptures(inbox:dir)
        precondition(restarted.db.operations.count==1 && restarted.capturePending.count==1)
        let duplicate=restarted.capturedOperation(repeatEvent,kind:.expense)!
        precondition(!restarted.finishCapture(repeatEvent,operation:duplicate,inbox:dir))
        precondition(restarted.db.operations.count==1)
        precondition(restarted.finishCapture(repeatEvent,operation:nil,inbox:dir))
        var later=try captureMessage(text,account:cash);later.date=first.date.addingTimeInterval(86400*20)
        try CaptureInbox.enqueue(later,in:dir);restarted.refreshCaptures(inbox:dir)
        precondition(restarted.db.operations.count==1 && restarted.capturePending.count==1)
        precondition(restarted.finishCapture(later,operation:restarted.capturedOperation(later,kind:.expense),allowSeparatePayment:true,inbox:dir))
        precondition(restarted.db.operations.count==2)
        // A failed persistence must leave the source event in the queue and not mark it handled.
        let new=try captureMessage("Оплата 555 грн; Магазин: Test",account:cash)
        try CaptureInbox.enqueue(new,in:dir);restarted.failWrite=true;restarted.refreshCaptures(inbox:dir)
        precondition(restarted.db.operations.count==2 && !restarted.captureRepeat(new))
        let queued=try CaptureInbox.read(in:dir);precondition(queued==[new])
        restarted.failWrite=false;restarted.refreshCaptures(inbox:dir)
        precondition(restarted.db.operations.count==3 && restarted.captureRepeat(new))
        let routeStore = Store()
        routeStore.db.accounts = [Account(id:"card-a",name:"Test debit"), Account(id:"card-b",name:"Test credit")]
        let key = finamiWalletAliasKey("Test Card 1234")!
        routeStore.db.capturePreferences = CapturePreferences(walletAuto:true,messageAuto:true,walletBindings:[key:"card-a"])
        let w = try captureWallet(amount:503.20,merchant:"Test Shop",account:key,currency:"UAH")
        try CaptureInbox.enqueue(w,in:dir); routeStore.refreshCaptures(inbox:dir)
        precondition(routeStore.db.operations.count == 1 && routeStore.db.operations[0].account == "card-a")
        var bank = try captureMessage("Купівля 503.20UAH Test Shop VINNITSA UA 26-11-2026 16:20",account:"card-b")
        bank.date = w.date
        try CaptureInbox.enqueue(bank,in:dir); routeStore.refreshCaptures(inbox:dir)
        precondition(routeStore.db.operations.count == 1 && routeStore.capturePending.count == 1 && routeStore.captureMatch(bank))
        precondition(routeStore.finishCapture(bank,operation:nil,inbox:dir))
        let unknown = try captureWallet(amount:77,merchant:"Test Shop",account:"wallet:unknown",currency:"UAH")
        try CaptureInbox.enqueue(unknown,in:dir); routeStore.refreshCaptures(inbox:dir)
        precondition(routeStore.capturePending.count == 1 && routeStore.capturePending[0].account.isEmpty && routeStore.db.operations.count == 1)
        precondition(routeStore.finishCapture(unknown,operation:nil,inbox:dir))
        print("PASS: actual Store wallet alias routing, cross-account duplicate review, unknown card inbox")
        routeStore.captureWarning="old warning"
        routeStore.refreshCaptures(inbox:dir)
        precondition(routeStore.capturePending.isEmpty && routeStore.captureWarning == nil && routeStore.db.operations.count == 1)
        print("PASS: empty inbox clears stale status without financial mutations")
        // Build 54: valid files must progress while an unreadable file remains untouched.
        let batch = Store(); batch.db.capturePreferences = CapturePreferences(walletAuto:true,messageAuto:true)
        let broken = dir.appendingPathComponent("damaged.json")
        let brokenData = Data("broken JSON".utf8)
        try brokenData.write(to:broken)
        let a = try captureWallet(amount:11,merchant:"A",account:cash,currency:"UAH")
        let b = try captureWallet(amount:22,merchant:"B",account:cash,currency:"UAH")
        var replay = try captureWallet(amount:11,merchant:"A",account:cash,currency:"UAH"); replay.date = a.date.addingTimeInterval(1)
        let incoming = try captureMessage("Зарахування 1000 UAH; Магазин: Test",account:cash)
        for e in [a,b,replay,incoming] { try CaptureInbox.enqueue(e,in:dir) }
        batch.failWrite=true; batch.refreshCaptures(inbox:dir)
        precondition(batch.db.operations.isEmpty && batch.capturePending.count == 4 && batch.captureWarning != nil)
        precondition(try! CaptureInbox.scan(in:dir).events.count == 4)
        print("PASS: failed capture batch leaves every event queued")
        batch.failWrite=false; batch.refreshCaptures(inbox:dir)
        precondition(batch.writes == 1 && batch.db.operations.count == 2 && batch.capturePending.count == 2)
        print("PASS: two clear payments committed with one durable write; staged duplicate and incoming remain for review")
        precondition(try! Data(contentsOf:broken) == brokenData && batch.captureWarning != nil)
        print("PASS: damaged file isolated and preserved without blocking valid payments")
        precondition(batch.capturePending.contains(where:{$0.id == replay.id}) && batch.capturePending.contains(where:{$0.id == incoming.id}))
        batch.refreshCaptures(inbox:dir)
        precondition(batch.writes == 1 && batch.db.operations.count == 2 && batch.captureWarning != nil)
        print("PASS: repeated refresh does not duplicate accepted events or clear damage warning")
        try FileManager.default.removeItem(at:broken)
        batch.refreshCaptures(inbox:dir)
        precondition(batch.captureWarning == nil && batch.capturePending.count == 2)
        print("PASS: warning clears after queue file is repaired")
        // Legacy databases missing new optional fields still decode.
        let old=try JSONDecoder().decode(Database.self,from:JSONEncoder().encode(Database()))
        precondition(old.captureMessageFingerprints==nil)
        print("PASS: actual Store duplicate guard, replay after restart, explicit separate purchase, failed persistence retry, database compatibility")
    }
}
SWIFT
swiftc Finora/FinamiIntelligenceCore.swift Finora/BankCore.swift Finora/FinamiScanCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift "$tmp/CaptureModels.swift" "$tmp/CaptureHarness.swift" -o "$tmp/capture-test"
"$tmp/capture-test"
