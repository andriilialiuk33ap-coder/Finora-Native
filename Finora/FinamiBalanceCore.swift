import Foundation

func finamiAccountMasks(_ a: Account) -> Set<String> {
    Set(([a.lastFour].compactMap{$0} + (a.additionalCardMasks ?? [])).filter{$0.count==4 && $0.allSatisfy{$0.isASCII && $0.isNumber}})
}
func finamiStatementAccount(_ batch:BankBatch, accounts:[Account]) -> String? {
    let bank=bankCanonicalName(batch.rows.first?.source ?? "")
    let candidates=accounts.filter{$0.code == "UAH" && ((($0.bankName ?? "").isEmpty && $0.statementIBAN != nil) || bankCanonicalName($0.bankName ?? "") == bank)}
    if let iban=batch.statementIBAN {
        let matched=candidates.filter{bankNormalizedIBAN($0.statementIBAN ?? "") == iban}
        if !matched.isEmpty {return matched.count==1 ? matched[0].id:nil}
    }
    let masks=Set(batch.statementMasks + [batch.statementLastFour].compactMap{$0})
    guard !masks.isEmpty else{return nil}
    let matched=candidates.filter { a in
        if let iban=batch.statementIBAN,let own=bankNormalizedIBAN(a.statementIBAN ?? ""),iban != own {return false}
        return !finamiAccountMasks(a).isDisjoint(with:masks)
    }
    return matched.count==1 ? matched[0].id:nil
}
func finamiStatementConflict(_ batch:BankBatch, account:Account, accounts:[Account]) -> Bool {
    if let iban=batch.statementIBAN,accounts.filter({bankNormalizedIBAN($0.statementIBAN ?? "")==iban}).count>1{return true}
    if let bank=batch.rows.first?.source,let assigned=account.bankName,!assigned.isEmpty,bankCanonicalName(bank) != bankCanonicalName(assigned){return true}
    if let iban=batch.statementIBAN,let own=bankNormalizedIBAN(account.statementIBAN ?? ""),iban != own {return true}
    if let identified=finamiStatementAccount(batch,accounts:accounts),identified != account.id{return true}
    if let last=batch.statementLastFour,!finamiAccountMasks(account).isEmpty,!finamiAccountMasks(account).contains(last){return true}
    return false
}
// A confirmed balance at a specific instant anchors the opening without erasing historical rows.
func finamiOpeningForAnchor(account:Account, operations:[Operation], net:Int64, at:Date) -> Int64? {
    var zero=account;zero.opening=0;zero.reconciliationDate=nil;zero.reconciliationNet=nil
    let movement=FinamiLedgerIndex(operations:operations).balanceAt(zero,date:at)
    let (opening,overflow)=net.subtractingReportingOverflow(movement)
    return !overflow && opening >= -1_000_000_000_000 && opening <= 1_000_000_000_000 ? opening:nil
}
struct FinamiFXAmounts: Equatable {
    let grossUSD:Int64
    let feeUSD:Int64
    let receivedUAH:Int64
    var netUSD:Int64 {grossUSD-feeUSD}
    var rate:Decimal {Decimal(receivedUAH)/Decimal(netUSD)}
    init?(grossUSD:Int64,feeUSD:Int64,receivedUAH:Int64) {
        guard grossUSD>0, feeUSD>=0, feeUSD<grossUSD, receivedUAH>0, grossUSD<=1_000_000_000_000,receivedUAH<=1_000_000_000_000 else{return nil}
        self.grossUSD=grossUSD;self.feeUSD=feeUSD;self.receivedUAH=receivedUAH
    }
    func operations(source:Account,destination:Account,date:Date) -> [Operation]? {
        guard source.code=="USD",destination.code=="UAH",source.id != destination.id else{return nil}
        let rateText=finamiFXRateText(rate)
        guard fxRate(rateText) != nil else{return nil}
        var result=[Operation(kind:.transfer,amount:receivedUAH,date:date,category:"Без категорії",note:"Обмін валют",account:source.id,destination:destination.id,originalAmount:netUSD,originalCurrency:"USD",sourceMinor:netUSD,destinationMinor:receivedUAH,entryCurrency:"USD",exchangeRate:rateText)]
        if feeUSD>0,let converted=fxMinor(feeUSD,rate:rate),converted>0 {
            result.append(Operation(kind:.expense,amount:converted,date:date,category:"🏦 Комісії",note:"Комісія обміну",account:source.id,originalAmount:feeUSD,originalCurrency:"USD",sourceMinor:feeUSD,entryCurrency:"USD",exchangeRate:rateText))
        } else if feeUSD>0 {return nil}
        return result
    }
}
// Grouping requires explicit selection; preserve bank keys and source USD amount.
func finamiGroupedConversion(transfer:Operation, rows:[Operation], accounts:[Account], protected:Set<String>, calendar:Calendar = .current) -> Operation? {
    guard transfer.kind == .transfer, transfer.groupedBankParts == nil, transfer.destinationBankKey == nil,transfer.bankKey==nil, !protected.contains(transfer.id),
          accounts.first(where:{$0.id==transfer.account})?.code=="USD",accounts.first(where:{$0.id==transfer.destination})?.code=="UAH",
          let source=transfer.sourceMinor,source>0, !rows.isEmpty,Set(rows.map(\.id)).count==rows.count else{return nil}
    let targetIBAN=accounts.first(where:{$0.id==transfer.destination})?.statementIBAN
    var parts:[FinamiBankPart]=[],total:Int64=0
    for r in rows {
        guard r.id != transfer.id,!protected.contains(r.id),r.kind == .income || r.kind == .unclassifiedCredit || r.kind == .movementIn,
              (r.bankType ?? "").range(of:"повернення",options:.caseInsensitive)==nil, r.refundOriginalID==nil,
              targetIBAN == nil || r.statementIBAN == nil || r.statementIBAN == targetIBAN,
              let key=r.bankKey,!key.isEmpty,r.groupedBankParts==nil,r.destinationBankKey==nil,r.scanImageID==nil,r.destination.isEmpty,
              accounts.first(where:{$0.id==r.account})?.code=="UAH",(r.bankFee ?? 0)==0,r.signedNative>0,
              calendar.isDate(r.date,inSameDayAs:transfer.date) else{return nil}
        let (next,overflow)=total.addingReportingOverflow(r.signedNative);guard !overflow,next<=1_000_000_000_000 else{return nil};total=next
        parts.append(.init(key:key,date:r.date,amount:r.signedNative,note:r.note,importBatch:r.importBatch,sourceBank:r.sourceBank,originalAmount:r.originalAmount,originalCurrency:r.originalCurrency,postingDate:r.bankPostingDate))
    }
    guard Set(parts.map(\.key)).count==parts.count else{return nil}
    var result=transfer;result.amount=total;result.destinationMinor=total;result.originalAmount=source;result.originalCurrency="USD";result.entryCurrency="USD"
    result.exchangeRate=finamiFXRateText(Decimal(total)/Decimal(source))
    guard fxRate(result.exchangeRate ?? "") != nil else{return nil}
    result.groupedBankParts=parts.sorted{$0.date<$1.date};result.mergedImportBatches=Array(Set(parts.compactMap(\.importBatch))).sorted()
    return result
}
func finamiMoveStatementRows(_ operations:[Operation], ids:Set<String>, to:Account, accounts:[Account], protected:Set<String>) -> [Operation]? {
    guard !ids.isEmpty, to.code=="UAH",ids.isDisjoint(with:protected) else{return nil}
    let selected=operations.filter{ids.contains($0.id)}
    guard selected.count==ids.count,selected.allSatisfy({ o in o.kind != .transfer && o.bankKey != nil && o.destination.isEmpty && o.groupedBankParts==nil && (to.statementIBAN == nil || o.statementIBAN == nil || to.statementIBAN == o.statementIBAN) && accounts.first(where:{$0.id==o.account})?.code==to.code}) else{return nil}
    return operations.map { o in var result=o;if ids.contains(o.id){result.account=to.id};return result }
}
struct FinamiBalanceUndo: Codable {
    let before:[Operation]
    let after:[Operation]
    func restore(current:[Operation]) -> [Operation]? {current==after ? before:nil}
}

