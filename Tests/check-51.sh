#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; echo 'let expenseDefaults=["Без категорії", "💳 Розстрочка"]; let incomeDefaults=["Без категорії"]'; sed -n '/^enum Kind:/,/^struct Legacy:/p' Finora/Finora.swift | sed '$d'; sed -n '/^enum OperationSort:/,/^func ruleKey/p' Finora/IzanamiFeatures.swift | sed '$d'; sed -n '/^enum SubscriptionPeriod:/,/^func currencyMoney/p' Finora/IzanamiFeatures.swift | sed '$d'; sed -n '/^struct FinamiPayment:/,/^struct FinamiPaymentCard:/p' Finora/FinamiPayments.swift | sed '$d'; cat <<'SWIFT'
struct DashboardItem: Codable {}
struct AppearancePreferences: Codable { var theme = "old" }
struct ForecastPreferences: Codable {}
struct CapturePreferences: Codable {}
struct PersonalReminder: Codable { var id = UUID().uuidString; var title = ""; var date = Date(); var linkedID: String? = nil }
@MainActor enum ReminderScheduler { static func cancel(_ r: PersonalReminder) {}; static func schedule(_ r: PersonalReminder) async throws {} }
@MainActor final class Store {
    var db=Database(); var error: String?; var currentRate: Decimal?; var failWrite=false
    func change(_ update:(inout Database)->Void)->Bool { if failWrite {return false};var copy=db;update(&copy);db=copy;return true }
}
SWIFT
} > "$tmp/Models.swift"
cat > "$tmp/Harness.swift" <<'SWIFT'
import Foundation
@main struct Harness {
    static func check(_ test: @autoclosure () -> Bool, _ label: String) { precondition(test(),label); print("PASS: " + label) }
    @MainActor static func main() throws {
        let date = Date().addingTimeInterval(-86400)
        let account = Account(id:"pumb",name:"PUMB",opening:100_000)
        let otp = Account(id:"otp",name:"OTP",opening:10_000)
        let store = Store(); store.db.accounts=[account,otp]
        let loan = Obligation(kind:.installment,name:"Phone",target:30_000,paid:10_000,monthly:10_000,due:date)
        store.db.obligations=[loan]; let p=store.upcomingPayments[0]
        check(store.confirmPayment(p,mode:.newOperation,accountID:account.id,operationID:"",paidDate:date,kind:.creditRepayment),"record installment and selected account")
        check(store.db.obligations[0].remaining==10_000 && store.db.obligations[0].due>date,"installment remaining decreases and due advances")
        check(store.db.operations.count==1 && store.db.operations[0].account==account.id && FinamiLedgerIndex(operations:store.db.operations).balance(account)==90_000,"single native debit; other account unaffected")
        check(store.db.operations[0].expenseValue==0 && store.db.paidRecords?.first?.operationID==store.db.operations[0].id,"principal excluded from expense and history linked")
        check(!store.confirmPayment(p,mode:.newOperation,accountID:account.id,operationID:"",paidDate:date,kind:.creditRepayment) && store.db.operations.count==1,"repeat tap cannot debit twice")
        let next=store.upcomingPayments[0]; let other=Operation(kind:.expense,amount:10_000,date:date,account:otp.id)
        store.db.operations.append(other)
        check(!store.confirmPayment(next,mode:.existing,accountID:account.id,operationID:other.id,paidDate:date,kind:.expense),"reject existing operation from wrong account")
        check(!store.confirmPayment(next,mode:.newOperation,accountID:otp.id,operationID:"",paidDate:date,kind:.expense),"similar existing operation blocks new debit without explicit override")
        store.failWrite=true
        check(!store.confirmPayment(next,mode:.existing,accountID:otp.id,operationID:other.id,paidDate:date,kind:.expense) && store.db.obligations[0].remaining==10_000,"failed write leaves schedule and ledger unchanged")
        store.failWrite=false
        check(store.confirmPayment(next,mode:.existing,accountID:otp.id,operationID:other.id,paidDate:date,kind:.expense) && store.db.operations.count==2 && store.db.obligations[0].remaining==0,"existing bank operation linked without new debit; final installment closes")
        check(finamiEligiblePaymentOperations(store.db.operations,records:store.db.paidRecords ?? [],account:otp.id,currency:"UAH",amount:10_000,date:date).isEmpty,"already linked operation excluded")
        store.db.obligations.append(Obligation(kind:.recurring,name:"Utilities",target:5000,monthly:5000,due:date))
        check(store.confirmPayment(store.upcomingPayments[0],mode:.markOnly,accountID:"",operationID:"",paidDate:date,kind:.expense) && store.db.operations.count==2,"mark only does not touch ledger")
        store.db.subscriptions=[SubscriptionRecord(name:"Music",amount:500,currency:"UAH",next:date)]
        check(store.confirmPayment(store.upcomingPayments[0],mode:.newOperation,accountID:account.id,operationID:"",paidDate:date,kind:.expense) && store.db.subscriptions?[0].payments.count==1 && store.db.operations.last?.expenseValue==500,"subscription paid from account with expense")
        let usd=Account(id:"usd",name:"USD",currency:"USD")
        check(finamiNewPaymentOperation(name:"USD",account:usd,currency:"USD",amount:100,date:date,kind:.expense,rate:nil,categories:[])==nil,"missing exchange rate blocks payment")
        let foreign=finamiNewPaymentOperation(name:"USD",account:usd,currency:"USD",amount:100,date:date,kind:.expense,rate:40,categories:[])!
        check(foreign.amount==4000 && foreign.sourceMinor==100 && foreign.signedNative == -100,"USD payment preserves native and reporting amounts")
        let row=BankRow(source:"ПУМБ",date:date,signed:-10_000,note:"Phone")
        var more=row;more.id=UUID().uuidString;more.note="Other"
        var index=FinamiStatementMatchIndex(operations:store.db.operations,account:account.id)
        check(index.newRows([row,more]).count==2 && index.candidates(row).count==1,"new bank rows reviewed against manual payment")
        let before=FinamiLedgerIndex(operations:store.db.operations).balance(account)
        check(finamiAttachStatement(row,to:&store.db.operations[0],account:account.id),"attach bank row to existing payment")
        check(FinamiLedgerIndex(operations:store.db.operations).balance(account)==before && store.db.operations[0].kind == .creditRepayment,"attachment does not change balance or classification")
        index=FinamiStatementMatchIndex(operations:store.db.operations,account:account.id)
        check(index.newRows([row]).isEmpty,"same statement contains zero new transactions")
        check(index.newRows([row,more]).map(\.id)==[more.id],"extended statement contains only new transaction")
        var duplicate=row;duplicate.id=UUID().uuidString
        check(index.newRows([row,duplicate]).count==1,"identical legitimate transactions preserve multiplicity")
        check(!finamiAttachStatement(row,to:&store.db.operations[0],account:account.id),"already linked statement cannot attach twice")
        check(FinamiStatementMatchIndex(operations:store.db.operations,account:otp.id).newRows([row]).count==1,"different accounts do not share exact keys")
        var transfer=Operation(kind:.transfer,amount:500,date:date,account:otp.id,destination:account.id)
        let credit=BankRow(source:"ПУМБ",date:date,signed:500,note:"Transfer")
        let debit=BankRow(source:"ОТП",date:date,signed:-500,note:"Transfer")
        check(FinamiStatementMatchIndex(operations:[transfer],account:account.id).candidates(credit).count==1,"incoming transfer leg recognized")
        check(finamiAttachStatement(credit,to:&transfer,account:account.id) && finamiAttachStatement(debit,to:&transfer,account:otp.id),"both transfer legs attach independently")
        check(FinamiStatementMatchIndex(operations:[transfer],account:account.id).newRows([credit]).isEmpty && FinamiStatementMatchIndex(operations:[transfer],account:otp.id).newRows([debit]).isEmpty,"both bank statements skip same transfer thereafter")
        let legacy=Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8)
        let decoded=try JSONDecoder().decode(Operation.self,from:legacy)
        check(decoded.destinationBankKey==nil && decoded.bankKey==nil,"old operation decodes with new optional key")
        let backup=try JSONEncoder().encode(store.db)
        let restored=try JSONDecoder().decode(Database.self,from:backup)
        check(restored.paidRecords?.count==4 && restored.operations==store.db.operations,"payment history and statement keys survive backup roundtrip")
        let search = FinamiHistoryQuery(kind:"all",account:"all",category:"all",search:"100.00",sort:.newest,hideAmounts:false)
        let hiddenSearch = FinamiHistoryQuery(kind:"all",account:"all",category:"all",search:"100.00",sort:.newest,hideAmounts:true)
        check(search.apply(to:store.db.operations,names:[:]).count==2 && hiddenSearch.apply(to:store.db.operations,names:[:]).isEmpty,"history query hides amount from search when privacy is enabled")
        let incomingQuery=FinamiHistoryQuery(kind:"all",account:account.id,category:"all",search:"",sort:.newest,hideAmounts:false)
        check(incomingQuery.apply(to:[transfer],names:[:]).count==1,"history account filter includes incoming transfer")
        let base=AppearancePreferences(theme:"old"), newer=AppearancePreferences(theme:"new")
        let sidecar=try JSONEncoder().encode(FinamiAppearanceSidecar(revision:"v1",preferences:newer))
        let loaded=try FinamiAppearanceSidecar.resolve(base:base,revision:"v1",data:sidecar)
        let stale=try FinamiAppearanceSidecar.resolve(base:base,revision:"v2",data:sidecar)
        let old=try FinamiAppearanceSidecar.resolve(base:base,revision:nil,data:sidecar)
        check(loaded?.theme=="new","appearance sidecar restores matching generation")
        check(stale?.theme=="old" && old?.theme=="old","stale sidecar cannot override restored or legacy database")
        var large:[Operation]=[];var rows:[BankRow]=[]
        for i in 0..<20_000 { let time=date.addingTimeInterval(Double(i)*60);let value=Int64(i+1); var r=BankRow(source:"ПУМБ",date:time,signed:-value,note:"Test");r.reference="test-\(i)";rows.append(r);if i<19_000 {large.append(Operation(kind:.expense,amount:value,date:time,account:account.id,bankKey:r.key))} }
        let start=DispatchTime.now().uptimeNanoseconds
        let added=FinamiStatementMatchIndex(operations:large,account:account.id).newRows(rows)
        let ms=Double(DispatchTime.now().uptimeNanoseconds-start)/1e6
        check(added.count==1000,"20k rows overlapping 19k prior transactions imports exactly 1k new")
        print(String(format:"BENCH: incremental statement 20,000 rows, 19,000 existing: %.2f ms (Linux, algorithm only)",ms))
    }
}
SWIFT
swiftc -O -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiScanCore.swift Finora/AutomationCore.swift Finora/FinamiCore.swift Finora/FinamiPaymentCore.swift Finora/FinamiStatementMatch.swift Finora/FinamiAppearanceStorage.swift Finora/FinamiHistoryQuery.swift "$tmp/Harness.swift" -o "$tmp/test"
"$tmp/test"
