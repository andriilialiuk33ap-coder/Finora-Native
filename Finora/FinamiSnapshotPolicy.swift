import Foundation

/// When to create and how long to keep local pre-change snapshots of the ledger.
/// Replaces "snapshot on every save, keep the last 12", which let a burst of edits erase every older restore point.
enum FinamiSnapshotPolicy {
    static let recentCount = 12
    static let dailyCount = 14
    static let protectedCount = 8
    static let weeklyCount = 4
    static let minimumInterval: TimeInterval = 300

    /// A snapshot of the state *before* a change. Frequent small edits share one snapshot;
    /// deletions and bulk changes always get their own.
    static func shouldSnapshot(newestAge: TimeInterval?, operationsBefore: Int, operationsAfter: Int, accountsBefore: Int, accountsAfter: Int, obligationsBefore: Int, obligationsAfter: Int) -> Bool {
        guard let age = newestAge else { return true }
        if age < 0 || age >= minimumInterval { return true }
        if operationsAfter < operationsBefore { return true }
        if abs(operationsAfter - operationsBefore) >= 5 { return true }
        if accountsAfter != accountsBefore { return true }
        if obligationsAfter < obligationsBefore { return true }
        return false
    }

    /// Keeps the newest `recentCount`, the newest snapshot of each of the last `dailyCount` days
    /// and of each of the last `weeklyCount` weeks. Everything else may be deleted.
    static func snapshotsToKeep(_ entries: [(id: String, date: Date)], now: Date, calendar: Calendar = Calendar.current) -> Set<String> {
        let sorted = entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        var keep = Set<String>()
        for entry in sorted.prefix(recentCount) { keep.insert(entry.id) }
        for entry in sorted.filter({ $0.id.hasPrefix("protected-") }).prefix(protectedCount) { keep.insert(entry.id) }
        let today = calendar.startOfDay(for: now)
        let dailyFloor = calendar.date(byAdding: .day, value: -(dailyCount - 1), to: today) ?? today
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let weeklyFloor = calendar.date(byAdding: .weekOfYear, value: -(weeklyCount - 1), to: currentWeek) ?? currentWeek
        var seenDays = Set<Date>()
        var seenWeeks = Set<Date>()
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.date)
            if entry.date >= dailyFloor, entry.date <= now, !seenDays.contains(day) {
                seenDays.insert(day)
                keep.insert(entry.id)
            }
            if entry.date >= weeklyFloor, entry.date <= now, let week = calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start, !seenWeeks.contains(week) {
                seenWeeks.insert(week)
                keep.insert(entry.id)
            }
        }
        return keep
    }
}
