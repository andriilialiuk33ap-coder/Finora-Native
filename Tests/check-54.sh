#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; grep '^struct ForecastPreferences:' Finora/IzanamiFeatures.swift; } > "$tmp/Preferences.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ value: @autoclosure ()->Bool,_ title:String){precondition(value(),title);print("PASS: "+title)}
var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(secondsFromGMT:0)!
let start=cal.date(from:.init(year:2026,month:11,day:26))!
func d(_ n:Int)->Date{cal.date(byAdding:.day,value:n,to:start)!}
func plan(_ entries:[FinamiPlanningEntry]=[],daily:Int64=0,reserve:Int64=10000,horizon:Int=10,opening:Int64=100000)->FinamiPlanningResult?{finamiPlanning(start:start,horizon:horizon,opening:opening,reserve:reserve,daily:daily,entries:entries,calendar:cal)}
check(plan()!.safeDaily==9000 && plan()!.closing==100000,"reserve stays in closing balance, daily spend capacity exact")
let events=[FinamiPlanningEntry(date:d(2),amount:-30000),.init(date:d(4),amount:50000),.init(date:d(9),amount:-10000)]
let result=plan(events,daily:5000)!
check(result.closing==60000 && result.freeBeforeIncome==50000,"dated income and fixed debits, no double-counting reserve")
check(result.safeDaily==10000,"daily capacity constrained by cumulative cash flow")
let shortage=plan([.init(date:d(0),amount:-95000),.init(date:d(0),amount:100000)])!
check(shortage.firstReserveShortfall==start && shortage.safeDaily==0 && shortage.closing==105000,"same-day payments cannot assume incoming funds arrive first")
check(plan([.init(date:d(-1),amount:500),.init(date:d(10),amount:-200)])!.closing==100000,"horizon excludes prior dates and end boundary")
check(plan([],daily:9001)!.firstReserveShortfall==d(9),"last-day reserve shortfall detected")
check(plan([],daily:9000)!.firstReserveShortfall==nil,"exact reserve not shortfall")
check(plan([],horizon:0)==nil && plan([],horizon:367)==nil && plan([],daily:-1)==nil,"invalid horizon and spending blocked")
check(plan([.init(date:start,amount:Int64.max)],opening:Int64.max)==nil,"overflow rejected")
check(plan([],reserve:0,horizon:3,opening:10)!.safeDaily==3,"daily limit floors to minor units")
check(finamiEnvelope(limit:1000,spent:1200)?.remaining == -200,"envelope overrun")
check(finamiEnvelope(limit:1000,spent:-100)?.remaining == 1100,"refund reduces category spend")
check(finamiEnvelope(limit:0,spent:0)==nil,"zero limit is unset")
let old=try JSONDecoder().decode(ForecastPreferences.self,from:Data(#"{"expected":1000,"planned":200,"reserve":300,"days":30}"#.utf8))
check(old.expected==1000 && old.daily==nil && old.incomeDate==nil,"legacy scenario decodes without new fields")
var next=old;next.incomeDate=d(5);next.daily=100;next.includeSchedule=false
let restored=try JSONDecoder().decode(ForecastPreferences.self,from:JSONEncoder().encode(next))
check(restored.daily==100 && restored.incomeDate==d(5) && restored.includeSchedule==false,"new scenario roundtrip")
SWIFT
swiftc -swift-version 5 Finora/FinamiPlanningCore.swift "$tmp/Preferences.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
