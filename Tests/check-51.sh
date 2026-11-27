#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
grep -qx "// END_PAYMENT_STORE_CORE" Finora/FinamiPayments.swift
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; echo 'let expenseDefaults=["Без категорії", "💳 Розстрочка"]; let incomeDefaults=["Без категорії"]'; sed -n '/^enum Kind:/,/^struct Legacy:/p' Finora/Finora.swift | sed '$d'; sed -n '/^enum OperationSort:/,/^func ruleKey/p' Finora/IzanamiFeatures.swift | sed '$d'; grep '^func ruleKey(' Finora/IzanamiFeatures.swift; sed -n '/^enum SubscriptionPeriod:/,/^func currencyMoney/p' Finora/IzanamiFeatures.swift | sed '$d'; sed -n '/^struct FinamiPayment:/,/^\/\/ END_PAYMENT_STORE_CORE$/p' Finora/FinamiPayments.swift | sed '$d'; cat <<'SWIFT'
struct DashboardItem: Codable {}
struct AppearancePreferences: Codable { var theme = "old" }
struct ForecastPreferences: Codable {}
struct CapturePreferences: Codable {}
struct PersonalReminder: Codable { var id = UUID().uuidString; var title = ""; var date = Date(); var linkedID: String? = nil }
@MainActor enum ReminderScheduler { static func cancel(_ r: PersonalReminder) {}; static func schedule(_ r: PersonalReminder) async throws {} }
@MainActor final class Store {
    var db=Database(); var error: String?; var currentRate: Decimal?; var failWrite=false
    func change(_ update:(inout Database)->Void)->Bool { if failWrite {return false};var copy=db;update(&copy);guard finamiLinkedOperationsPreserved(before:db,after:copy) else{return false};db=copy;return true }
}
SWIFT
} > "$tmp/Models.swift"
cat > "$tmp/Harness.swift" <<'SWIFT'
import Foundation
@main struct Harness {
    static func check(_ test: @autoclosure () -> Bool, _ label: String) { precondition(test(),label); print("PASS: " + label) }
    @MainActor static func main() throws {
        let partialDate = Date().addingTimeInterval(-3600)
        let partialAccount=Account(id:"partial",name:"Test",opening:100000)
        let partialStore=Store();partialStore.db.accounts=[partialAccount]
        let partialLoan=Obligation(kind:.installment,name:"Test",target:30000,monthly:10000,due:partialDate)
        partialStore.db.obligations=[partialLoan]
        let original=partialStore.upcomingPayments[0]
        check(partialStore.confirmPayment(original,mode:.newOperation,accountID:partialAccount.id,operationID:"",paidDate:partialDate,kind:.creditRepayment,actualAmount:3000),"partial payment commits once")
        let nextPartial=partialStore.upcomingPayments[0]
        check(nextPartial.date==partialDate && nextPartial.amount==7000 && nextPartial.remaining==27000 && nextPartial.recurringAmount==10000,"partial next charge and unchanged date")
        check(!partialStore.confirmPayment(original,mode:.newOperation,accountID:partialAccount.id,operationID:"",paidDate:partialDate,kind:.creditRepayment,actualAmount:3000),"stale partial request cannot repeat")
        check(partialStore.confirmPayment(nextPartial,mode:.markOnly,accountID:"",operationID:"",paidDate:partialDate,kind:.creditRepayment,actualAmount:12000),"early principal payment")
        check(partialStore.upcomingPayments[0].amount==10000 && partialStore.upcomingPayments[0].remaining==15000 && partialStore.upcomingPayments[0].date>partialDate,"next full payment preserved after early payment")
        let last=partialStore.db.paidRecords!.last!
        check(partialStore.canUndoObligationPayment(last.id) && partialStore.undoObligationPayment(last.id),"safe last payment unlink restores schedule")
        check(partialStore.upcomingPayments[0].amount==7000 && partialStore.db.operations.count==1,"undo leaves actual ledger unchanged")
        let previous=partialStore.db.paidRecords!.last!
        check(partialStore.undoObligationPayment(previous.id) && partialStore.upcomingPayments[0].amount==10000 && partialStore.db.operations.count==1,"undo recorded debit restores original schedule without deleting statement")
        check(FinamiLedgerIndex(operations:partialStore.db.operations).balance(partialAccount)==97000,"unlink keeps account balance")
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
        var archived = store.db
        let originalOperations = archived.operations
        let originalRecords = archived.paidRecords?.map(\.id)
        archived.partnerGroups = [FinamiPartnerGroup(name:"Test",limit:100000,obligationIDs:[loan.id])]
        check(finamiRemoveInstallment(loan.id, from:&archived) && archived.obligations.isEmpty && archived.removedInstallments?.count == 1,"installment archive removes future obligations")
        check(archived.operations == originalOperations && archived.paidRecords?.map(\.id) == originalRecords && archived.partnerGroups?.first?.obligationIDs.isEmpty == true,"archive preserves actual debit and history, detaches partner group")
        check(!finamiRemoveInstallment(loan.id, from:&archived),"duplicate archive rejected")
        let restoredArchive = try JSONDecoder().decode(Database.self, from:JSONEncoder().encode(archived))
        archived = restoredArchive
        check(finamiRestoreInstallment(loan.id, into:&archived) && archived.obligations.first?.remaining == 10000 && archived.operations == originalOperations,"archive survives backup and restores original schedule")
        check(!finamiRestoreInstallment(loan.id, into:&archived),"duplicate restore rejected")
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
        // Directly entering or editing a ledger debit must advance the same schedule.
        do {
        let direct = Store(); let credit = Account(id:"credit",name:"Credit",opening:-30_000,accountType:"credit",creditLimit:100_000)
        direct.db.accounts=[account,credit]
        direct.db.obligations=[Obligation(kind:.installment,name:"Direct loan",target:30_000,monthly:10_000,due:date)]
        let first=direct.upcomingPayments[0]
        let transferDraft=Operation(kind:.transfer,amount:10_000,date:date,account:account.id,destination:credit.id)
        check(direct.confirmPayment(first,mode:.newOperation,accountID:account.id,operationID:transferDraft.id,paidDate:date,kind:.transfer,operationDraft:transferDraft),"direct transfer links explicitly to installment")
        check(direct.db.obligations[0].remaining==20_000 && direct.upcomingPayments[0].date>date && direct.db.paidRecords?.first?.operationID==transferDraft.id,"all schedule views use updated balance and due")
        let ledger=FinamiLedgerIndex(operations:direct.db.operations)
        check(ledger.balance(account)==90_000 && ledger.balance(credit)==(-20_000) && direct.db.operations.count==1,"one transfer debit and credit, no duplicate operation")
        let second=direct.upcomingPayments[0]
        check(!direct.confirmPayment(second,mode:.newOperation,accountID:account.id,operationID:transferDraft.id,paidDate:date,kind:.transfer,operationDraft:transferDraft),"already linked operation cannot pay another installment")
        let old=Operation(kind:.creditRepayment,amount:10_000,date:date,account:account.id)
        direct.db.operations.append(old)
        let priorBalance=FinamiLedgerIndex(operations:direct.db.operations).balance(account)
        check(direct.confirmPayment(second,mode:.newOperation,accountID:account.id,operationID:old.id,paidDate:date,kind:old.kind,operationDraft:old),"link earlier operation directly from editor")
        check(direct.db.operations.count==2 && direct.db.obligations[0].remaining==10_000 && FinamiLedgerIndex(operations:direct.db.operations).balance(account)==priorBalance,"link earlier debit without second debit")
        check(!direct.change{$0.operations.removeAll{$0.id==old.id}},"linked debit cannot be deleted by edit or batch")
        check(!direct.change{$0.operations[0].amount=99},"linked debit amount cannot change silently")
        check(direct.change{$0.operations[0].note="Updated"},"linked debit note can change")
        let final=direct.upcomingPayments[0];let wrong=Operation(kind:.creditRepayment,amount:500,date:date,account:account.id)
        check(!direct.confirmPayment(final,mode:.newOperation,accountID:account.id,operationID:wrong.id,paidDate:date,kind:wrong.kind,operationDraft:wrong),"mismatched payment amount rejected")
        let finalDebit=Operation(kind:.creditRepayment,amount:10_000,date:date,account:account.id)
        direct.failWrite=true
        check(!direct.confirmPayment(final,mode:.newOperation,accountID:account.id,operationID:finalDebit.id,paidDate:date,kind:finalDebit.kind,operationDraft:finalDebit) && direct.db.obligations[0].remaining==10_000 && direct.db.operations.count==2,"direct link failure leaves both schedule and ledger unchanged")
        direct.failWrite=false
        check(direct.confirmPayment(final,mode:.newOperation,accountID:account.id,operationID:finalDebit.id,paidDate:date,kind:finalDebit.kind,operationDraft:finalDebit) && direct.upcomingPayments.isEmpty,"last linked repayment closes installment")
        direct.db.subscriptions=[SubscriptionRecord(name:"Music direct",amount:500,currency:"UAH",next:date)]
        let sub=direct.upcomingPayments[0];let expense=Operation(kind:.expense,amount:500,date:date,category:"Music",note:"Music",account:account.id)
        check(direct.confirmPayment(sub,mode:.newOperation,accountID:account.id,operationID:expense.id,paidDate:date,kind:.expense,operationDraft:expense,learnCategory:true) && direct.db.subscriptions?[0].payments.count==1 && direct.db.subscriptions![0].next>date && direct.db.operations.last?.expenseValue==500,"subscription direct expense advances date and records one expense")
        check(direct.db.merchantRules?[ruleKey("Music",kind:.expense)]=="Music","direct linked expense preserves learning category")
        check(!finamiPaymentDraftMatches(expense,account:credit,currency:"UAH",amount:500),"wrong account rejected")
        check(!finamiPaymentDraftMatches(expense,account:account,currency:"USD",amount:500),"wrong currency rejected")
        check(!finamiPaymentDraftMatches(Operation(kind:.income,amount:500,date:date,account:account.id),account:account,currency:"UAH",amount:500),"incoming payment rejected")
        }
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
        let window = FinamiHistoryQuery(kind:"all",account:"all",category:"all",search:"",sort:.newest,hideAmounts:false,from:date.addingTimeInterval(1))
        check(window.apply(to:[transfer],names:[:]).isEmpty,"history lower date boundary")
        let minQuery = FinamiHistoryQuery(kind:"all",account:"all",category:"all",search:"",sort:.newest,hideAmounts:false,minimum:1)
        check(minQuery.apply(to:[transfer],names:[:]).count==1 && minQuery.apply(to:[transfer],names:[:],maskedAccounts:[transfer.account]).isEmpty,"amount filter excludes masked accounts")
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
swiftc -O -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiScanCore.swift Finora/AutomationCore.swift Finora/FinamiCore.swift Finora/FinamiPaymentCore.swift Finora/FinamiStatementMatch.swift Finora/FinamiAppearanceStorage.swift Finora/FinamiHistoryQuery.swift Finora/FinamiIntelligenceCore.swift "$tmp/Harness.swift" -o "$tmp/test"
"$tmp/test"
