import Foundation

// Exact key counts retain distinct identical transactions within a statement.
// Amount/date matches are suggestions only, never silently discarded or merged.
struct FinamiStatementMatchIndex {
    private var bySigned: [Int64: [Operation]] = [:]
    let existingKeys: [String]
    init(operations: [Operation], account: String) {
        var keys: [String] = []
        for o in operations {
            if o.account == account {
                if let key = o.bankKey { keys.append(key) }
                else { bySigned[o.signedNative, default: []].append(o) }
            }
            if o.kind == .transfer && o.destination == account && o.account != account {
                if let parts = o.groupedBankParts { keys.append(contentsOf: parts.map(\.key)) }
                else if let key = o.destinationBankKey { keys.append(key) }
                else { bySigned[o.destinationMinor ?? o.amount, default: []].append(o) }
            }
        }
        existingKeys = keys
    }
    func newRows(_ rows: [BankRow]) -> [BankRow] { bankNewRows(rows, existing: existingKeys) }
    func candidates(_ row: BankRow) -> [Operation] {
        (bySigned[row.signed] ?? []).filter { abs($0.date.timeIntervalSince(row.date)) <= 36 * 3600 }.sorted { lhs, rhs in
            let a = abs(lhs.date.timeIntervalSince(row.date)), b = abs(rhs.date.timeIntervalSince(row.date))
            return a == b ? lhs.id < rhs.id : a < b
        }
    }
}
func finamiAttachStatement(_ row: BankRow, to operation: inout Operation, account: String) -> Bool {
    guard abs(operation.date.timeIntervalSince(row.date)) <= 36 * 3600 else { return false }
    // Do not overwrite amounts, category, date, transfer destination or other metadata.
    if operation.account == account, operation.bankKey == nil, operation.signedNative == row.signed {
        operation.bankKey = row.key; return true
    }
    if operation.kind == .transfer, operation.destination == account, operation.account != account, operation.destinationBankKey == nil, operation.groupedBankParts == nil, (operation.destinationMinor ?? operation.amount) == row.signed {
        operation.destinationBankKey = row.key; return true
    }
    return false
}

// Reimport can enrich existing bank metadata, without recording money again.
func finamiEnrichStatementMetadata(_ batch:BankBatch,operations:[Operation],account:String)->(operations:[Operation],count:Int) {
    let byKey=Dictionary(grouping:batch.rows,by:\.key)
    let old=Dictionary(grouping:operations.filter{$0.account==account && $0.bankKey != nil && $0.groupedBankParts==nil},by:{$0.bankKey ?? ""})
    var result=operations,count=0
    for i in result.indices where result[i].account==account && result[i].groupedBankParts==nil {
        guard let key=result[i].bankKey,old[key]?.count==1,let rows=byKey[key],rows.count==1,let row=rows.first else{continue}
        var o=result[i]
        if let iban=batch.statementIBAN {
            guard o.statementIBAN==nil || o.statementIBAN==iban else{continue}
            o.statementIBAN=iban
        }
        if row.postingKnown==true {
            if o.bankPostingDate==nil {o.bankPostingDate=row.postingDate}
            o.bankPostingKnown=true
        }
        if o.creditContractSuffix==nil {o.creditContractSuffix=row.creditContractSuffix}
        if o != result[i] {result[i]=o;count+=1}
    }
    return (result,count)
}
