import Foundation

// Explicit matching: no amount-only automatic linkage, one recorded payment per operation.
enum FinamiPaymentMode: String, CaseIterable, Identifiable {
    case newOperation = "Створити списання", existing = "Вже є в операціях", markOnly = "Лише позначити сплаченим"
    var id: String { rawValue }
}
func finamiEligiblePaymentOperations(_ operations: [Operation], records: [FinamiPaidRecord], account: String, currency: String, amount: Int64, date: Date) -> [Operation] {
    let used = Set(records.compactMap(\.operationID))
    return operations.filter { o in
        o.account == account && finamiPaymentDebitKind(o.kind) && (currency == "UAH" || o.entryCurrency == currency) && (o.sourceMinor ?? o.amount) == amount && !used.contains(o.id) && o.date <= Date() && abs(o.date.timeIntervalSince(date)) <= 7 * 86400
    }.sorted { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
}
func finamiNewPaymentOperation(name: String, account: Account, currency: String, amount: Int64, date: Date, kind: Kind, rate: Decimal?, categories: [String], preferredCategory: String = "💳 Розстрочка") -> Operation? {
    guard amount > 0, amount <= 1_000_000_000_000, account.code == currency, kind == .expense || kind == .creditRepayment else { return nil }
    let converted: Int64
    if currency == "USD" { guard let rate, let value = fxMinor(amount, rate: rate), value > 0 else { return nil }; converted = value }
    else { guard currency == "UAH" else { return nil }; converted = amount }
    let category = kind == .expense && categories.contains(preferredCategory) ? preferredCategory : "Без категорії"
    var operation = Operation(kind: kind, amount: converted, date: date, category: category, note: name, account: account.id)
    operation.sourceMinor = amount; operation.entryCurrency = currency
    if currency == "USD" { operation.exchangeRate = rate.map(fxString) }
    return operation
}
func finamiAdvanceObligation(_ o: inout Obligation, scheduled: Date, amount: Int64, calendar: Calendar = .current) -> Bool {
    guard o.due == scheduled, amount > 0, o.remaining >= amount else { return false }
    let expected = o.monthly > 0 ? min(o.monthly, o.remaining) : o.remaining
    guard expected == amount else { return false }
    let remainder = o.remaining - amount
    if remainder > 0 { guard let next = calendar.date(byAdding: .month, value: 1, to: o.due), next > o.due else { return false }; o.due = next }
    o.paid += amount
    return true
}

// A payment can only be linked to a real outgoing ledger entry. Native amounts
// are compared in the currency of the debited account, not the reporting currency.
func finamiPaymentDebitKind(_ kind: Kind) -> Bool {
    [.expense, .creditRepayment, .transfer, .movementOut, .unclassifiedDebit].contains(kind)
}
func finamiPaymentDraftMatches(_ operation: Operation, account: Account, currency: String, amount: Int64, now: Date = Date()) -> Bool {
    operation.account == account.id && account.code == currency && amount > 0 &&
    (operation.sourceMinor ?? operation.amount) == amount && operation.amount > 0 &&
    operation.date <= now && finamiPaymentDebitKind(operation.kind)
}
// Linked debits are not silently removed or changed by editing or batch deletion.
// Notes, categories and statement metadata can still be updated.
func finamiLinkedOperationsPreserved(before: Database, after: Database) -> Bool {
    let ids = Set((before.paidRecords ?? []).compactMap(\.operationID))
    guard !ids.isEmpty else { return true }
    let afterByID = Dictionary(after.operations.filter { ids.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return before.operations.filter { ids.contains($0.id) }.allSatisfy { old in
        guard let new = afterByID[old.id] else { return false }
        return old.kind == new.kind && old.account == new.account && old.destination == new.destination &&
            old.amount == new.amount && (old.sourceMinor ?? old.amount) == (new.sourceMinor ?? new.amount) &&
            (old.destinationMinor ?? old.amount) == (new.destinationMinor ?? new.amount) && old.date == new.date
    }
}

// The first occurrence can be partially paid. Extra principal reduces remaining debt,
// but never pretends that the bank waived or moved multiple due dates.
func finamiApplyInstallment(_ o: inout Obligation, scheduled: Date, amount: Int64, calendar: Calendar = .current) -> Bool {
    guard o.kind == .installment, o.due == scheduled, amount > 0, amount <= o.remaining, o.nextCharge > 0 else { return false }
    let due = o.nextCharge
    if amount < due { o.currentDuePaid = max(0,o.currentDuePaid ?? 0) + amount }
    else {
        if o.remaining > amount { guard let next=calendar.date(byAdding:.month,value:1,to:o.due),next>o.due else{return false};o.due=next }
        o.currentDuePaid=nil
    }
    o.paid += amount; return true
}
func finamiReminderFingerprint(_ values: [PersonalReminder]) -> Data? {
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try? encoder.encode(values.sorted{$0.id<$1.id})
}
