#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ ok:@autoclosure ()->Bool,_ label:String){ precondition(ok(),label);print("PASS: " + label) }
let old=try JSONDecoder().decode(AppearancePreferences.self,from:Data(#"{"theme":"Gold","mode":"dark","font":"default","largeIcons":true,"glow":true,"modernAccountGrid":true,"hideAmounts":true}"#.utf8))
check(old.finamiLayout == "grid" && old.designLayout == nil,"legacy compact grid preserved")
check(FinamiDesignPolicy.layout("unknown",legacyGrid:false)=="cards","invalid layout falls back safely")
check(FinamiDesignPolicy.layout("list",legacyGrid:true)=="list","explicit list overrides legacy grid")
let fields:Set<String>=["own","limit","used","available"]
check(FinamiDesignPolicy.primaryField(fields:fields,credit:true,mode:"all")=="available","credit compact card labels available credit, not own cash")
check(FinamiDesignPolicy.primaryField(fields:fields,credit:true,mode:"own")=="own","own mode never chooses credit limit")
check(FinamiDesignPolicy.primaryField(fields:["own"],credit:true,mode:"credit")==nil,"credit mode never displays own funds")
check(FinamiDesignPolicy.primaryField(fields:["used"],credit:true,mode:"all")=="used","respects explicit visible fields")
check(FinamiDesignPolicy.primaryField(fields:[],credit:true,mode:"all")==nil,"hidden fields are not reintroduced")
check(FinamiDesignPolicy.primaryField(fields:["available"],credit:false,mode:"all")==nil,"debit never displays credit")
let names=["Black Titanium","Digital Bank","Compact Pro","Liquid Glass","Emerald Analytics","White Studio"]
for name in names { var prefs=old;prefs.applyFinamiDesign(name);check(prefs.design==name && prefs.hideAmounts==true && prefs.mode=="preset" && FinamiDesignPolicy.layouts.contains(prefs.finamiLayout),"profile \(name) valid and preserves privacy") }
var prefs=old;prefs.applyFinamiDesign("Compact Pro");prefs.designAccent="gold";prefs.designRadius=17;prefs.collapsedDashboard=["accounts"];prefs.reportsAccount="private";prefs.designPresets=["Mine":prefs.finamiStyleSnapshot]
let restored=try JSONDecoder().decode(AppearancePreferences.self,from:JSONEncoder().encode(prefs))
check(restored.designPresets?["Mine"]?["accent"]=="gold" && restored.designRadius==17 && restored.finamiLayout=="list","custom style roundtrip")
var fresh=AppearancePreferences();fresh.hideAmounts=false;fresh.reportsAccount="other";fresh.collapsedDashboard=["budget"];fresh.restoreFinamiStyle(restored.designPresets!["Mine"]!)
check(fresh.designRadius==17 && fresh.finamiLayout=="list" && fresh.hideAmounts==false && fresh.reportsAccount=="other" && fresh.collapsedDashboard==["budget"],"style restore leaves privacy, filters and collapsed state intact")
fresh.restoreFinamiStyle(["radius":"999","layout":"bogus","accent":"bogus"])
check(fresh.designRadius==30 && fresh.finamiLayout=="list" && fresh.designAccent==nil,"malformed custom preset safely bounded")
check(FinamiDesignPolicy.radius(-12)==0 && FinamiDesignPolicy.radius(12)==12,"radius bounded")
var bank=AppearancePreferences();bank.applyFinamiDesign("Digital Bank");bank.restoreFinamiStyle(old.finamiStyleSnapshot);check(bank.homeAccountLayout==nil && bank.homeAccountRight==nil,"restoring original style clears later card layout overrides")
SWIFT
swiftc -swift-version 5 -warnings-as-errors Finora/FinamiDesignPolicy.swift "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
# Test the actual production month function against the previous implementation.
cat > "$tmp/Month.swift" <<'SWIFT'
import Foundation
struct Operation { let date:Date; let id:Int }
struct Database { var operations:[Operation] }
func sameMonth(_ a:Date,_ b:Date)->Bool { Calendar.current.isDate(a,equalTo:b,toGranularity:.month) }
final class Store {
    var db:Database { didSet { dashboardMonthCache.removeAll() } }
    var dashboardMonthCache:[DateInterval:[Operation]]=[:]
    init(_ ops:[Operation]) { db=Database(operations:ops) }
SWIFT
sed -n '/^  func month(_ date: Date)/,/^  }/p' Finora/FinamiStore.swift >> "$tmp/Month.swift"
cat >> "$tmp/Month.swift" <<'SWIFT'
}
@main struct Harness {
    static func main() {
        let cal=Calendar.current
        let start=cal.dateInterval(of:.month,for:Date())!.start
        let ops=(0..<100000).map { Operation(date:start.addingTimeInterval(Double(($0 % 400)-200)*86400),id:$0) }
        let store=Store(ops)
        let reference=ops.filter{sameMonth($0.date,start)}.map(\.id)
        precondition(store.month(start).map(\.id)==reference)
        print("PASS: cached month exactly matches Calendar month filtering on 100k operations")
        let end=cal.dateInterval(of:.month,for:start)!.end
        store.db.operations=[.init(date:start.addingTimeInterval(-1),id:1),.init(date:start,id:2),.init(date:end.addingTimeInterval(-1),id:3),.init(date:end,id:4)]
        precondition(store.month(start).map(\.id)==[2,3])
        print("PASS: cache invalidation and exact inclusive start/exclusive end")
        for i in 1...12 { _=store.month(cal.date(byAdding:.month,value:i,to:start)!) }
        precondition(store.dashboardMonthCache.count<=4)
        print("PASS: month cache bounded to four entries")
        let refStore=Store(ops)
        var count=0;let t=Date()
        for _ in 0..<20 { count+=ops.filter{sameMonth($0.date,start)}.count }
        let direct=Date().timeIntervalSince(t)*1000
        var cached=0;let t2=Date()
        for _ in 0..<20 { cached+=refStore.month(start).count }
        let indexed=Date().timeIntervalSince(t2)*1000
        precondition(count==cached)
        print("BENCH: 100k synthetic rows, 20 same-month queries: direct \(direct) ms, cached \(indexed) ms (Linux, algorithm only)")
    }
}
SWIFT
swiftc -O -parse-as-library "$tmp/Month.swift" -o "$tmp/month"
"$tmp/month"
