#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let old = Data(#"{"id":"a","name":"Old","opening":10000}"#.utf8)
var a = try JSONDecoder().decode(Account.self, from: old)
precondition(a.cardOptions == nil && a.opening == 10000)
var b = Account(id:"b", name:"Second", currency:"USD")
var c = Account(id:"c", name:"Third")
a.cardOptions = AccountCardOptions(style:"premium",right:"photo",fields:["own","expenses"],photo:Data([1,2,3]),pinned:true,order:5,accent:"Ocean")
b.cardOptions = AccountCardOptions(order:1)
c.cardOptions = AccountCardOptions(order:0)
let copy = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(a))
precondition(copy.cardOptions?.photo == Data([1,2,3]) && copy.cardOptions?.fields == ["own","expenses"] && copy.cardOptions?.right == "photo" && copy.opening == 10000)
precondition(finamiOrderedAccounts([b,c,a]).map(\.id) == ["a","c","b"])
let oldPrefs = Data(#"{"theme":"Crimson","mode":"system","font":"default","largeIcons":true,"glow":true,"homeAccountLayout":"cards"}"#.utf8)
var prefs = try JSONDecoder().decode(AppearancePreferences.self, from: oldPrefs)
precondition(prefs.homeAccountRight == nil && prefs.homeAccountFields == nil && prefs.homeAccountLayout == "cards")
prefs.homeAccountRight = "actions"; prefs.homeAccountFields = ["own"]
let restored = try JSONDecoder().decode(AppearancePreferences.self, from: JSONEncoder().encode(prefs))
precondition(restored.homeAccountRight == "actions" && restored.homeAccountFields == ["own"])
var cal = Calendar(identifier:.gregorian); cal.timeZone = TimeZone(secondsFromGMT:0)!
let now = cal.date(from:DateComponents(year:2026,month:11,day:25))!
let past = cal.date(byAdding:.month,value:-1,to:now)!
let ops = [
    Operation(id:"expense",kind:.expense,amount:4200,date:now,account:"a"),
    Operation(id:"refund",kind:.refund,amount:1000,date:now,account:"a"),
    Operation(id:"income",kind:.income,amount:15000,date:now,account:"a"),
    Operation(id:"transfer",kind:.transfer,amount:4000,date:now,account:"a",destination:"b",sourceMinor:4000,destinationMinor:100),
    Operation(id:"usd",kind:.expense,amount:4200,date:now,account:"b",sourceMinor:100),
    Operation(id:"repay",kind:.creditRepayment,amount:2000,date:now,account:"a"),
    Operation(id:"old",kind:.expense,amount:9000,date:past,account:"a"),
    Operation(id:"foreign",kind:.income,amount:100000,date:now,account:"c")
]
let activity = AccountActivity(account:a,operations:ops,month:now,calendar:cal)
precondition(activity.spending == 3200 && activity.income == 15000 && activity.count == 5 && activity.history.count == 6)
let dollars = AccountActivity(account:b,operations:ops,month:now,calendar:cal)
precondition(dollars.spending == 100 && dollars.income == 0 && dollars.count == 2)
let transfer = ops.first{$0.id == "transfer"}!
precondition(activity.signed(transfer) == -4000 && dollars.signed(transfer) == 100)
precondition(AccountActivity(account: c,operations:[],month:now,calendar:cal).count == 0)
print("PASS: Preview 3 account appearance/legacy persistence, pin/order, currency-aware monthly activity, refunds, transfers and period filtering")
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/preview3-tests"
"$tmp/preview3-tests"
