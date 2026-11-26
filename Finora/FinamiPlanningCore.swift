import Foundation

// Planning is a read-only simulation, separate from the actual ledger.
struct FinamiPlanningEntry: Equatable {
    let date: Date
    let amount: Int64 // signed UAH minor units
}
struct FinamiPlanningDay: Equatable, Identifiable {
    let date: Date
    let balance: Int64
    let beforeIncome: Int64
    var id: Date { date }
}
struct FinamiPlanningResult: Equatable {
    let days: [FinamiPlanningDay]
    let closing: Int64
    let safeDaily: Int64
    let freeBeforeIncome: Int64
    let firstReserveShortfall: Date?
}
func finamiPlanning(start: Date, horizon: Int, opening: Int64, reserve: Int64, daily: Int64, entries: [FinamiPlanningEntry], calendar: Calendar = .current) -> FinamiPlanningResult? {
    guard (1...366).contains(horizon), reserve >= 0, daily >= 0, entries.count <= 100_000 else { return nil }
    let day = calendar.startOfDay(for: start)
    guard let end = calendar.date(byAdding: .day, value: horizon, to: day) else { return nil }
    var incoming: [Date: Decimal] = [:], outgoing: [Date: Decimal] = [:]
    for entry in entries where entry.date >= day && entry.date < end {
        let key = calendar.startOfDay(for: entry.date)
        if entry.amount >= 0 { incoming[key, default: 0] += Decimal(entry.amount) }
        else { outgoing[key, default: 0] += Decimal(entry.amount) }
    }
    func exact(_ n: Decimal) -> Int64? {
        guard n >= Decimal(Int64.min), n <= Decimal(Int64.max) else { return nil }
        return NSDecimalNumber(decimal: n).int64Value
    }
    var balance = Decimal(opening), noDaily = balance, noIncome = balance, safe = Decimal(Int64.max), firstShortfall: Date?
    var result: [FinamiPlanningDay] = []
    for i in 0..<horizon {
        guard let date = calendar.date(byAdding: .day, value: i, to: day) else { return nil }
        let debit = outgoing[date, default: 0], credit = incoming[date, default: 0]
        noDaily += debit; noIncome += debit
        // Conservative: debit before income on the same date. No assumed intraday credit.
        let limit = (noDaily - Decimal(reserve)) / Decimal(i + 1)
        safe = min(safe, limit)
        balance += debit - Decimal(daily)
        guard let pre = exact(balance) else { return nil }
        if balance < Decimal(reserve) && firstShortfall == nil { firstShortfall = date }
        balance += credit; noDaily += credit
        guard let closing = exact(balance) else { return nil }
        result.append(.init(date: date, balance: closing, beforeIncome: pre))
    }
    var floored = Decimal(), dailyLimit = max(0, safe)
    NSDecimalRound(&floored, &dailyLimit, 0, .down)
    guard let close = exact(balance), let capacity = exact(floored), let free = exact(noIncome - Decimal(reserve)) else { return nil }
    return .init(days: result, closing: close, safeDaily: capacity, freeBeforeIncome: free, firstReserveShortfall: firstShortfall)
}
// Envelope budgets allocate limits, not balances or additional expenses.
struct FinamiEnvelopeStatus: Equatable {
    let limit: Int64
    let spent: Int64
    var remaining: Int64 { limit - spent }
}
func finamiEnvelope(limit: Int64, spent: Int64) -> FinamiEnvelopeStatus? {
    guard limit > 0, limit <= 1_000_000_000_000, spent >= -1_000_000_000_000, spent <= 1_000_000_000_000 else { return nil }
    return .init(limit: limit, spent: spent)
}
