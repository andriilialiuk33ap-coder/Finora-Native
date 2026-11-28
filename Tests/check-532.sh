#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
# Compile the actual AccountEditor calculation without SwiftUI, using a minimal store.
{
cat <<'SWIFT'
import Foundation
struct TestAccountDB { var accounts:[Account] }
struct TestAccountStore {
    var db:TestAccountDB
    var operations:[Operation]
    func nativeBalance(_ a:Account)->Int64 { FinamiLedgerIndex(operations:operations,accounts:db.accounts).balance(a) }
}
struct AccountEditorCalculation {
    var s:TestAccountStore
    var a:Account
    var opening="0", limitText="0", actualText="0", actualMode="net", ownText="0", usedText="0"
    var correctBalance=false
SWIFT
sed -n '/^  var newOpening: Int64? {/,/^  var existingAccount:/p' Finora/FinamiAccountViews.swift | sed '$d'
echo '}'
} > "$tmp/AccountEditorCalculation.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ b:@autoclosure ()->Bool,_ title:String){precondition(b(),title);print("PASS: "+title)}
let iban="UA"+String(repeating:"1",count:27), other="UA"+String(repeating:"2",count:27)
let usd=Account(id:"usd",name:"USD",opening:100000,currency:"USD"), debit=Account(id:"a",name:"Debit",bankName:"ПУМБ",lastFour:"1111",statementIBAN:iban,additionalCardMasks:["2222"]), credit=Account(id:"b",name:"Credit",bankName:"PUMB",lastFour:"3333",statementIBAN:other)
let date=bankDate("2027-01-12 15:00:00")!
let header="За рахунком №\nUA11 "+String(repeating:"1",count:25)+"\nІнформація про рух коштів\n"+other
check(bankStatementIBAN(header)==iban,"statement owner IBAN extracted, ignores table counterparty")
check(bankStatementIBAN("Переказ ACCOUNT "+iban)==nil,"no IBAN from an unlabelled transfer")
check(bankNormalizedIBAN("UA123") == nil,"invalid IBAN rejected")
check(bankRowMask("12345678****2222")=="2222" && bankRowMask("CARD*2222")==nil,"card column mask only")
let row=BankRow(source:"ПУМБ",date:date,signed:10000,note:"Example")
var batch=BankBatch(rows:[row],statementIBAN:iban,statementMasks:["1111","2222"])
check(finamiStatementAccount(batch,accounts:[debit,credit])==debit.id,"IBAN exact match and two cards on one account")
check(finamiStatementConflict(batch,account:credit,accounts:[debit,credit]),"wrong credit account blocked")
batch.statementIBAN=nil;batch.statementMasks=["2222"]
check(finamiStatementAccount(batch,accounts:[debit,credit])==debit.id,"additional card mask matches")
batch.statementMasks=["2222","3333"]
check(finamiStatementAccount(batch,accounts:[debit,credit])==nil,"ambiguous masks not auto-selected")
check(bankCreditContractSuffix("Погаш. з-ті за кред. договором № 1234567890 від 12/01/2027")=="7890","only contract suffix extracted before redaction")
let c=["2027-01-12 15:00:00","100.00 UAH","100.00 UAH","0.00 UAH","","TEST","Оплата"]
check(pumbRow(c)?.signed == -10000,"PUMB payment row recognized")
var cashRow=c;cashRow[6]="Отримання готівки"
check(pumbRow(cashRow)?.signed == -10000,"cash withdrawal parsed, not an income")
var blank=c;blank[6]="";check(pumbRow(blank)==nil,"blank direction not guessed")
check(bankKind(signed:100,note:"Shop",mcc:nil,operationType:"Повернення коштів",creditAccount:false)=="refund","refund classified by bank type")
check(bankKind(signed:-100,note:"погаш. з-ті за кред. договором",mcc:nil,operationType:"Списання",creditAccount:false)=="creditRepayment","credit contract description recognized")
let fx=FinamiFXAmounts(grossUSD:85000,feeUSD:1500,receivedUAH:4000000)!
let fxRows=fx.operations(source:usd,destination:debit,date:date)!
check(fxRows.count==2 && fx.netUSD==83500,"independent USD amount and fee")
check(FinamiLedgerIndex(operations:fxRows).balance(usd)==15000 && FinamiLedgerIndex(operations:fxRows).balance(debit)==4000000,"fee debited once in native USD and exact UAH credit")
check(fxRate(fxRows[0].exchangeRate!) != nil,"computed rate editable at eight decimals")
check(FinamiFXAmounts(grossUSD:100,feeUSD:100,receivedUAH:1)==nil,"invalid fee rejected")
let manual=Operation(id:"manual",kind:.transfer,amount:4000000,date:date,account:usd.id,destination:debit.id,sourceMinor:83500,destinationMinor:4000000,entryCurrency:"USD")
let bankRows=(0..<13).map{ i in BankRow(source:"ПУМБ",date:date.addingTimeInterval(Double(i)),signed:100000+Int64(i),note:"Example \(i)") }
let ops=bankRows.enumerated().map{ i,r in Operation(id:"r\(i)",kind:i<9 ? .unclassifiedCredit:.income,amount:r.signed,date:r.date,account:i<9 ? credit.id:debit.id,bankKey:r.key,sourceBank:r.source,importBatch:"example") }
let before=[manual]+ops
let merged=finamiGroupedConversion(transfer:manual,rows:ops,accounts:[usd,debit,credit],protected:[])!
check(merged.groupedBankParts?.count==13 && merged.destinationMinor==1300078 && merged.sourceMinor==83500,"all 13 bank legs preserved, source USD unchanged")
let ledger=FinamiLedgerIndex(operations:[merged]);check(ledger.balance(debit)==1300078 && ledger.balance(credit)==0 && ledger.balance(usd)==16500,"conversion counted once on correct account")
check(FinamiStatementMatchIndex(operations:[merged],account:debit.id).newRows(bankRows).isEmpty,"same statement after group imports zero new rows")
check(finamiGroupedConversion(transfer:merged,rows:ops,accounts:[usd,debit,credit],protected:[])==nil,"cannot group same transfer twice")
check(finamiGroupedConversion(transfer:manual,rows:ops,accounts:[usd,debit,credit],protected:[ops[0].id])==nil,"linked payment not consumed")
check(finamiGroupedConversion(transfer:manual,rows:[ops[0],ops[0]],accounts:[usd,debit,credit],protected:[])==nil,"duplicate selection rejected")
let move=finamiMoveStatementRows(before,ids:Set(ops.map(\.id)),to:debit,accounts:[usd,debit,credit],protected:[])!
check(move.filter{$0.kind != .transfer}.allSatisfy{$0.account==debit.id} && move.count==before.count,"batch correction preserves rows")
check(finamiMoveStatementRows(before,ids:[ops[0].id],to:debit,accounts:[usd,debit,credit],protected:[ops[0].id])==nil,"protected payment move rejected")
let undo=FinamiBalanceUndo(before:before,after:[merged]);check(undo.restore(current:[merged])==before && undo.restore(current:[merged,ops[0]])==nil,"undo rejects intervening ledger edits")
check(!finamiGroupedTransfersPreserved(before:[merged],after:[]) && finamiGroupedTransfersPreserved(before:[merged],after:[merged]),"grouped transfer protected from deletion")
// Exercise the exact calculation compiled into AccountEditor, not a rewritten copy.
var editor=AccountEditorCalculation(s:TestAccountStore(db:TestAccountDB(accounts:[debit]),operations:[Operation(kind:.income,amount:30000,date:date,account:debit.id)]),a:debit)
editor.correctBalance=true;editor.actualText="500"
check(editor.newOpening==20000,"AccountEditor correction uses Int64 movement")
var anchoredEditor=debit;anchoredEditor.opening=7000;anchoredEditor.reconciliationDate=date;anchoredEditor.reconciliationNet=90000
editor.s.db.accounts=[anchoredEditor];editor.a=anchoredEditor
check(editor.newOpening==20000,"AccountEditor correction ignores old anchor and uses complete recorded movement")
editor.s.db.accounts=[]
check(editor.newOpening==50000,"AccountEditor new account has zero movement")
var creditEditor=credit;creditEditor.accountType="credit";creditEditor.creditLimit=1000000
editor.a=creditEditor;editor.s.db.accounts=[creditEditor];editor.actualMode="available";editor.limitText="10000";editor.actualText="8500"
check(editor.newOpening == -150000,"AccountEditor available credit converted to net debt")
editor.actualMode="components";editor.ownText="0";editor.usedText="1500"
check(editor.newOpening == -150000,"AccountEditor component correction retains negative net debt")
editor.correctBalance=false;editor.opening="-100.50"
check(editor.newOpening == -10050,"AccountEditor normal opening edit preserves native minor units")
let anchor=finamiOpeningForAnchor(account:debit,operations:ops,net:2000000,at:date.addingTimeInterval(9))!
var anchored=debit;anchored.opening=anchor
check(FinamiLedgerIndex(operations:ops.filter{$0.date<=date.addingTimeInterval(9)}).balance(anchored)==2000000,"dated anchor retains historical rows")
anchored.reconciliationDate=date.addingTimeInterval(9);anchored.reconciliationNet=2000000
let dated=FinamiLedgerIndex(operations:ops,accounts:[anchored])
let late=Operation(kind:.income,amount:1000,date:date.addingTimeInterval(-100),account:debit.id)
check(dated.balance(anchored)==FinamiLedgerIndex(operations:ops+[late],accounts:[anchored]).balance(anchored),"late import before anchor cannot inflate current balance")
let future=Operation(kind:.expense,amount:1234,date:date.addingTimeInterval(100),account:debit.id)
check(FinamiLedgerIndex(operations:ops+[future],accounts:[anchored]).balance(anchored)==dated.balance(anchored)-1234,"new movement after anchor changes balance normally")
check(FinamiLedgerIndex(operations:[merged]).balanceAt(debit,date:date.addingTimeInterval(1))==200001,"historical grouped bank credits use each bank leg date")
let delta=Operation(kind:.expense,amount:manual.amount-merged.amount,date:date,account:debit.id)
check(finamiRedundantFXAdjustment(delta,original:manual,grouped:merged,protected:[]),"matching manual FX difference offered only for explicit confirmation")
var realFee=delta;realFee.bankKey="real-fee"
check(!finamiRedundantFXAdjustment(realFee,original:manual,grouped:merged,protected:[]),"bank-confirmed fee never removed as redundant")
check(finamiValidGroupedBankParts(merged),"group metadata validates sum and keys")
var broken=merged;broken.destinationMinor=1
check(!finamiValidGroupedBankParts(broken),"corrupt group total rejected")
let purchase=Operation(id:"purchase",kind:.expense,amount:5000,date:date,category:"Food",note:"Shop",account:debit.id)
var refund=Operation(id:"refund",kind:.unclassifiedCredit,amount:2000,date:date.addingTimeInterval(1),note:"Shop",account:debit.id,bankType:"Повернення коштів")
check(finamiRefundChoices(refund,operations:[purchase],merchantKey:{$0.lowercased()}).map(\.id)==[purchase.id],"refund matched to original purchase")
refund.kind = .refund;refund.refundOriginalID=purchase.id
var ledgerRows=[purchase,refund]
check(finamiSynchronizeRefundLinks(&ledgerRows) && ledgerRows[1].category=="Food" && FinamiLedgerIndex(operations:ledgerRows).balance(debit) == -3000,"partial refund retains ledger and inherits category")
var excess=refund;excess.id="excess";excess.amount=4000
var excessRows=[purchase,refund,excess];check(!finamiSynchronizeRefundLinks(&excessRows),"refund cannot exceed original purchase")
var missing=[refund];check(!finamiSynchronizeRefundLinks(&missing),"cannot delete purchase with linked refund")
if CommandLine.arguments.count>1 {
    struct Sample:Decodable {var accounts:[Account];var operations:[Operation]}
    let backup=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
    var kyiv=Calendar(identifier:.gregorian);kyiv.timeZone=TimeZone(identifier:"Europe/Kyiv")!
    for t in backup.operations where t.kind == .transfer && backup.accounts.first(where:{$0.id==t.account})?.code=="USD" {
        let candidates=backup.operations.filter{finamiGroupedConversion(transfer:t,rows:[$0],accounts:backup.accounts,protected:[],calendar:kyiv) != nil}
        if let g=finamiGroupedConversion(transfer:t,rows:candidates,accounts:backup.accounts,protected:[],calendar:kyiv) {
            let adjustments=backup.operations.filter{finamiRedundantFXAdjustment($0,original:t,grouped:g,protected:[],calendar:kyiv)}
            print("LOCAL BACKUP (read only): \(candidates.count) matching bank credits; \(Set(candidates.map(\.account)).count) source accounts; \(adjustments.count) possible already-included manual difference")
            check(g.groupedBankParts?.count==candidates.count && finamiValidGroupedBankParts(g),"actual backup supports grouped conversion without dropping bank keys")
        }
    }
}
var metadataRow=bankRows[0];metadataRow.postingKnown=true;metadataRow.postingDate=date;metadataRow.creditContractSuffix="1234"
let metaBatch=BankBatch(rows:[metadataRow],statementIBAN:iban)
var oldRow=ops[0];oldRow.account=debit.id
let update=finamiEnrichStatementMetadata(metaBatch,operations:[oldRow],account:debit.id)
check(update.count==1 && update.operations[0].bankPostingDate==date && update.operations[0].creditContractSuffix=="1234" && update.operations[0].signedNative==oldRow.signedNative,"reimport updates missing metadata without ledger mutation")
check(finamiEnrichStatementMetadata(metaBatch,operations:update.operations,account:debit.id).count==0,"metadata update is idempotent")
let persisted=try JSONDecoder().decode(Operation.self,from:JSONEncoder().encode(merged));check(persisted==merged,"group metadata roundtrip")
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" "$tmp/AccountEditorCalculation.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiStatementMatch.swift Finora/FinamiBalanceCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test" "$@"
