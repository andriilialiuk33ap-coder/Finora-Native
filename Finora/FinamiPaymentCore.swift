import Foundation

// Explicit matching: no amount-only automatic linkage, one recorded payment per operation.
enum FinamiPaymentMode: String, CaseIterable, Identifiable {
    case newOperation = "Створити списання", existing = "Вже є в операціях", markOnly = "Лише позначити сплаченим"
    var id: String { rawValue }
}
func finamiEligiblePaymentOperations(_ operations: [Operation], records: [FinamiPaidRecord], account: String, currency: String, amount: Int64, date: Date) -> [Operation] {
    let used = Set(records.compactMap(\.operationID))
    return operations.filter { o in
        o.account == account && !o.kind.incoming && (currency == "UAH" || o.entryCurrency == currency) && (o.sourceMinor ?? o.amount) == amount && !used.contains(o.id) && o.date <= Date() && abs(o.date.timeIntervalSince(date)) <= 7 * 86400
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
