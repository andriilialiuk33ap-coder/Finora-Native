#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; sed -n '/^enum Kind:/,/^enum ObligationKind:/p' Finora/Finora.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ title: String) { precondition(condition(),title); print("PASS: \(title)") }
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT:0)!
func day(_ y:Int,_ m:Int,_ d:Int)->Date { cal.date(from:.init(year:y,month:m,day:d))! }
let allowed = ["📱 Зв’язок", "🛒 Продукти", "📺 Підписки", "🚕 Таксі", "💼 Зарплата", "Моя категорія", "Інша категорія"]
check(finamiIntelligentCategory("EASYPAY*LIFECELL KYIV UA",kind:.expense,allowed:allowed,learned:[:]) == "📱 Зв’язок", "PUMB alias and normalized vendor")
check(finamiIntelligentCategory("ATB MARKET",kind:.expense,allowed:allowed,learned:[:]) == "🛒 Продукти", "merchant category")
check(finamiIntelligentCategory("SALARY",kind:.income,allowed:allowed,learned:[:]) == "💼 Зарплата", "already-classified income category")
check(finamiIntelligentCategory("SALARY",kind:.transfer,allowed:allowed,learned:[:]) == "Без категорії", "no transaction type inference")
check(finamiIntelligentCategory("EASYPAY*LIFECELL KYIV UA",kind:.expense,allowed:allowed,learned:["expense:lifecell":"Моя категорія"]) == "Моя категорія", "normalized user category has priority")
check(finamiIntelligentCategory("LIFECELL UA",kind:.expense,allowed:allowed,learned:["expense:lifecell":"Моя категорія","expense:lifecell kyiv":"Інша категорія"]) == "Без категорії", "conflicting learned rules do not guess")
check(finamiIntelligentCategory("APPLE.COM/BILL",kind:.expense,allowed:allowed,learned:[:]) == "Без категорії", "ambiguous Apple invoice not assumed subscription")
check(finamiIntelligentCategory("ATB",kind:.expense,allowed:[],learned:[:]) == "Без категорії", "hidden or deleted category not restored")
let a=Account(id:"a",name:"PUMB",opening:100000), b=Account(id:"b",name:"OTP",opening:-5000,accountType:"credit",creditLimit:20000)
let ops=[Operation(id:"1",kind:.expense,amount:10000,date:day(2026,8,7),category:"📺 Підписки",note:"Netflix",account:a.id),Operation(id:"2",kind:.expense,amount:10000,date:day(2026,9,7),category:"📺 Підписки",note:"NETFLIX KYIV UA",account:a.id),Operation(id:"3",kind:.expense,amount:11000,date:day(2026,10,7),category:"📺 Підписки",note:"Netflix",account:a.id)]
let c = finamiRecurringCandidates(operations:ops,accounts:[a,b],now:day(2026,10,26),calendar:cal)
check(c.count==1 && c[0].amount==11000 && c[0].next==day(2026,11,7) && c[0].changedPrice, "three monthly charges and price change")
check(finamiRecurringCandidates(operations:Array(ops.prefix(2)),accounts:[a,b],now:day(2026,10,26),calendar:cal).isEmpty,"two purchases insufficient")
var groceries=ops; for i in groceries.indices { groceries[i].date=day(2026,10,7+i); groceries[i].note="ATB" }
check(finamiRecurringCandidates(operations:groceries,accounts:[a,b],now:day(2026,10,26),calendar:cal).isEmpty,"daily purchases not recurring")
var split=ops; split[2].account=b.id
check(finamiRecurringCandidates(operations:split,accounts:[a,b],now:day(2026,10,26),calendar:cal).isEmpty,"accounts never merged")
var generic=ops; for i in generic.indices { generic[i].note="APPLE.COM/BILL" }
check(finamiRecurringCandidates(operations:generic,accounts:[a,b],now:day(2026,10,26),calendar:cal).isEmpty,"aggregate Apple billing not a known contract")
check(finamiRecurringCandidates(operations:ops,accounts:[a,b],now:day(2027,1,1),calendar:cal).isEmpty,"stale subscription suggestion excluded")
let movements=[Operation(kind:.expense,amount:1000,date:day(2026,11,1),account:a.id),Operation(kind:.transfer,amount:5000,date:day(2026,11,2),account:a.id,destination:b.id),Operation(kind:.income,amount:10000,date:day(2026,11,5),account:a.id)]
let rec=finamiReconcile(account:a,operations:movements,observedAt:day(2026,11,2),reported:94000)
check(rec.difference==0 && rec.laterOperations==1,"historical reconciliation excludes later income")
check(finamiReconcile(account:b,operations:movements,observedAt:day(2026,11,2),reported:20000).difference==0,"credit and incoming transfer at observation")
check(finamiReconcile(account:a,operations:movements,observedAt:day(2026,11,2),reported:93500).difference == -500,"difference remains explicit, no ledger mutation")
let dec=DateInterval(start:day(2026,12,1),end:day(2027,1,1))
let schedule=finamiPlannedOccurrences(id:"loan",start:day(2026,11,7),amount:10000,remaining:15000,component:.month,step:1,interval:dec,calendar:cal)
check(schedule.count==1 && schedule[0].amount==5000 && schedule[0].projected,"last installment capped; forecast is not payable")
let week=finamiPlannedOccurrences(id:"sub",start:day(2026,12,1),amount:500,remaining:nil,component:.day,step:7,interval:dec,calendar:cal)
check(week.count==5 && !week[0].projected && week.dropFirst().allSatisfy(\.projected),"weekly recurrence and one current payable event")
let january=DateInterval(start:day(2027,1,1),end:day(2027,2,1))
check(finamiPlannedOccurrences(id:"loan",start:day(2026,11,7),amount:10000,remaining:15000,component:.month,step:1,interval:january,calendar:cal).isEmpty,"closed installment no future forecast")
var totals=FinamiReportTotals(); totals.add(Operation(kind:.income,amount:100));totals.add(Operation(kind:.movementIn,amount:200));totals.add(Operation(kind:.refund,amount:50));totals.add(Operation(kind:.creditDraw,amount:300));totals.add(Operation(kind:.unclassifiedCredit,amount:400))
check(totals.income==100 && totals.incoming==1050,"gross incoming separate from true income")
let current=DateInterval(start:day(2026,11,1),end:day(2026,12,1)), prior=DateInterval(start:day(2026,10,1),end:day(2026,11,1))
let compareOps=[Operation(kind:.income,amount:100,date:day(2026,10,3)),Operation(kind:.income,amount:300,date:day(2026,10,20)),Operation(kind:.income,amount:200,date:day(2026,11,3)),Operation(kind:.income,amount:900,date:day(2026,11,20))]
let compare=finamiComparableTotals(operations:compareOps,current:current,previous:prior,account:nil,now:day(2026,11,10),elapsed:true,calendar:cal)
check(compare.current.income==200 && compare.previous.income==100,"equal elapsed calendar days")
let full=finamiComparableTotals(operations:compareOps,current:current,previous:prior,account:nil,now:day(2026,11,10),elapsed:false,calendar:cal)
check(full.current.income==1100 && full.previous.income==400,"full-period comparison unchanged")
var cache=FinamiComparisonCache()
let cached=cache.totals(operations:compareOps,current:current,previous:prior,account:nil,now:day(2026,11,10),elapsed:true,calendar:cal)
check(cached.current.income==200,"comparison cache calculates expected result")
cache.removeAll()
let fresh=cache.totals(operations:[],current:current,previous:prior,account:nil,now:day(2026,11,10),elapsed:true,calendar:cal)
check(fresh.current.income==0,"comparison invalidation after ledger change")
let snap=FinamiWidgetSnapshot(ownUAH:12345,dueAmount:1000,dueCurrency:"UAH",dueDate:day(2026,12,1),updated:day(2026,11,26))
let data=try JSONEncoder().encode(snap)
check(FinamiWidgetSnapshot.decode(data,now:day(2026,11,26))==snap,"widget summary roundtrip")
check(FinamiWidgetSnapshot.decode(data,now:day(2026,11,27))==nil,"widget summary expires after 24h")
check(FinamiWidgetSnapshot.decode(Data(),now:day(2026,11,26))==nil,"invalidated or corrupted widget file hides financial data")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/MoneyCore.swift Finora/FinamiIntelligenceCore.swift Finora/FinamiReportCore.swift WidgetShared/FinamiWidgetData.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
