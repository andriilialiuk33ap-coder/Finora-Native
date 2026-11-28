#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ test: @autoclosure () -> Bool, _ label: String) { precondition(test(), label); print("PASS: " + label) }
func oldBalance(_ a: Account, _ ops: [Operation]) -> Int64 {
    ops.reduce(a.opening) { n, o in
        if o.kind == .transfer { return n - (o.account == a.id ? (o.sourceMinor ?? o.amount) : 0) + (o.destination == a.id ? (o.destinationMinor ?? o.amount) : 0) }
        return n + (o.account == a.id ? o.signedNative : 0)
    }
}
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 26))!
let a = Account(id: "a", name: "A", opening: -20000)
let b = Account(id: "b", name: "B", opening: 30000, currency: "USD")
let c = Account(id: "c", name: "C", opening: 42)
let ops = Kind.allCases.enumerated().map { i, kind in
    Operation(id: "op-\(i)", kind: kind, amount: Int64(1000 + i), date: day, account: a.id, destination: b.id, sourceMinor: Int64(200 + i), destinationMinor: Int64(30 + i))
} + [Operation(kind: .transfer, amount: 200, date: day, account: b.id, destination: a.id), Operation(kind: .transfer, amount: 100, date: day, account: a.id, destination: a.id)]
let idx = FinamiLedgerIndex(operations: ops)
check([a,b,c].allSatisfy { idx.balance($0) == oldBalance($0, ops) }, "indexed balances match legacy including all kinds, FX and same-account transfer")
check([a,b,c].allSatisfy { x in idx.history(x.id).map(\.id) == ops.filter { $0.account == x.id || ($0.kind == .transfer && $0.destination == x.id) }.map(\.id) }, "history includes both transfer legs without duplication")
for account in [a,b,c] {
    let x = AccountActivity(account: account, operations: ops, month: day, calendar: cal)
    let y = AccountActivity(account: account, operations: idx.history(account.id), month: day, calendar: cal)
    check(x.history.map(\.id) == y.history.map(\.id) && x.income == y.income && x.spending == y.spending && x.count == y.count, "account activity unchanged for \(account.id)")
}
var changed = a; changed.opening += 123
check(idx.balance(changed) == idx.balance(a) + 123, "opening balance is not frozen in index")
let newer = Array(ops.dropFirst()) + [Operation(kind: .income, amount: 123456, date: day, account: a.id)]
check(FinamiLedgerIndex(operations: newer).balance(a) == oldBalance(a, newer), "rebuild after deletion and addition")
var cache = FinamiReportCache()
let first = cache.snapshot(operations: ops, date: day, annual: true, account: nil, calendar: cal)
let same = cache.snapshot(operations: ops, date: day.addingTimeInterval(60), annual: true, account: nil, calendar: cal)
check(first.totals.income == same.totals.income && first.reviewIDs == same.reviewIDs && first.interval == same.interval, "same period cached report equivalent")
let scoped = cache.snapshot(operations: ops, date: day, annual: true, account: b.id, calendar: cal)
check(scoped.accounts.keys.sorted() == [b.id], "account filter invalidates cache key")
let next = cache.snapshot(operations: ops, date: cal.date(byAdding: .year, value: 1, to: day)!, annual: true, account: nil, calendar: cal)
check(next.totals.count == 0 && next.previous.count == first.totals.count, "period change invalidates cache key")
let month = cache.snapshot(operations: ops, date: day, annual: false, account: nil, calendar: cal)
check(month.interval != first.interval, "month versus year changes cache key")
cache.removeAll()
let refreshed = cache.snapshot(operations: newer, date: day, annual: true, account: nil, calendar: cal)
let direct = FinamiReportSnapshot(operations: newer, date: day, annual: true, account: nil, calendar: cal)
check(refreshed.totals.income == direct.totals.income && refreshed.totals.expense == direct.totals.expense && refreshed.reviewIDs == direct.reviewIDs, "cache clear after write matches direct report")
// Synthetic optimized release-mode benchmark. No iPhone latency claims.
let accounts = (0..<20).map { Account(id: "a\($0)", name: "Account \($0)") }
var large: [Operation] = []
for i in 0..<20_000 {
    let kind: Kind = i % 5 == 0 ? .transfer : .expense
    let amount = Int64(100 + i % 1000)
    let source = accounts[i % 20].id
    let destination = accounts[(i + 1) % 20].id
    large.append(Operation(id: "b\(i)", kind: kind, amount: amount, date: day, account: source, destination: destination))
}
let repeats = 50
func measured(_ f: () -> Int64) -> (Double, Int64) { let t = DispatchTime.now().uptimeNanoseconds; let sum = f(); return (Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6, sum) }
let old = measured { var total: Int64 = 0; for _ in 0..<repeats { for a in accounts { total += oldBalance(a, large) } }; return total }
let new = measured { let index = FinamiLedgerIndex(operations: large); var total: Int64 = 0; for _ in 0..<repeats { for a in accounts { total += index.balance(a) } }; return total }
check(old.1 == new.1, "20k-operation benchmark identical checksum")
print(String(format: "BENCH: 20,000 synthetic operations, 20 accounts, 1,000 balance queries: legacy %.2f ms, indexed including build %.2f ms", old.0, new.0))
SWIFT
swiftc -O -warnings-as-errors "$tmp/Models.swift" Finora/FinamiReportCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
