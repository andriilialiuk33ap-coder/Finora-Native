#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift Finora/Domain/PaymentModels.swift Finora/Domain/FinancialRecords.swift Finora/Domain/Database.swift; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; cat <<'SWIFT'
struct DashboardItem: Codable { var categorySelection: [String]? = nil }
struct SubscriptionRecord: Codable {}
struct PersonalReminder: Codable { var id = UUID().uuidString; var linkedID: String? = nil }
struct ForecastPreferences: Codable {}
struct CapturePreferences: Codable {}
SWIFT
} > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(),label); print("PASS: " + label) }
let date = Date().addingTimeInterval(-60)
var db = Database()
db.expenseCategories = ["Інше", "Food", "Child", "Other"]
db.incomeCategories = ["Інше", "Food"]
db.operations = [Operation(id:"debit",kind:.expense,amount:1000,date:date,category:"Food",account:cash), Operation(id:"refund",kind:.refund,amount:200,date:date,category:"Food",account:cash), Operation(id:"income",kind:.income,amount:2000,date:date,category:"Food",account:cash)]
db.limits = ["Food":10000,"Other":5000]
db.categoryParents = ["Food":"Group","Child":"Food"]
db.hiddenExpenseCategories = ["Food"]
db.merchantRules = ["expense:shop":"Food","income:company":"Food"]
db.dashboard = [.init(categorySelection:["Food","Other"])]
var prefs = AppearancePreferences(); prefs.designEditorFavorites = ["Food","Other"]; db.preferences = prefs
let old = db.operations
check(FinamiCategoryCore.edit(&db,income:false,old:"Food",new:"Groceries",parent:"Household"),"rename category in one candidate")
check(db.expenseCategories == ["Інше","Groceries","Child","Other"],"category order stays stable")
check(db.operations.map(\.category) == ["Groceries","Groceries","Food"],"rename affects only expense and refund group")
check(db.operations.map(\.signedNative) == old.map(\.signedNative) && db.operations.map(\.expenseValue) == old.map(\.expenseValue),"balances and report totals unchanged")
check(db.limits["Food"] == nil && db.limits["Groceries"] == 10000,"budget follows rename")
check(db.categoryParents == ["Groceries":"Household","Child":"Groceries"],"parent and child references updated")
check(db.merchantRules == ["expense:shop":"Groceries","income:company":"Food"],"learned rules stay scoped")
check(db.hiddenExpenseCategories == ["Groceries"] && db.dashboard?.first?.categorySelection == ["Groceries","Other"],"visibility and dashboard filters follow rename")
check(Set(db.preferences?.designEditorFavorites ?? []) == Set(["Food","Groceries","Other"]),"shared income favorite retained")
check(FinamiCategoryCore.edit(&db,income:false,old:"Groceries",new:"Other",merge:true),"merge categories")
check(db.limits == ["Other":15000] && db.dashboard?.first?.categorySelection == ["Other"],"merge adds budgets and deduplicates dashboard references")
check(db.hiddenExpenseCategories?.isEmpty == true && db.categoryParents?["Child"] == "Other", "target visibility preserved and child moved")
check(db.operations.map(\.category) == ["Other","Other","Food"] && db.merchantRules?["expense:shop"] == "Other", "merge references consistent")
let data = try JSONEncoder().encode(db)
let decoded = try JSONDecoder().decode(Database.self,from:data)
check(decoded.operations == db.operations && decoded.limits == db.limits,"JSON roundtrip retains category changes")
check(!FinamiCategoryCore.edit(&db,income:false,old:"Інше",new:"Other",merge:true),"protected fallback cannot be removed")
check(!FinamiCategoryCore.edit(&db,income:false,old:"Other",new:"Child"),"duplicate name rejected")
db.limits = ["Other":Int64.max,"Child":1]
check(!FinamiCategoryCore.edit(&db,income:false,old:"Other",new:"Child",merge:true) && db.limits["Other"] == Int64.max,"overflow fails before mutation")
check(FinamiCategoryCore.categoryAfterTypeChange("Other",from:.expense,to:.refund,database:db,note:"") == "Other","refund keeps compatible expense category")
check(FinamiCategoryCore.categoryAfterTypeChange("Other",from:.expense,to:.income,database:db,note:"company") == "Food","type change uses only learned income category")
check(FinamiCategoryCore.categoryAfterTypeChange("Food",from:.income,to:.movementIn,database:db,note:"") == "Без категорії","neutral transfer drops report category")
check(FinamiCategoryCore.categoryAfterTypeChange("Food",from:.income,to:.expense,database:db,note:"unknown") == "Без категорії","incompatible category reset")
var rows: [Operation] = []
rows.reserveCapacity(100000)
for i in 0..<100000 {
    let kind: Kind = i % 4 == 0 ? .income : .expense
    let amount = Int64((i % 997 + 1) * 100)
    let stamp = date.addingTimeInterval(-Double(i))
    let account = i % 3 == 0 ? "a" : "b"
    rows.append(Operation(id:String(i),kind:kind,amount:amount,date:stamp,category:"Other",account:account))
}
let records = rows.filter { $0.kind == .expense && Int($0.id)! % 11 == 0 }.map { FinamiPaidRecord(paymentID:"sub",scheduledDate:$0.date,paidDate:$0.date,amount:$0.amount,currency:"UAH",accountID:$0.account,operationID:$0.id) }
let start = Date(); let index = FinamiPaymentLookup(operations:rows,records:records); let build = Date().timeIntervalSince(start)
var fast: [[String]] = []; var slow: [[String]] = []
let queries = (1...24).map { Int64($0 * 100) }
let fastStart = Date()
for amount in queries { for used in [false,true] { fast.append(index.matches(account:"b",currency:"UAH",amount:amount,date:date,used:used).map(\.id)) } }
let fastTime = Date().timeIntervalSince(fastStart)
let slowStart = Date()
for amount in queries { slow.append(finamiEligiblePaymentOperations(rows,records:records,account:"b",currency:"UAH",amount:amount,date:date).map(\.id)); slow.append(finamiUsedPaymentOperations(rows,records:records,account:"b",currency:"UAH",amount:amount,date:date).map(\.id)) }
let slowTime = Date().timeIntervalSince(slowStart)
check(fast == slow,"100k payment index matches all 48 legacy queries exactly")
check(index.record(for:records[0].operationID!)?.id == records[0].id,"linked operation lookup")
check(index.recent(paymentID:"sub",currency:"UAH",amount:records[0].amount,date:date).map(\.id) == finamiRecentSubscriptionPayments(records,paymentID:"sub",currency:"UAH",amount:records[0].amount,date:date).map(\.id),"recent payment index equals original history")
let distant = Operation(id:"older",kind:.expense,amount:100,date:date.addingTimeInterval(-20*86400),account:"b")
let wideIndex = FinamiPaymentLookup(operations:[distant],records:[])
check(wideIndex.matches(account:"b",currency:"UAH",amount:100,date:date,used:false).isEmpty,"default search stays within 7 days")
check(wideIndex.matches(account:"b",currency:"UAH",amount:100,date:date,used:false,searchDays:30).map(\.id) == ["older"],"explicit 30 day search locates earlier debit")
let linked = FinamiPaidRecord(paymentID:"sub",scheduledDate:date,paidDate:distant.date,amount:100,currency:"UAH",accountID:"b",operationID:distant.id)
let linkedIndex = FinamiPaymentLookup(operations:[distant],records:[linked])
check(linkedIndex.matches(account:"b",currency:"UAH",amount:100,date:date,used:false,searchDays:90).isEmpty,"expanded search never offers linked debit again")
let metrics = FinamiDashboardMetrics(operations:rows)
check(metrics.income == rows.reduce(0){$0 + ($1.kind == .income ? $1.amount : 0)} && metrics.expense == rows.reduce(0){$0+$1.expenseValue},"100k financial overview equals reference sums")
print(String(format:"BENCH: 100,000 operations; index build %.2f ms; 48 indexed queries %.2f ms; reference %.2f ms (Linux)",build*1000,fastTime*1000,slowTime*1000))
SWIFT
swiftc -O -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiScanCore.swift Finora/AutomationCore.swift Finora/FinamiCategoryCore.swift Finora/FinamiIntelligenceCore.swift Finora/FinamiPaymentCore.swift Finora/FinamiQualityCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