func finamiFXRateText(_ rate:Decimal)->String {var input=rate;var rounded=Decimal();NSDecimalRound(&rounded,&input,8,.plain);return NSDecimalNumber(decimal:rounded).stringValue}

func finamiGroupedTransfersPreserved(before:[Operation],after:[Operation])->Bool {
    let grouped=before.filter{$0.groupedBankParts != nil}
    guard !grouped.isEmpty else{return true}
    let lookup=Dictionary(after.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
    return grouped.allSatisfy { old in
        guard var new=lookup[old.id] else{return false}
        new.note=old.note
        return old==new
    }
}

// Only an explicitly confirmed manual adjustment equal to the already absorbed conversion difference is removable.
func finamiRedundantFXAdjustment(_ o:Operation,original:Operation,grouped:Operation,protected:Set<String>,calendar:Calendar = .current)->Bool {
    let difference=(original.destinationMinor ?? original.amount)-(grouped.destinationMinor ?? grouped.amount)
    return difference>0 && o.kind == .expense && o.account==original.destination && o.signedNative == -difference && o.bankKey==nil && o.sourceBank==nil && o.captureSource==nil && o.scanImageID==nil && !protected.contains(o.id) && abs(o.date.timeIntervalSince(original.date))<=36*3600
}

func finamiValidGroupedBankParts(_ o:Operation)->Bool {
    guard let parts=o.groupedBankParts else{return true}
    guard o.kind == .transfer,!parts.isEmpty,Set(parts.map(\.key)).count==parts.count,parts.allSatisfy({!$0.key.isEmpty && $0.amount>0 && $0.amount<=1_000_000_000_000}) else{return false}
    var sum:Int64=0
    for p in parts {let (value,overflow)=sum.addingReportingOverflow(p.amount);guard !overflow,value<=1_000_000_000_000 else{return false};sum=value}
    return sum==(o.destinationMinor ?? o.amount)
}

func finamiIsRefundCandidate(_ o:Operation)->Bool {
    o.kind == .refund || (o.kind == .unclassifiedCredit && (o.bankType ?? "").range(of:"повернення",options:.caseInsensitive) != nil)
}
// Match and link only after user confirmation. This changes report categorization, never the ledger sign.
func finamiRefundChoices(_ refund:Operation,operations:[Operation],merchantKey:(String)->String)->[Operation] {
    let key=merchantKey(refund.note)
    guard finamiIsRefundCandidate(refund),!key.isEmpty,refund.signedNative>0 else{return []}
    var amounts:[String:Int64]=[:]
    for o in operations where o.id != refund.id {if let id=o.refundOriginalID {amounts[id,default:0] += o.signedNative}}
    return operations.filter{o in o.kind == .expense && o.account==refund.account && o.date<=refund.date && merchantKey(o.note)==key && -o.signedNative >= refund.signedNative+(amounts[o.id] ?? 0)}.sorted{$0.date>$1.date}
}
func finamiSynchronizeRefundLinks(_ operations:inout [Operation])->Bool {
    let linked=operations.indices.filter{operations[$0].refundOriginalID != nil}
    guard !linked.isEmpty else{return true}
    let lookup=Dictionary(operations.map{($0.id,$0)},uniquingKeysWith:{a,_ in a});var sums:[String:Int64]=[:]
    for i in linked {
        let o=operations[i]
        guard o.kind == .refund,let id=o.refundOriginalID,let original=lookup[id],original.kind == .expense,original.account==o.account,original.date<=o.date,o.signedNative>0 else{return false}
        let (sum,overflow)=(sums[id] ?? 0).addingReportingOverflow(o.signedNative)
        guard !overflow,sum <= -original.signedNative else{return false}
        sums[id]=sum
    }
    for i in linked {if let id=operations[i].refundOriginalID,let original=lookup[id] {operations[i].category=original.category}}
    return true
}
