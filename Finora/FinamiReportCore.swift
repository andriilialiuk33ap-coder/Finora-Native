import Foundation

// All report amounts use the recorded UAH ledger value, never today's FX rate.
struct FinamiReportTotals {
    var income: Int64 = 0
    var expense: Int64 = 0
    var refunds: Int64 = 0
    var count = 0
    var review = 0
    var net: Int64 { income - expense }
    mutating func add(_ o: Operation) {
        count += 1
        if o.kind == .income { income += o.amount }
        expense += o.expenseValue
        if o.kind == .refund { refunds += o.amount }
        if o.kind.needsReview { review += 1 }
    }
}
struct FinamiReportSnapshot {
    var totals = FinamiReportTotals()
    var previous = FinamiReportTotals()
    var categories: [String: Int64] = [:]
    var accounts: [String: FinamiReportTotals] = [:]
    var periods: [Date: FinamiReportTotals] = [:]
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
                totals.add(o)
                if o.expenseValue != 0 { categories[o.expenseGroup, default: 0] += o.expenseValue }
                accounts[o.account, default: FinamiReportTotals()].add(o)
                if let key = calendar.dateInterval(of: annual ? .month : .day, for: o.date)?.start {
                    periods[key, default: FinamiReportTotals()].add(o)
                }
            } else if o.date >= previousInterval.start && o.date < previousInterval.end { previous.add(o) }
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
