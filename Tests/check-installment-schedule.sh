#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# Compile actual payment model, schedule parser, and payment advancement with a minimal reminder stub.
{ echo 'import Foundation'; echo 'struct PersonalReminder: Codable {}'; cat Finora/Domain/PaymentModels.swift; sed -n '/^func finamiApplyInstallment(/,/^func finamiReminderFingerprint(/p' Finora/FinamiPaymentCore.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); print("PASS: " + name) }
let cal = Calendar(identifier: .gregorian)
let start = Date(timeIntervalSince1970: 1_800_000_000)
let next = start.addingTimeInterval(43 * 86400)
let zero = start.addingTimeInterval(-10 * 86400)
let rows = [FinamiScheduleRow(date:zero,amount:0), .init(date:start,amount:2500), .init(date:next,amount:7500)]
let confirmed = Obligation.outstandingSchedule(from:rows,remaining:10000,firstDue:start,calendar:cal)
check(confirmed?.map(\.amount) == [2500,7500], "zero row excluded from outstanding debit schedule")
check(Obligation.outstandingSchedule(from:rows,remaining:9999,firstDue:start,calendar:cal) == nil,"sum mismatch refuses activation")
check(Obligation.outstandingSchedule(from:rows,remaining:10000,firstDue:zero,calendar:cal) == nil,"zero date cannot be first payable date")
check(Obligation.outstandingSchedule(from:rows + [rows[1]],remaining:12500,firstDue:start,calendar:cal) == nil,"duplicate days refuse activation")
var o = Obligation(kind:.installment,target:10000,monthly:5000,due:start,confirmedSchedule:confirmed)
check(o.confirmedScheduleValid && o.nextCharge == 2500,"verified irregular first amount")
let encoded = try JSONEncoder().encode(o)
var decoded = try JSONDecoder().decode(Obligation.self,from:encoded)
check(decoded.confirmedSchedule == confirmed && decoded.confirmedScheduleValid,"confirmed schedule JSON roundtrip")
check(!finamiApplyInstallment(&decoded,scheduled:start,amount:3000),"ambiguous extra payment rejected")
check(decoded.paid == 0 && decoded.confirmedSchedule == confirmed,"failed payment leaves state unchanged")
check(finamiApplyInstallment(&o,scheduled:start,amount:500),"partial payment accepted")
check(o.nextCharge == 2000 && o.due == start && o.remaining == 9500 && o.confirmedScheduleValid,"partial charge and total remain consistent")
check(finamiApplyInstallment(&o,scheduled:start,amount:2000),"first charge settled")
check(o.due == next && o.nextCharge == 7500 && o.confirmedScheduleValid,"next actual date preserved")
check(finamiApplyInstallment(&o,scheduled:next,amount:7500),"final charge settled")
check(o.remaining == 0 && o.nextCharge == 0 && o.confirmedSchedule == [] && o.confirmedScheduleValid,"settled confirmed schedule stays closed")
check(finamiApplyInstallment(&decoded,scheduled:start,amount:10000) && decoded.confirmedScheduleValid && decoded.remaining == 0,"explicit full payoff closes schedule")
let legacy = Obligation(kind:.installment,target:10000,monthly:5000,due:start)
let legacyDecoded = try JSONDecoder().decode(Obligation.self,from:JSONEncoder().encode(legacy))
check(legacyDecoded.confirmedSchedule == nil && legacyDecoded.nextCharge == 5000,"legacy schedule remains estimated")
var invalid = legacy; invalid.confirmedSchedule = rows
check(!invalid.confirmedScheduleValid,"invalid persisted active schedule rejected")
let ocr = finamiScheduleRows(["12.12.2026 0 ₴", "12.01.2027 3533 ₴"],reference:start)
check(ocr.map(\.amount) == [0,353300],"OCR preserves explicit zero amount as evidence")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiScanCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
