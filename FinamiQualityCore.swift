import Foundation

/// Derived dashboard values only; the ledger remains the source of truth.
struct FinamiDashboardMetrics {
    let income: Int64
    let expense: Int64
    let categories: [(key: String, value: Int64)]
    let recent: [Operation]

    init(operations: [Operation]) {
        var income: Int64 = 0, expense: Int64 = 0
        var categories: [String: Int64] = [:]
        var recent: [Operation] = []
        for operation in operations {
            income += operation.incomeValue
            let value = operation.expenseValue
            expense += value
            if value != 0 { categories[operation.expenseGroup, default: 0] += value }
            // Keep only the five latest records (largest dashboard recent block).
            if recent.count < 5 || operation.date > recent[4].date {
                let index = recent.firstIndex { $0.date < operation.date } ?? recent.endIndex
                recent.insert(operation, at: index)
                if recent.count > 5 { recent.removeLast() }
            }
        }
        self.income = income
        self.expense = expense
        self.categories = categories.filter { $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        self.recent = recent
    }
}

enum FinamiRepeatDraft {
    /// A fresh manual UAH draft, never a clone of bank identity, links, or fees.
    static func make(_ operation: Operation, accounts: [Account], masked: Bool, now: Date = Date()) -> Operation? {
        guard !masked, let account = accounts.first(where: { $0.id == operation.account }),
              account.hideAmounts != true, account.code == "UAH",
              operation.kind == .expense || operation.kind == .income,
              operation.amount > 0, operation.refundOriginalID == nil,
              operation.groupedBankParts == nil, operation.bankFee == nil,
              operation.originalCurrency == nil || operation.originalCurrency == "UAH",
              operation.entryCurrency == nil || operation.entryCurrency == "UAH",
              operation.sourceMinor == nil || operation.sourceMinor == operation.amount,
              operation.originalAmount == nil || operation.originalAmount == operation.amount else { return nil }
        return Operation(kind: operation.kind, amount: operation.amount, date: now,
                         category: operation.category, note: operation.note,
                         account: operation.account, tags: operation.tags)
    }
}
