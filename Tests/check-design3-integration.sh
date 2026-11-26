#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ ok: @autoclosure () -> Bool, _ label: String) { precondition(ok(), label); print("PASS: " + label) }
var p = try JSONDecoder().decode(AppearancePreferences.self,from:Data(#"{"theme":"Gold","mode":"dark","font":"default","largeIcons":true,"glow":true,"hideAmounts":true}"#.utf8))
check(p.designShowsUpcoming("amount") && p.designChart("flow") == "None", "legacy Design 3.0 integration defaults")
for (key, options) in FinamiDesignPolicy.componentOptions.sorted(by: {$0.key < $1.key}) {
    for style in options { p.setDesignStyle(style, for: key); check(p.designStyle(for:key)==style,"style registration " + key + "/" + style) }
}
p.setDesignUpcoming("amount",visible:false)
p.setDesignUpcoming("not-real",visible:true)
check(!p.designShowsUpcoming("amount") && p.designShowsUpcoming("date") && !p.designShowsUpcoming("not-real"),"upcoming field independence")
p.setDesignChart("Donut",block:"categories");p.setDesignChart("Heatmap",block:"periods");p.setDesignChart("Donut",block:"flow")
check(p.designChart("categories")=="Donut" && p.designChart("periods")=="Heatmap" && p.designChart("flow")=="None","chart compatibility")
p.designReportOrder=["review","review","invalid","flow"]
check(p.designOrderedReportBlocks.first=="review" && Set(p.designOrderedReportBlocks)==Set(FinamiDesignPolicy.reportBlocks) && p.designOrderedReportBlocks.count==7,"report block order normalized")
p.setDesignReportStyle("financePro",block:"categories");p.setDesignReportStyle("invalid",block:"categories")
check(p.designReportStyle("categories")=="financePro" && p.designReportStyle("flow")==p.designStyle(for:"reports"),"report style override independent")
p.setDesignSize("L",for:"report.categories");p.designHiddenSubscriptions=["s1"];p.designCalendarListCollapsed=true;p.designEditorKeyboard=true;p.designEditorConfirm=true
p.applyFinamiDesign("Black Titanium")
let q = try JSONDecoder().decode(AppearancePreferences.self,from:JSONEncoder().encode(p))
check(q.hideAmounts==true && !q.designShowsUpcoming("amount") && q.designHiddenSubscriptions==["s1"] && q.designEditorConfirm==true && q.designCalendarListCollapsed==true && q.designSize(for:"report.categories")=="L" && q.designReportStyle("categories")=="financePro","new preferences persist and survive theme change")
check(FinamiDesignPolicy.fraction(40,100,masked:false)==0.4 && FinamiDesignPolicy.fraction(40,100,masked:true)==nil && FinamiDesignPolicy.fraction(40,0,masked:false)==nil,"progress privacy and zero total")
check(FinamiDesignPolicy.annualFactor("Тиждень")==52 && FinamiDesignPolicy.annualFactor("Місяць")==12 && FinamiDesignPolicy.annualFactor("Рік")==1,"annual subscription estimate periodicity")
check(FinamiDesignPolicy.safeMinor(Double.infinity)==0 && FinamiDesignPolicy.safeMinor(12.6)==13,"bounded display conversion")
check(FinamiDesignPolicy.calculate("10,25","2,75",operation:"+")=="13","decimal addition")
check(FinamiDesignPolicy.calculate("10","4",operation:"÷")=="2,5","decimal division")
check(FinamiDesignPolicy.calculate("10","0",operation:"÷")==nil && FinamiDesignPolicy.calculate("1","2",operation:"−")==nil,"reject zero divisor and negative result")
check(FinamiDesignPolicy.calculate("1.2.3","1",operation:"+")==nil,"reject malformed number")
SWIFT
swiftc -swift-version 5 -warnings-as-errors Finora/FinamiDesignPolicy.swift "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
