import Foundation

struct FinamiAuditIssue: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let operationIDs: [String]
}
// Candidates only. Never delete or merge records automatically, including opposite entries on the same account.
func finamiAuditIssues(operations: [Operation], accounts: [Account], records: [FinamiPaidRecord]) -> [FinamiAuditIssue] {
    var result: [FinamiAuditIssue] = []
    let accountIDs = Set(accounts.map(\.id))
    for o in operations where !accountIDs.contains(o.account) || (o.kind == .transfer && (!accountIDs.contains(o.destination) || o.destination == o.account)) {
        result.append(.init(id:"account-"+o.id,title:"Некоректний рахунок",detail:"Перевір джерело та призначення операції.",operationIDs:[o.id]))
    }
    let keys = operations.flatMap { o in ([o.bankKey,o.destinationBankKey].compactMap{$0} + (o.groupedBankParts ?? []).map(\.key)).filter{!$0.isEmpty}.map{($0,o.id)} }
    for (key,rows) in Dictionary(grouping:keys,by:{$0.0}) where rows.count > 1 { result.append(.init(id:"key-"+key,title:"Повтор банківського ключа",detail:"Перевір виписку; нічого не видалено.",operationIDs:rows.map{$0.1})) }
    let candidates = operations.filter{$0.requiresReview && $0.amount > 0}
    let groups = Dictionary(grouping:candidates) { o in "\(o.amount)|\(o.date.timeIntervalSince1970)|\(finamiMerchantKey(o.note))" }
    for (key,rows) in groups where rows.contains(where:{$0.kind == .unclassifiedCredit}) && rows.contains(where:{$0.kind == .unclassifiedDebit}) {
        let same = Set(rows.map(\.account)).count == 1
        result.append(.init(id:"pair-"+key,title:same ? "Протилежні записи на одному рахунку" : "Можливий внутрішній переказ",detail:"Однакова сума, дата та опис. Перевір обидві виписки; автоматичне об’єднання небезпечне.",operationIDs:rows.map(\.id)))
    }
    let paymentIssues = Set(finamiPaymentIntegrityIssues(operations: operations, accounts: accounts, records: records))
    for issue in paymentIssues {
        let title: String
        switch issue.kind {
        case .duplicateRecord: title = "Повтор запису оплати"
        case .duplicateLink: title = "Операція пов’язана з кількома оплатами"
        case .missingDebit: title = "Втрачений зв’язок платежу"
        case .wrongDebit: title = "Неправильний тип пов’язаної операції"
        case .wrongAccount: title = "Рахунок оплати не збігається"
        case .wrongAmount: title = "Сума оплати не збігається"
        case .wrongCurrency: title = "Валюта оплати не збігається"
        case .invalidRecord: title = "Некоректний запис оплати"
        }
        result.append(.init(id: "payment-" + issue.kind.rawValue + "-" + issue.reference + "-" + (issue.operationID ?? ""), title: title, detail: "Перевір історію оплат. Нічого не змінено автоматично.", operationIDs: issue.operationID.map { [$0] } ?? []))
    }
    return result.sorted{$0.id<$1.id}
}
struct FinamiCategoryGroup: Identifiable {
    let id: String
    let merchant: String
    let kind: Kind
    let ids: [String]
    let suggestion: String
}
func finamiCategoryGroups(operations:[Operation], expense:[String], income:[String], learned:[String:String]) -> [FinamiCategoryGroup] {
    let unknown = operations.filter{($0.kind == .expense || $0.kind == .income) && ["Без категорії","Інше",""].contains($0.category) && !finamiMerchantKey($0.note).isEmpty}
    return Dictionary(grouping:unknown){$0.kind.rawValue+":"+finamiMerchantKey($0.note)}.compactMap { key, rows in
        guard let first=rows.first else{return nil}; let allowed=first.kind == .income ? income : expense
        let proposals=Set(rows.map {finamiIntelligentCategory($0.note,kind:$0.kind,allowed:allowed,learned:learned)})
        return FinamiCategoryGroup(id:key,merchant:finamiMerchantKey(first.note),kind:first.kind,ids:rows.map(\.id),suggestion:proposals.count==1 ? (proposals.first ?? "Без категорії") : "Без категорії")
    }.sorted{ $0.ids.count == $1.ids.count ? $0.id<$1.id : $0.ids.count>$1.ids.count }
}

