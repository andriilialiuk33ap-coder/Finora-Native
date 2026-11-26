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
SWIFT
swiftc -swift-version 5 -warnings-as-errors Finora/FinamiDesignPolicy.swift Finora/FinamiSimplicityCore.swift "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
