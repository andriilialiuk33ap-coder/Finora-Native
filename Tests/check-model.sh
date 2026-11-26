#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; sed -n '/^enum Kind:/,/^enum ObligationKind:/p' Finora/Finora.swift | sed '$d'; } > "$tmp/Models.swift"
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
{ echo 'import Foundation'; echo 'let cash="cash"'; echo 'let expenseDefaults=["Без категорії"]; let incomeDefaults=["Без категорії"]'; sed -n '/^enum Kind:/,/^struct Legacy:/p' Finora/Finora.swift | sed '$d'; sed -n '/^struct CapturePreferences:/,/^struct AutomationCenter:/p' Finora/AutomationView.swift | sed '$d'; cat <<'SWIFT'
struct DashboardItem: Codable {}
struct AppearancePreferences: Codable {}
struct SubscriptionRecord: Codable {}
struct PersonalReminder: Codable {}
struct ForecastPreferences: Codable {}
func suggestedCategory(_ merchant: String,kind: Kind,database: Database) -> String {"Без категорії"}
@MainActor final class Store {
    var db=Database()
    var capturePending:[CapturedPayment]=[]
    var captureWarning:String?=nil
    var currentRate:Decimal?=nil
    var failWrite=false
    var storageHealthy=true
    var loading=false
    func change(_ update:(inout Database)->Void)->Bool {
        if failWrite {return false}
        var copy=db;update(&copy);db=copy;return true
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
        // Legacy databases missing new optional fields still decode.
        let old=try JSONDecoder().decode(Database.self,from:JSONEncoder().encode(Database()))
        precondition(old.captureMessageFingerprints==nil)
        print("PASS: actual Store duplicate guard, replay after restart, explicit separate purchase, failed persistence retry, database compatibility")
    }
}
SWIFT
swiftc Finora/BankCore.swift Finora/FinamiScanCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift "$tmp/CaptureModels.swift" "$tmp/CaptureHarness.swift" -o "$tmp/capture-test"
"$tmp/capture-test"