// Explicitly confirmed matching UAH legs only. The resulting transfer preserves both
// bank keys and both native balances. Fees/FX/linked payments are not guessed.
func finamiTransferFromPair(_ first:Operation,_ second:Operation,accounts:[Account],records:[FinamiPaidRecord]) -> Operation? {
    let debit = first.kind == .unclassifiedDebit ? first : second
    let credit = first.kind == .unclassifiedCredit ? first : second
    guard debit.kind == .unclassifiedDebit,credit.kind == .unclassifiedCredit,debit.id != credit.id,debit.account != credit.account,
          debit.amount>0,debit.amount==credit.amount,debit.date==credit.date,
          finamiMerchantKey(debit.note)==finamiMerchantKey(credit.note),!finamiMerchantKey(debit.note).isEmpty,
          accounts.first(where:{$0.id==debit.account})?.code=="UAH",accounts.first(where:{$0.id==credit.account})?.code=="UAH",
          (debit.bankFee ?? 0)==0,(credit.bankFee ?? 0)==0,(debit.sourceMinor ?? debit.amount)==debit.amount,(credit.sourceMinor ?? credit.amount)==credit.amount,
          (debit.originalCurrency ?? "UAH")=="UAH",(credit.originalCurrency ?? "UAH")=="UAH",(debit.originalAmount ?? debit.amount)==debit.amount,(credit.originalAmount ?? credit.amount)==credit.amount,
          let sourceKey=debit.bankKey,let destinationKey=credit.bankKey,sourceKey != destinationKey,
          debit.destinationBankKey==nil,credit.destinationBankKey==nil,debit.scanImageID==nil,credit.scanImageID==nil,
          debit.captureSource==nil,credit.captureSource==nil,
          !records.contains(where:{$0.operationID==debit.id || $0.operationID==credit.id}) else{return nil}
    var transfer=debit;transfer.kind = .transfer;transfer.destination=credit.account;transfer.destinationBankKey=destinationKey;transfer.destinationBankNote=credit.note;transfer.mergedImportBatches=[debit.importBatch,credit.importBatch].compactMap{$0};transfer.sourceMinor=debit.amount;transfer.destinationMinor=credit.amount;transfer.entryCurrency="UAH";transfer.category="Без категорії";transfer.classificationReviewed=true
    return transfer
}
// Old bank-imported payments may already be reflected in the remaining balance.
// Linking them to history must not advance the schedule or debit an account again.
func finamiHistoricalPaymentRecord(obligation:Obligation,operation:Operation,accounts:[Account],records:[FinamiPaidRecord]) -> FinamiPaidRecord? {
    guard obligation.kind == .installment,finamiPaymentDebitKind(operation.kind),operation.date<=Date(),operation.amount>0,
          accounts.first(where:{$0.id==operation.account})?.code=="UAH",!records.contains(where:{$0.operationID==operation.id}) else{return nil}
    let amount=operation.sourceMinor ?? operation.amount
    let tracked=records.filter{$0.paymentID==obligation.id}.reduce(Int64(0)){$0+$1.amount}
    guard amount>0,tracked<=obligation.paid,amount<=obligation.paid-tracked else{return nil}
    return FinamiPaidRecord(paymentID:obligation.id,scheduledDate:operation.date,paidDate:operation.date,amount:amount,currency:"UAH",accountID:operation.account,operationID:operation.id,historicalOnly:true)
}

func finamiContractMatches(obligation:Obligation,operation:Operation)->Bool {
    let expected=obligation.creditContractSuffix ?? "", found=operation.creditContractSuffix ?? ""
    if expected.count==4,found.count==4 {return expected==found}
    return obligation.monthly>0 && (operation.sourceMinor ?? operation.amount)==obligation.monthly
}
