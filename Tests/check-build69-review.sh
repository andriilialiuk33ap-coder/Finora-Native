#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ test: @autoclosure () -> Bool, _ message: String) { precondition(test(), message); print("PASS: " + message) }
func blockers(name: String = "ПУМБ · Сплачуйте частинами", total: Int64? = 1200000, remaining: Int64? = 400000, monthly: Int64? = 400000, date: Bool = true, confirmed: Bool = true, foreign: Bool = false, target: Bool = true, exact: Bool = false, similar: Bool = false, override: Bool = false, reminder: Bool = true) -> [String] {
    FinamiScanParser.installmentBlockers(name: name, total: total, remaining: remaining, monthly: monthly, dateChecked: date, checked: confirmed, foreign: foreign, targetExists: target, exact: exact, similar: similar, duplicateOverride: override, reminderValid: reminder)
}
check(blockers().isEmpty, "PUMB confirmed valid amounts permit saving")
check(blockers(date: false).count == 1, "unconfirmed date has explicit blocker")
check(blockers(confirmed: false).count == 1, "unconfirmed data has explicit blocker")
check(blockers(date: false, confirmed: false).count == 2, "both confirmations independent")
check(blockers(name: "  ").count == 1, "empty name blocked")
check(blockers(total: nil).count == 1, "missing total blocked")
check(blockers(remaining: 1200001).count == 1, "excess remaining blocked")
check(blockers(monthly: 0).count == 1, "zero regular payment with debt blocked")
check(blockers(remaining: 0, monthly: 0).isEmpty, "fully repaid loan allowed")
check(blockers(foreign: true).count == 1, "foreign currency remains blocked")
check(blockers(target: false).count == 1, "missing update target blocked")
check(blockers(exact: true, similar: true, override: true).count == 1, "exact duplicate cannot be overridden")
check(blockers(similar: true).count == 1 && blockers(similar: true, override: true).isEmpty, "possible duplicate needs explicit override")
check(blockers(reminder: false).count == 1, "invalid reminder blocked")
check(blockers(name: "", total: nil, date: false, confirmed: false, foreign: true, target: false, exact: true, reminder: false).count == 8, "all blockers visible together")
SWIFT
swiftc -warnings-as-errors Finora/BankCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
