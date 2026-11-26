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
                if let key = o.destinationBankKey { keys.append(key) }
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
    if operation.kind == .transfer, operation.destination == account, operation.account != account, operation.destinationBankKey == nil, (operation.destinationMinor ?? operation.amount) == row.signed {
        operation.destinationBankKey = row.key; return true
    }
    return false
}
