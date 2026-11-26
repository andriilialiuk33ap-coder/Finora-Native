#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ ok:@autoclosure ()->Bool,_ label:String) {precondition(ok(),label);print("PASS: " + label)}
var old=try JSONDecoder().decode(AppearancePreferences.self,from:Data(#"{"theme":"Gold","mode":"dark","font":"default","largeIcons":true,"glow":true,"hideAmounts":true}"#.utf8))
check(old.simpleHome != true,"old backup retains current dashboard")
old.simpleHome=true
let roundtrip=try JSONDecoder().decode(AppearancePreferences.self,from:JSONEncoder().encode(old))
check(roundtrip.simpleHome == true && roundtrip.hideAmounts == true,"alternate home persists without privacy changes")
old.applyFinamiDesign("Black Titanium")
check(old.simpleHome == true,"design preset does not override dashboard choice")
old.restoreFinamiStyle(["design":"Pure","layout":"list"])
check(old.simpleHome == true,"custom style restore does not override dashboard choice")
check(FinamiSearchPolicy.matches("ЗВІРКА БАЛАНС",text:"звірка рахунку баланс"),"search multiple tokens, case independent")
check(!FinamiSearchPolicy.matches("категорії баланс",text:"категорії витрат"),"unmatched token excluded")
check(FinamiSearchPolicy.matches("здоров'я",text:"Здоров’я"),"apostrophe normalization")
check(FinamiSearchPolicy.matches("",text:"Категорії"),"empty query supported")
check(FinamiSearchPolicy.categoryName("🛒 Продукти",icon:"🍎") == "🍎 Продукти","replace existing category icon")
check(FinamiSearchPolicy.categoryName("Спорт",icon:"💪") == "💪 Спорт","add icon to plain title")
check(FinamiSearchPolicy.categoryName("",icon:"💪") == "💪","empty draft accepts icon")
check(FinamiDashboardPreviewPolicy.payments(count:0,nextAmount:nil,nextDate:nil,overdue:false,masked:false) == "Немає активних платежів","empty collapsed payment preview")
check(FinamiDashboardPreviewPolicy.payments(count:2,nextAmount:"100 ₴",nextDate:"7 груд.",overdue:false,masked:false) == "Активні: 2 · Наступний: 7 груд. · 100 ₴","collapsed preview uses next amount rather than total")
check(FinamiDashboardPreviewPolicy.payments(count:2,nextAmount:"100 ₴",nextDate:"7 груд.",overdue:true,masked:false).contains("Прострочено:"),"overdue preview is not labelled as future")
check(FinamiDashboardPreviewPolicy.payments(count:2,nextAmount:"100 ₴",nextDate:"7 груд.",overdue:false,masked:true) == "Суми приховано","collapsed payment privacy")
check(FinamiDashboardPreviewPolicy.payments(count:2,nextAmount:nil,nextDate:nil,overdue:false,masked:false) == "Активні: 2","disabled amount and date remain hidden")
check(FinamiDashboardPreviewPolicy.accounts(count:0,masked:false) == "Немає видимих рахунків","empty collapsed accounts")
check(FinamiDashboardPreviewPolicy.accounts(count:4,masked:true) == "Суми приховано","collapsed accounts privacy")
var design3 = old
check(design3.designStyle(for:"accounts")==nil && design3.designSize(for:"accounts")=="M","Design 3 legacy defaults")
design3.setDesignStyle("bankingSplit",for:"accounts")
design3.setDesignAccountStyle("creditRing",for:"credit-id")
design3.setDesignSize("L",for:"accounts")
design3.toggleDesignCard("same-id",subscription:false)
check(design3.isDesignCardCollapsed("same-id",subscription:false) && !design3.isDesignCardCollapsed("same-id",subscription:true),"independent collapsed cards")
design3.setDesignStyle("invalid",for:"accounts")
design3.setDesignStyle("other",for:"navigation")
design3.setDesignSize("XXL",for:"accounts")
check(design3.designStyle(for:"accounts")=="bankingSplit" && design3.designSize(for:"accounts")=="L" && design3.componentStyles?["navigation"]==nil,"invalid styles rejected, fixed navigation")
check(design3.designAccountStyle(for:"credit-id")=="creditRing" && design3.designAccountStyle(for:"other")=="bankingSplit","individual account override and fallback")
design3.applyFinamiDesign("Digital Bank")
design3.restoreFinamiStyle(["design":"Dark Classic"])
check(design3.designStyle(for:"accounts")=="bankingSplit" && design3.designAccountStyle(for:"credit-id")=="creditRing" && design3.hideAmounts==true,"theme and legacy preset preserve independent styles and privacy")
var persisted = try JSONDecoder().decode(AppearancePreferences.self,from:JSONEncoder().encode(design3))
check(persisted.designSize(for:"accounts")=="L" && persisted.isDesignCardCollapsed("same-id",subscription:false),"Design 3 persistence roundtrip")
persisted.toggleDesignCard("same-id",subscription:false)
check(!persisted.isDesignCardCollapsed("same-id",subscription:false),"individual expand persists")
check(FinamiDesignPolicy.componentOptions["operations"]?.count == 4, "four operation styles registered")
for key in FinamiDesignPolicy.componentOptions["operations"] ?? [] {
    persisted.setDesignStyle(key, for: "operations")
    let decoded = try JSONDecoder().decode(AppearancePreferences.self, from: JSONEncoder().encode(persisted))
    check(decoded.designStyle(for: "operations") == key && decoded.designAccountStyle(for: "credit-id") == "creditRing", "independent operation style: " + key)
}
check(FinamiDesignPolicy.creditFraction(used: 25, limit: 100, masked: false) == 0.25, "credit fraction uses limit")
check(FinamiDesignPolicy.creditFraction(used: 200, limit: 100, masked: false) == 1, "credit overflow clamped")
check(FinamiDesignPolicy.creditFraction(used: -5, limit: 100, masked: false) == 0, "negative fraction clamped")
check(FinamiDesignPolicy.creditFraction(used: 25, limit: 100, masked: true) == nil, "masked credit graph suppressed")
check(FinamiDesignPolicy.creditFraction(used: 25, limit: 0, masked: false) == nil, "zero limit graph suppressed")
persisted.setDesignAccountStyle(nil, for: "credit-id")
check(persisted.designAccountStyle(for: "credit-id") == "bankingSplit", "reset returns to general account style")
SWIFT
swiftc -swift-version 5 -warnings-as-errors Finora/FinamiDesignPolicy.swift Finora/FinamiSimplicityCore.swift "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
