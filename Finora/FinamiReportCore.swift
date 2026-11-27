import Foundation

// All report amounts use the recorded UAH ledger value, never today's FX rate.
struct FinamiReportTotals {
    var income: Int64 = 0
    var expense: Int64 = 0
    var refunds: Int64 = 0
    var receipts: Int64 = 0
    var neutralReceipts: Int64 = 0
    var transfersIn: Int64 = 0
    var transfersOut: Int64 = 0
    var creditDraw: Int64 = 0
    var creditTopUp: Int64 = 0
    var creditRepayment: Int64 = 0
    var unclassifiedIn: Int64 = 0
    var unclassifiedOut: Int64 = 0
    var count = 0
    var review = 0
    var net: Int64 { income - expense }
    var incoming: Int64 { income + neutralReceipts + refunds + transfersIn + creditDraw + creditTopUp + unclassifiedIn }
    // Gross movements are separate from income/expense. For internal transfers,
    // each account sees only its own leg; the aggregate sees both legs once.
    mutating func add(_ o: Operation, account: String? = nil) {
        if let account, o.account != account && !(o.kind == .transfer && o.destination == account) { return }
        count += 1
        switch o.kind {
        case .income: income += o.amount
        case .receipt:
            receipts += o.amount
            income += o.incomeValue
            neutralReceipts += o.amount - o.incomeValue
        case .refund: refunds += o.amount
        case .transfer:
            if account == nil || account == o.account { transfersOut += o.amount }
            if !o.destination.isEmpty && (account == nil || account == o.destination) { transfersIn += o.amount }
        case .movementIn: transfersIn += o.amount
        case .movementOut: transfersOut += o.amount
        case .creditDraw: creditDraw += o.amount
        case .creditRepaymentIncoming: creditTopUp += o.amount
        case .creditRepayment: creditRepayment += o.amount
        case .unclassifiedCredit: unclassifiedIn += o.amount
        case .unclassifiedDebit: unclassifiedOut += o.amount
        case .expense: break
        }
        expense += o.expenseValue
        if o.requiresReview { review += 1 }
    }
}
// Stable per-account display choices, independent of the ledger and report math.
enum FinamiAccountReportField: String, CaseIterable, Identifiable {
    case expense, income, refunds, transfersIn, transfersOut, creditDraw, creditTopUp, creditRepayment, unclassifiedIn, unclassifiedOut, net, review, receipts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: return "Чисті витрати"
        case .income: return "Доходи"
        case .refunds: return "Повернення покупок"
        case .receipts: return "Зарахування (усі)"
        case .transfersIn: return "Вхідні перекази / поповнення"
        case .transfersOut: return "Вихідні перекази / зняття"
        case .creditDraw: return "Отримано кредиту"
        case .creditTopUp: return "Поповнення кредитки"
        case .creditRepayment: return "Погашення кредиту"
        case .unclassifiedIn: return "Неуточнені надходження"
        case .unclassifiedOut: return "Неуточнені списання"
        case .net: return "Чистий потік"
        case .review: return "Уточнити операції"
        }
    }
    static let compact: [Self] = [.expense, .income]
    static func selected(account: String, preferences: [String: [String]]?) -> [Self] {
        guard let saved = preferences?[account] else { return allCases }
        let keys = Set(saved)
        return allCases.filter { keys.contains($0.rawValue) }
    }
    static func updating(_ preferences: [String: [String]]?, account: String, fields: [Self]) -> [String: [String]] {
        var result = preferences ?? [:]
        let keys = Set(fields.map(\.rawValue))
        result[account] = allCases.map(\.rawValue).filter { keys.contains($0) }
        return result
    }
    var needsIncomeEnabled: Bool { self == .income || self == .net }
    func amount(_ t: FinamiReportTotals) -> Int64? {
        switch self {
        case .expense: return t.expense
        case .income: return t.income
        case .refunds: return t.refunds
        case .receipts: return t.receipts
        case .transfersIn: return t.transfersIn
        case .transfersOut: return t.transfersOut
        case .creditDraw: return t.creditDraw
        case .creditTopUp: return t.creditTopUp
        case .creditRepayment: return t.creditRepayment
        case .unclassifiedIn: return t.unclassifiedIn
        case .unclassifiedOut: return t.unclassifiedOut
        case .net: return t.net
        case .review: return nil
        }
    }
    func isVisible(in totals: FinamiReportTotals, showIncome: Bool) -> Bool {
        if needsIncomeEnabled && !showIncome { return false }
        switch self {
        case .expense, .income, .net: return true
        case .review: return totals.review > 0
        default: return (amount(totals) ?? 0) != 0
        }
    }
}
struct FinamiReportSnapshot {
    var totals = FinamiReportTotals()
    var previous = FinamiReportTotals()
    var categories: [String: Int64] = [:]
    var accounts: [String: FinamiReportTotals] = [:]
    var periods: [Date: FinamiReportTotals] = [:]
    var reviewIDs: [String] = []
    let interval: DateInterval
    let previousInterval: DateInterval
    init(operations: [Operation], date: Date, annual: Bool, account: String?, calendar: Calendar = .current) {
        let unit: Calendar.Component = annual ? .year : .month
        let current = calendar.dateInterval(of: unit, for: date)!
        let priorDate = calendar.date(byAdding: unit, value: -1, to: current.start)!
        interval = current
        previousInterval = calendar.dateInterval(of: unit, for: priorDate)!
        // Half-open intervals prevent midnight at the start of the next period being counted twice.
        for o in operations {
            guard account == nil || o.account == account || (o.kind == .transfer && o.destination == account) else { continue }
            if o.date >= interval.start && o.date < interval.end {
                totals.add(o, account: account)
                if o.requiresReview { reviewIDs.append(o.id) }
                if o.expenseValue != 0 { categories[o.expenseGroup, default: 0] += o.expenseValue }
                if account == nil || account == o.account {
                    accounts[o.account, default: FinamiReportTotals()].add(o, account: o.account)
                }
                if o.kind == .transfer && !o.destination.isEmpty && o.destination != o.account && (account == nil || account == o.destination) {
                    accounts[o.destination, default: FinamiReportTotals()].add(o, account: o.destination)
                }
                if let key = calendar.dateInterval(of: annual ? .month : .day, for: o.date)?.start {
                    periods[key, default: FinamiReportTotals()].add(o, account: account)
                }
            } else if o.date >= previousInterval.start && o.date < previousInterval.end { previous.add(o, account: account) }
        }
    }
    var sortedCategories: [(key: String, value: Int64)] {
        categories.filter { $0.value != 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }
}
// Reorder a visible subset without dropping or moving hidden items out of their slots.
func finamiReorderSubset(_ all: [String], orderedSubset: [String]) -> [String] {
    let selected = Set(orderedSubset)
    guard selected.count == orderedSubset.count, selected.isSubset(of: Set(all)), Set(all).count == all.count else { return all }
    var iterator = orderedSubset.makeIterator()
    return all.map { selected.contains($0) ? (iterator.next() ?? $0) : $0 }
}

// Bounded to one snapshot. The owning Store invalidates after every database replacement.
struct FinamiReportCache {
    private struct Key: Equatable {
        let interval: DateInterval
        let annual: Bool
        let account: String?
        let calendar: Calendar
    }
    private var entry: (key: Key, value: FinamiReportSnapshot)?
    mutating func removeAll() { entry = nil }
    mutating func snapshot(operations: [Operation], date: Date, annual: Bool, account: String?, calendar: Calendar = .current) -> FinamiReportSnapshot {
        let key = Key(interval: calendar.dateInterval(of: annual ? .year : .month, for: date)!, annual: annual, account: account, calendar: calendar)
        if let entry, entry.key == key { return entry.value }
        let value = FinamiReportSnapshot(operations: operations, date: date, annual: annual, account: account, calendar: calendar)
        entry = (key, value)
        return value
    }
}

// Use the same number of calendar days for an unfinished period. Full historical periods remain full.
func finamiComparableTotals(operations: [Operation], current: DateInterval, previous: DateInterval, account: String?, now: Date = Date(), elapsed: Bool, calendar: Calendar = .current) -> (current: FinamiReportTotals, previous: FinamiReportTotals) {
    var a = FinamiReportTotals(), b = FinamiReportTotals()
    var currentEnd = current.end, previousEnd = previous.end
    if elapsed && current.start <= now && now < current.end {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        currentEnd = min(current.end, tomorrow)
        let days = calendar.dateComponents([.day], from: current.start, to: currentEnd).day ?? 0
        previousEnd = min(previous.end, calendar.date(byAdding: .day, value: days, to: previous.start) ?? previous.end)
    }
    for o in operations {
        if o.date >= current.start && o.date < currentEnd { a.add(o, account: account) }
        else if o.date >= previous.start && o.date < previousEnd { b.add(o, account: account) }
    }
    return (a,b)
}

struct FinamiComparisonCache {
    private struct Key: Equatable { let current: DateInterval; let previous: DateInterval; let account: String?; let day: Date; let elapsed: Bool; let calendar: Calendar }
    private var entry: (Key, FinamiReportTotals, FinamiReportTotals)?
    mutating func removeAll() { entry = nil }
    mutating func totals(operations: [Operation], current: DateInterval, previous: DateInterval, account: String?, now: Date = Date(), elapsed: Bool, calendar: Calendar = .current) -> (current: FinamiReportTotals, previous: FinamiReportTotals) {
        let key = Key(current:current,previous:previous,account:account,day:calendar.startOfDay(for:now),elapsed:elapsed,calendar:calendar)
        if let entry, entry.0 == key { return (entry.1,entry.2) }
        let result = finamiComparableTotals(operations:operations,current:current,previous:previous,account:account,now:now,elapsed:elapsed,calendar:calendar)
        entry = (key,result.current,result.previous)
        return result
    }
}
