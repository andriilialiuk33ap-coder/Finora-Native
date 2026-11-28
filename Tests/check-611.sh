#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition:@autoclosure ()->Bool,_ label:String){precondition(condition(),label);print("PASS: "+label)}
let t=Date(timeIntervalSince1970:1_800_000_000)
let debit=Account(id:"d",name:"Debit",opening:10000,accountType:"debit",bankName:"PUMB",lastFour:"1111",additionalCardMasks:["2222"])
let credit=Account(id:"c",name:"Credit",opening:-1000,accountType:"credit",bankName:"ПУМБ",lastFour:"3333",creditLimit:100000)
let row=BankRow(source:"ПУМБ",date:t,signed:5000,note:"Example")
let batch=BankBatch(rows:[row],statementLastFour:"2222",statementMasks:["1111","2222"])
let op=Operation(id:"old",kind:.unclassifiedCredit,amount:5000,date:t,account:credit.id,bankKey:row.key,sourceBank:row.source,importBatch:"old-batch")
let accounts=[debit,credit]
func moves(_ ops:[Operation],_ b:BankBatch=batch,_ protected:Set<String>=[])->[String:String] {finamiStatementReassignments(b,operations:ops,target:debit,accounts:accounts,protected:protected)}
check(moves([op])==[row.id:op.id],"exact wrong-account statement row proposed for explicit move")
check(moves([op],batch,[op.id]).isEmpty,"linked payment / exchange operation cannot move")
check(moves([op,op]).isEmpty,"ambiguous exact key cannot move")
var wrong=batch;wrong.statementLastFour="3333";wrong.statementMasks=["3333"]
check(moves([op],wrong).isEmpty && finamiStatementConflict(wrong,account:debit,accounts:accounts),"wrong statement identity blocked")
var ambiguous=batch;ambiguous.statementMasks=["1111","3333"]
check(moves([op],ambiguous).isEmpty,"ambiguous account masks do not propose moves")
var conflict=op;conflict.statementIBAN="UA"+String(repeating:"1",count:27)
check(moves([conflict]).isEmpty,"unverified prior IBAN not overwritten")
var wrongAmount=op;wrongAmount.amount=6000
check(moves([wrongAmount]).isEmpty,"changed financial amount needs manual review")
var refund=op;refund.id="refund";refund.kind = .refund;refund.bankKey=nil;refund.refundOriginalID=op.id
check(moves([op,refund]).isEmpty,"refund-linked original cannot move")
var moved=op;moved.account=debit.id
check(moves([moved]).isEmpty && FinamiStatementMatchIndex(operations:[moved],account:debit.id).newRows(batch.rows).isEmpty,"reimport after reassignment idempotent")
let before=FinamiLedgerIndex(operations:[op]),after=FinamiLedgerIndex(operations:[moved])
check(after.balance(debit)==before.balance(debit)+5000 && after.balance(credit)==before.balance(credit)-5000,"reassignment preserves total net movement")
check(FinamiBalanceUndo(before:[op],after:[moved]).restore(current:[moved])==[op],"undo exact reassignment")
check(finamiEstimatedNetFromAvailable(0,limit:100000)==nil,"zero available is ambiguous")
check(finamiEstimatedNetFromAvailable(1178040,limit:3205975)==(-2027935),"credit available converts to signed net only on explicit estimation")
check(finamiEstimatedNetFromAvailable(3410479,limit:0)==3410479,"debit estimated net separately from holds")
let net=CardPosition.netFrom(own:0,used:2027935)!
let position=CardPosition(net:net,limit:3205975)
check(position.used==2027935 && position.unused==1178040 && position.available==1178040,"shared credit formula matches confirmed bank components")
var anchored=debit;anchored.reconciliationDate=t;anchored.reconciliationNet=3410479;anchored.opening=finamiOpeningForAnchor(account:debit,operations:[moved],net:3410479,at:t)!
var later=Operation(kind:.expense,amount:1000,date:t.addingTimeInterval(1),account:debit.id)
let anchoredIndex=FinamiLedgerIndex(operations:[moved,later],accounts:[anchored])
check(anchoredIndex.balance(anchored)==3409479 && anchoredIndex.balanceAt(anchored,date:t)==3410479,"anchor plus later movement; old imports do not inflate balance")
anchored.reconciliationEstimated=true
let roundtrip=try JSONDecoder().decode(Account.self,from:JSONEncoder().encode(anchored))
check(roundtrip.reconciliationEstimated==true && roundtrip.reconciliationNet==3410479,"estimated anchor provenance persists")
check(op.sourceLabel=="Банківська виписка" && later.sourceLabel=="Ручний / невідоме джерело","sources distinguished without inventing origin")
later.captureSource="Apple Pay";check(later.sourceLabel=="Apple Pay","capture provenance retained")
// Reproduce the 13-leg exchange pattern with synthetic keys and no identifying details.
let usd=Account(id:"u",name:"Exchange",opening:82000,currency:"USD")
let amounts:[Int64]=[200000,2613700,250000,190000,135000,100000,100000,140100,51300,100000,50000,50400,3600]
let transfer=Operation(id:"fx",kind:.transfer,amount:3984380,date:t,account:usd.id,destination:debit.id,sourceMinor:82000,destinationMinor:3984380)
let legs=amounts.enumerated().map { i,v in Operation(id:"leg\(i)",kind:.unclassifiedCredit,amount:v,date:t,account:i<9 ? credit.id:debit.id,bankKey:"key\(i)",sourceBank:"ПУМБ",importBatch:"example") }
let merged=finamiGroupedConversion(transfer:transfer,rows:legs,accounts:[usd,debit,credit],protected:[])!
check(merged.destinationMinor==3984100 && merged.groupedBankParts?.count==13,"13 bank deposits preserve actual sum and keys")
check(FinamiLedgerIndex(operations:[merged]).balance(debit)==debit.opening+3984100,"grouped exchange counted once")
check(FinamiLedgerIndex(operations:[merged]).balance(credit)==credit.opening,"wrong-account FX credits removed from credit ledger by confirmed grouping")
if CommandLine.arguments.count>1 {
    struct Backup:Decodable {var accounts:[Account];var operations:[Operation]}
    let b=try JSONDecoder().decode(Backup.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
    let cal=Calendar(identifier:.gregorian)
    guard let fx=b.operations.first(where:{$0.kind == .transfer && $0.sourceMinor==82000}), let d=b.accounts.first(where:{$0.id==fx.destination}) else {fatalError("Expected example backup")}
    let ledger=FinamiLedgerIndex(operations:b.operations,accounts:b.accounts)
    let candidates=b.operations.filter{finamiGroupedConversion(transfer:fx,rows:[$0],accounts:b.accounts,protected:[],calendar:cal) != nil}
    let g=finamiGroupedConversion(transfer:fx,rows:candidates,accounts:b.accounts,protected:[],calendar:cal)!
    check(ledger.balance(d)==3614479,"read-only supplied backup reproduces debit discrepancy")
    let c=b.accounts.first(where:{$0.isCredit && bankCanonicalName($0.bankName ?? "")=="pumb"})!
    let cp=CardPosition(net:ledger.balance(c),limit:c.limit)
    check(cp.used==446416 && cp.unused==2759559,"read-only supplied backup reproduces credit discrepancy")
    check(candidates.count==13 && g.destinationMinor==3984100,"read-only supplied backup has all 13 real exchange legs")
    check(candidates.filter{$0.account==d.id}.reduce(Int64(0)){$0+$1.signedNative}==204000,"four legitimate receipts already represented in manual FX total")
}
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiStatementMatch.swift Finora/FinamiBalanceCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test" "$@"
