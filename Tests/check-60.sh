#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; cat Finora/Domain/FinancialRecords.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ yes:@autoclosure ()->Bool,_ text:String){precondition(yes(),text);print("PASS: "+text)}
var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(secondsFromGMT:0)!
let day=cal.date(from:.init(year:2026,month:11,day:26,hour:12))!
func d(_ months:Int)->Date {cal.date(byAdding:.month,value:months,to:day)!}
func op(_ id:String,_ kind:Kind = .expense,_ amount:Int64 = 10000,_ date:Date=day,_ note:String="Test Store",_ account:String="cash",_ category:String="Без категорії")->Operation {Operation(id:id,kind:kind,amount:amount,date:date,category:category,note:note,account:account)}
let a=op("a"), b=op("b",.expense,10000,day.addingTimeInterval(30)), c=op("c",.expense,10000,day.addingTimeInterval(200))
check(finamiReviewPairs([c,b,a])==[FinamiReviewPair(first:"a",second:"b")],"review pair is time-bounded, deterministic, not deletion")
check(finamiReviewPairs([a,op("b",.expense,10000,day,"Test Store","other")]).isEmpty,"same amount on another account not a duplicate suggestion")
check(finamiReviewPairs([a,op("b",.income)]).isEmpty,"opposite direction not a duplicate")
check(finamiReviewPairs([a,b],limit:0).isEmpty,"review result limit")
let charges=[op("old",.expense,9900,d(-2),"Streaming","cash","📺 Підписки"),op("prev",.expense,9900,d(-1),"Streaming","cash","📺 Підписки"),op("new",.expense,17900,day,"Streaming","cash","📺 Підписки")]
let price=finamiPriceChanges(charges,calendar:cal)
check(price.count==1 && price[0].previous==9900 && price[0].current==17900,"large subscription price increase detected")
check(finamiPriceChanges(Array(charges.suffix(2)),calendar:cal).isEmpty,"two charges insufficient for price-change inference")
check(finamiPriceChanges(charges.map{var v=$0;v.category="🛒 Продукти";return v},calendar:cal).isEmpty,"routine groceries not a subscription")
check(finamiCleanTags(" work, Work , , home ")==["work","home"],"tags trimmed and deduplicated")
check(finamiCleanTags((0..<25).map(String.init).joined(separator:",")).count==12,"tag count bounded")
var tagged=a;tagged.tags=["work"]
let restored=try JSONDecoder().decode(Operation.self,from:JSONEncoder().encode(tagged))
check(restored.tags==["work"],"tags round-trip")
let legacy=Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8)
let old=try JSONDecoder().decode(Operation.self,from:legacy)
check(old.tags==nil,"old JSON still decodes")
let history=[op("a",.income,30000),op("b",.expense,10000),op("c",.refund,3000),op("d",.unclassifiedCredit,50000),op("e",.transfer,90000),op("f",.expense,1000,d(-1)),op("future",.income,99999,day.addingTimeInterval(1))]
let months=finamiMonthInsights(history,ending:day,months:3,calendar:cal)
check(months.count==3 && months[0].count==0 && months[1].expense==1000,"empty months preserved and chronological")
check(months[2].income==30000 && months[2].expense==7000 && months[2].net==23000,"real income and refunds exact; transfer not income")
check(months[2].unclassifiedIn==50000 && months[2].review==1 && months[2].uncategorized==1,"unclear amounts separate from income")
check(finamiMonthInsights([],ending:day,months:37,calendar:cal).isEmpty,"invalid month range rejected")
check(finamiTokenUnits("120")==12_000_000_000 && finamiTokenUnits("0,07")==7_000_000,"8-decimal USDT conversion exact")
check(finamiTokenUnits("0.00000001")==1 && finamiTokenText(1)=="0,00000001","smallest token unit preserved")
check(finamiTokenUnits("0.000000001")==nil && finamiTokenUnits("-1")==nil && finamiTokenUnits("1e3")==nil,"invalid token precision, sign and exponent blocked")
check(finamiTokenText(11_993_000_000)=="119,93","token formatting exact")
let salary=FinamiExchangeRecord(id:"income",date:day,units:12_000_000_000)
let sale=FinamiExchangeRecord(id:"sale",kind:"sale",date:day.addingTimeInterval(1),units:12_000_000_000,fee:7_000_000,feeIncluded:true,orderUAH:600_039,receivedUAH:600_100,rate:"50.00")
check(finamiExchangeDebit(sale)==12_000_000_000 && finamiExchangeBalance([sale,salary])==0,"embedded fee exact; salary then sale closes balance")
check(sale.receivedUAH-sale.orderUAH==61,"actual order discrepancy retained as 61 kopecks, not inferred fee")
var plus=sale;plus.feeIncluded=false
check(finamiExchangeDebit(plus)==12_007_000_000 && finamiExchangeBalance([salary,plus])==nil,"fee on top requires extra funds")
check(finamiExchangeBalance([sale])==nil && finamiExchangeBalance([salary,salary])==nil,"negative token balance and duplicate ID rejected")
var early=sale;early.date=day.addingTimeInterval(-1)
check(finamiExchangeBalance([salary,early])==nil,"sale before receipt blocked")
var invalid=sale;invalid.fee=invalid.units
check(finamiExchangeDebit(invalid)==nil,"fee cannot consume entire sale")
let saved=try JSONDecoder().decode(FinamiExchangeRecord.self,from:JSONEncoder().encode(sale))
check(saved==sale,"exchange record exact roundtrip")
let partner=finamiPartnerPosition(limit:3_000_000,balances:[75_000,490_000,180_000],prepaid:60_000)!
check(partner.used==745_000 && partner.available==2_255_000,"shared partner cap excludes prepaid until posted")
check(finamiPartnerPosition(limit:100,balances:[120],prepaid:0)?.overLimit==20,"over-limit scenario")
check(finamiPartnerPosition(limit:100,balances:[-1],prepaid:0)==nil && finamiPartnerPosition(limit:100,balances:[Int64.max,1],prepaid:0)==nil,"invalid partner debt and overflow blocked")
var bank=op("bank",.unclassifiedCredit,15000,day);bank.sourceBank="TestBank";bank.sourceMinor=15000
var bank2=op("bank2",.unclassifiedCredit,25000,day);bank2.sourceBank="TestBank"
let account=Account(id:"cash",name:"Test",opening:10000)
check(finamiExchangeReceiptTotal(ids:["bank","bank2"],operations:[bank,bank2],accounts:[account],date:day,calendar:cal)==40000,"manual receipt linkage sums exact native UAH")
check(finamiExchangeReceiptTotal(ids:["bank","bank"],operations:[bank],accounts:[account],date:day,calendar:cal)==nil,"receipt cannot be selected twice")
check(finamiExchangeReceiptTotal(ids:["missing"],operations:[bank],accounts:[account],date:day,calendar:cal)==nil,"missing receipt marked unresolved")
check(finamiExchangeReceipt(bank,accounts:[account],date:d(-1),calendar:cal)==nil,"receipts outside three-day window blocked")
check(finamiExchangeReceipt(op("refund",.refund),accounts:[account],date:day,calendar:cal)==nil,"refund not treated as exchange receipt")
var linked=sale;linked.linkedReceiptIDs=["bank"]
var another=linked;another.id="sale2";another.units=1;another.fee=0
var enough=salary;enough.units=salary.units+100
check(finamiExchangeBalance([enough,linked,another])==nil,"one bank row cannot reconcile two exchange sales")
let group=FinamiPartnerGroup(id:"test-group",name:"Partner",limit:300000,prepaid:1000,obligationIDs:["a","b"])
check(finamiValidPartnerGroups([group]),"valid partner group")
var group2=group;group2.id="other"
check(!finamiValidPartnerGroups([group,group2]),"one installment cannot belong to two partner groups")
group2.obligationIDs=["c"]
check(finamiValidPartnerGroups([group,group2]),"independent partner groups valid")
let encoded=try JSONDecoder().decode(FinamiPartnerGroup.self,from:JSONEncoder().encode(group))
check(encoded==group,"partner group roundtrip")
var hidden=Account(id:"masked",name:"Masked",opening:99000);hidden.hideAmounts=true
let credit=Account(id:"credit",name:"Credit",opening:-3000,accountType:"credit",creditLimit:100000)
let usd=Account(id:"usd",name:"FX",opening:100,currency:"USD")
let snapshots=finamiHistoricalPositions(accounts:[account,credit,hidden,usd],operations:[op("exp",.expense,2000,day)],ending:day,months:2,usdRate:Decimal(40),calendar:cal)
check(snapshots.count==2 && snapshots[0].own==14000 && snapshots[1].own==12000 && snapshots[1].debt==3000 && snapshots[1].net==9000,"historical account positions exclude masked accounts and unused credit")
let omitted=finamiHistoricalPositions(accounts:[account,usd],operations:[],ending:day,months:1,usdRate:nil,calendar:cal)
check(omitted.first?.omitted==1 && omitted.first?.own==10000,"missing FX rate explicitly omitted")
let generated=(0..<100_000).map { i in op("synth-"+String(i),.expense,100,day.addingTimeInterval(-Double(i)*60),"Test") }
let before=Date();let computed=finamiMonthInsights(generated,ending:day,months:12,calendar:cal)
check(computed.reduce(0){$0+$1.count}==100_000 && computed.reduce(0){$0+$1.expense}==10_000_000,"100k synthetic operations monthly rollup exact")
print("BENCH: 100k monthly rollup Linux: \(Int(Date().timeIntervalSince(before)*1000)) ms")

SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" Finora/MoneyCore.swift Finora/FinamiIntelligenceCore.swift Finora/FinamiNextCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
