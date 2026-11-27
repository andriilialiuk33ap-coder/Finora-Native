#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; echo 'let expenseDefaults=["Без категорії", "Інше"]; let incomeDefaults=["Без категорії", "Інше"]'; sed -n '/^enum Kind:/,/^struct Legacy:/p' Finora/Finora.swift | sed '$d'; sed -n '/^struct AppearancePreferences:/,/^struct IzanamiTheme:/p' Finora/IzanamiFeatures.swift | sed '$d'; cat <<'SWIFT'
struct DashboardItem: Codable { var categorySelection: [String]? = nil }
struct SubscriptionRecord: Codable {}
struct PersonalReminder: Codable { var id = UUID().uuidString; var linkedID: String? = nil }
struct ForecastPreferences: Codable {}
struct CapturePreferences: Codable {}
SWIFT
} > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS: " + label) }
let date = Date().addingTimeInterval(-60)
let a = Account(id:"a",name:"Bank",opening:100000)
let b = Account(id:"b",name:"Other",opening:0)
let neutral = Operation(id:"n",kind:.receipt,amount:20000,date:date,category:"🤝 Повернення боргу",account:a.id,bankKey:"n-key",receiptTreatment:.neutral)
let gift = Operation(id:"g",kind:.receipt,amount:30000,date:date,category:"🎁 Подарунок",account:a.id,receiptTreatment:.income)
let pending = Operation(id:"p",kind:.receipt,amount:40000,date:date,category:"👤 Переказ від іншої людини",account:a.id)
let salary = Operation(id:"s",kind:.income,amount:50000,date:date,category:"💼 Зарплата",account:a.id)
let spend = Operation(id:"e",kind:.expense,amount:10000,date:date,category:"Food",account:a.id)
let transfer = Operation(id:"t",kind:.transfer,amount:7000,date:date,account:a.id,destination:b.id)
let old = [salary,spend,transfer]
let ops = old + [neutral,gift,pending]
let t = FinamiReportSnapshot(operations:ops,date:date,annual:false,account:nil).totals
check(t.income == 80000 && t.expense == 10000 && t.net == 70000,"only explicitly included receipts are income")
check(t.receipts == 90000 && t.neutralReceipts == 60000 && t.incoming == 147000,"gross incoming counts each receipt once")
check(t.transfersIn == 7000 && t.transfersOut == 7000,"own transfers remain separate")
check(t.review == 1 && pending.requiresReview && !neutral.requiresReview && !gift.requiresReview,"pending receipt appears in attention")
check(FinamiLedgerIndex(operations:ops).balance(a) == 223000 && FinamiLedgerIndex(operations:ops).balance(b) == 7000,"actual balances include all receipts once")
check(FinamiDashboardMetrics(operations:ops).income == t.income,"dashboard matches reports")
check(AccountActivity(account:a,operations:ops,month:date).income == t.income,"account income matches reports")
check(FinamiMonthInsight(month:date).income == 0,"insight model default")
check(finamiMonthInsights(ops,ending:Date(),months:1).first?.income == t.income,"monthly insights match reports")
check(FinamiOperationChoice.options(bankIncoming:true,current:.reviewCredit).contains(.receipt) && !FinamiOperationChoice.options(bankIncoming:false,current:.expense).contains(.receipt),"receipt offered only for incoming or manual")
check(FinamiReceiptTreatment.suggestion("🤝 Повернення боргу") == .neutral && FinamiReceiptTreatment.suggestion("🎁 Подарунок") == .income && FinamiReceiptTreatment.suggestion("💵 Отримані позикові кошти") == .pending,"conservative accounting suggestions")
let legacyJSON = try JSONEncoder().encode(salary)
let decoded = try JSONDecoder().decode(Operation.self,from:legacyJSON)
check(decoded == salary && decoded.receiptTreatment == nil && decoded.incomeValue == salary.amount,"old JSON works without new field")
let roundtrip = try JSONDecoder().decode([Operation].self,from:JSONEncoder().encode(ops))
check(roundtrip == ops,"new records survive JSON roundtrip")
var db = Database(); db.accounts = [a,b]; db.operations = ops; db.expenseCategories = ["Food","Other","Без категорії"]; db.incomeCategories = ["💼 Зарплата","🎁 Подарунок","Без категорії"]
var rules: [String:String] = [:]
finamiRememberMerchant("Переказ коштів",kind:.receipt,category:neutral.category,rules:&rules)
check(rules.isEmpty,"generic bank labels never learned as sender")
finamiRememberMerchant("Іван Іваненко",kind:.receipt,category:neutral.category,rules:&rules)
check(finamiIntelligentCategory("ІВАН ІВАНЕНКО",kind:.receipt,allowed:db.availableReceiptCategories,learned:rules)==neutral.category,"explicit receipt category learning")
check(finamiIntelligentCategory("ІВАН ІВАНЕНКО",kind:.income,allowed:db.incomeCategories,learned:rules)=="Без категорії","receipt rules never classify salary")
db.merchantRules = rules
check(FinamiCategoryCore.editReceipt(&db,old:neutral.category,new:"Повернення позичених коштів"),"receipt rename succeeds")
check(db.operations.first{$0.id==neutral.id}?.category == "Повернення позичених коштів" && db.merchantRules?.values.contains("Повернення позичених коштів") == true,"receipt category and rule synchronized")
check(db.operations.map(\.signedNative)==ops.map(\.signedNative) && db.operations.map(\.incomeValue)==ops.map(\.incomeValue),"rename does not change accounting")
check(FinamiCategoryCore.categoryAfterTypeChange("Food",from:.expense,to:.receipt,database:db,note:"unknown") == "Без категорії","incompatible category cleared")
let unknown = Operation(id:"u",kind:.unclassifiedCredit,amount:700,date:date,account:a.id,bankKey:"u-key")
db.operations.append(unknown)
let plan = FinamiCategoryBatch.plan(in:db,ids:["u"],kind:.unclassifiedCredit,category:"👤 Переказ від іншої людини",treatment:.neutral)!
let applied = plan.applying(to:db.operations)!
check(applied.last?.kind == .receipt && applied.last?.receiptTreatment == .neutral && applied.last?.bankKey == "u-key","batch converts explicitly selected inflow, preserves identity")
check(applied.map(\.signedNative)==db.operations.map(\.signedNative),"batch preserves balances")
check(plan.applying(to:applied,undo:true)==db.operations,"batch undo restores exact rows")
var changed = applied; changed[changed.count-1].note="edited"
check(plan.applying(to:changed,undo:true)==nil,"undo refuses newer edit")
let added = Operation(kind:.expense,amount:100,account:a.id)
check(plan.applying(to:applied+[added],undo:true)==db.operations+[added],"undo preserves unrelated imports")
check(FinamiCategoryBatch.plan(in:db,ids:["u","e"],kind:.unclassifiedCredit,category:"👤 Переказ від іншої людини")==nil,"mixed direction batch rejected")
check(FinamiCategoryBatch.plan(in:db,ids:["e"],kind:.expense,category:"invalid")==nil,"invalid category rejected")
db.paidRecords = [FinamiPaidRecord(paymentID:"sub",scheduledDate:date,paidDate:date,amount:spend.amount,currency:"UAH",accountID:a.id,operationID:spend.id)]
check(FinamiCategoryBatch.plan(in:db,ids:["e"],kind:.expense,category:"Other")==nil,"linked payments protected")
let fresh = FinamiReportSnapshot(operations:applied,date:date,annual:false,account:nil)
check(fresh.totals.income==t.income,"neutral bulk classification does not become income")
var comp = Operation(id:"comp",kind:.receipt,amount:3000,date:date,category:"🍽️ Компенсація витрат",account:b.id,refundOriginalID:spend.id,receiptTreatment:.reimbursement)
var reimburse = [spend,comp]
check(finamiSynchronizeRefundLinks(&reimburse),"cross-account UAH compensation can be linked")
check(reimburse[1].expenseGroup == spend.category && reimburse[1].category == comp.category && reimburse[1].expenseValue == -3000,"compensation keeps receipt category and reduces original category")
let ct = FinamiReportSnapshot(operations:reimburse,date:date,annual:false,account:nil).totals
check(ct.income == 0 && ct.expense == 7000 && ct.incoming == 3000,"compensation reduces expense and counts gross once")
check(FinamiLedgerIndex(operations:reimburse).balance(a)==90000 && FinamiLedgerIndex(operations:reimburse).balance(b)==3000,"compensation does not create additional debit")
var refunded = Operation(kind:.refund,amount:8000,date:date,account:a.id,refundOriginalID:spend.id)
var excessive = reimburse + [refunded]
check(!finamiSynchronizeRefundLinks(&excessive),"combined refund and compensation cannot exceed original")
check(finamiCompensationChoices(comp,operations:[spend,refunded],accounts:[a,b]).isEmpty,"overcompensated original is excluded")
comp.refundOriginalID=nil
var missing = [spend,comp]
check(!finamiSynchronizeRefundLinks(&missing),"unlinked compensation rejected")
var foreign = reimburse; foreign[1].entryCurrency="USD"
check(!finamiSynchronizeRefundLinks(&foreign),"cross-currency compensation rejected")
reimburse[0].category="Renamed"
check(finamiSynchronizeRefundLinks(&reimburse) && reimburse[1].expenseGroup=="Renamed","compensation follows original category rename")
SWIFT
swiftc -O -warnings-as-errors "$tmp/Models.swift" Finora/BankCore.swift Finora/MoneyCore.swift Finora/FinamiScanCore.swift Finora/AutomationCore.swift Finora/FinamiCategoryCore.swift Finora/FinamiIntelligenceCore.swift Finora/FinamiPaymentCore.swift Finora/FinamiQualityCore.swift Finora/FinamiReportCore.swift Finora/FinamiNextCore.swift Finora/FinamiBalanceCore.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
