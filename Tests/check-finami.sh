#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(secondsFromGMT: 0)!
func date(_ day: Int) -> Date { cal.date(from: DateComponents(year:2026,month:11,day:day))! }
let start = date(1), end = date(30).addingTimeInterval(86400)
precondition(finamiScheduledAmounts(start:date(2),amount:1000,remaining:nil,component:.day,step:7,from:start,until:end,calendar:cal) == [1000,1000,1000,1000,1000])
precondition(finamiScheduledAmounts(start:date(4),amount:1000,remaining:2500,component:.day,step:7,from:start,until:end,calendar:cal) == [1000,1000,500])
precondition(finamiScheduledAmounts(start:date(1),amount:1000,remaining:2500,component:.month,step:1,from:date(2),until:end,calendar:cal).isEmpty)
precondition(finamiScheduledAmounts(start:end,amount:1000,remaining:nil,component:.month,step:1,from:start,until:end,calendar:cal).isEmpty)
precondition(finamiScheduledAmounts(start:start,amount:1000,remaining:0,component:.month,step:1,from:start,until:end,calendar:cal).isEmpty)
precondition(finamiVoiceAmount("Витратив 450 гривень в АТБ") == 45000)
precondition(finamiVoiceAmount("Заплатив 1 250,50 грн") == 125050)
precondition(finamiVoiceAmount("20 грн і 50 грн") == nil)
precondition(finamiVoiceAmount("без суми") == nil)
precondition(finamiVoiceAmount("0 грн") == nil)
print("PASS: Finami monthly schedule and safe voice draft (10 assertions)")
SWIFT
swiftc -warnings-as-errors Finora/FinamiCore.swift "$tmp/main.swift" -o "$tmp/finami-tests"
"$tmp/finami-tests"
