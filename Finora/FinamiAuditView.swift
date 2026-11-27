import SwiftUI

struct FinamiAuditView: View {
    @EnvironmentObject private var s: Store
    @State private var operation: Operation?
    @State private var confirmIncome = false
    @State private var selectedPair: FinamiAuditIssue?
    @State private var oldPayment: FinamiPaidRecord?
    private var issues:[FinamiAuditIssue] { finamiAuditIssues(operations:s.db.operations,accounts:s.db.accounts,records:s.db.paidRecords ?? []) }
    private var incomes:[Operation] { s.db.operations.filter { o in o.kind == .unclassifiedCredit && bankKind(signed:o.amount,note:o.note,mcc:o.bankMCC,operationType:o.bankType,creditAccount:s.db.accounts.first(where:{$0.id==o.account})?.isCredit ?? false) == "income" } }
    var body: some View {
        let currentIssues = issues
        let reviewIDs = s.db.operations.filter { $0.requiresReview }.map(\.id)
        List {
            Section("Стан бази") {
                LabeledContent("Операцій",value:String(s.db.operations.count))
                NavigationLink { FinamiReportReviewList(ids: reviewIDs, account: nil, maskAmounts: s.privateAmounts) } label: {
                    LabeledContent("Потребують уточнення типу", value: String(reviewIDs.count))
                }
                LabeledContent("Можливі суперечності",value:String(currentIssues.count))
                NavigationLink("Схожі операції та дублікати") { FinamiNextReviewView() }
                NavigationLink("Резервні копії та стан сховища") { FinamiDiagnostics() }
                NavigationLink("Зашифрована резервна копія") { FinamiSecureBackupView() }
                NavigationLink("Розумна звірка та валютний обмін") { FinamiBalanceView() }
                NavigationLink("Звірка з банківським залишком") { FinamiReconciliation() }
                NavigationLink("Категорії та правила") { FinamiRulesView() }
                Text("Перевірка не змінює суми, рахунки або історію без підтвердження.").font(.caption)
            }
            Section("Потребують перевірки") {
                if currentIssues.isEmpty {Text("Суперечностей за цими правилами не знайдено")}
                ForEach(currentIssues) { issue in issueRow(issue) }
            }
            if !incomes.isEmpty { incomeSection }
            Section("Можливі старі оплати") { ForEach(s.db.obligations.filter{$0.kind == .installment}) { o in historicalRow(o) } }
        }.navigationTitle("Якість фінансових даних").sheet(item:$operation){OpEditor(original:$0)}
        .confirmationDialog("Підтвердити, що всі запропоновані зарахування є доходами?",isPresented:$confirmIncome){Button("Підтвердити"){applyIncome()}}
        .confirmationDialog("Об’єднати два підтверджені записи переказу? Баланси залишаться незмінними.",isPresented:Binding(get:{selectedPair != nil},set:{if !$0 {selectedPair=nil}})){Button("Об’єднати переказ"){mergePair()}}
        .confirmationDialog("Підтвердити, що ця оплата ВЖЕ врахована в поточному залишку розстрочки? Сума боргу, дата й баланс рахунку не зміняться.",isPresented:Binding(get:{oldPayment != nil},set:{if !$0 {oldPayment=nil}})){Button("Додати лише до історії"){linkHistorical()}}
    }
    private func auditAmount(_ operation: Operation) -> String {
        let hidden = s.db.accounts.contains { account in
            account.hideAmounts == true && (account.id == operation.account || (operation.kind == .transfer && account.id == operation.destination))
        }
        return hidden ? "••••" : s.visibleMoney(operation.amount)
    }
    private func issueOperations(_ issue:FinamiAuditIssue)->[Operation] { s.db.operations.filter{issue.operationIDs.contains($0.id)} }
    private func transfer(_ issue:FinamiAuditIssue)->Operation? { let rows=issueOperations(issue);guard rows.count==2 else{return nil};return finamiTransferFromPair(rows[0],rows[1],accounts:s.db.accounts,records:s.db.paidRecords ?? []) }
    private func issueRow(_ issue:FinamiAuditIssue)->some View {
        VStack(alignment:.leading,spacing:8) {
            Text(issue.title).bold();Text(issue.detail).font(.caption)
            ForEach(issueOperations(issue)) { o in Button {operation=o} label:{VStack(alignment:.leading){Text(o.displayKindTitle+" · "+s.accountName(o.account));Text(auditAmount(o)).font(.caption)}}.buttonStyle(.borderless) }
            if transfer(issue) != nil { Button("Підтвердити внутрішній переказ"){selectedPair=issue}.buttonStyle(.borderless) }
        }
    }
    private var incomeSection:some View { Section("Можливі доходи") {
        Text("Явні ознаки зарплати, винагороди або кешбеку. Зміна типу не змінює залишок рахунку.").font(.caption)
        ForEach(incomes){o in Button {operation=o} label:{VStack(alignment:.leading){Text(o.note);Text(auditAmount(o)).font(.caption)}}}
        Button("Підтвердити всі як доходи"){confirmIncome=true}
    } }
    @ViewBuilder private func historicalRow(_ obligation:Obligation)->some View {
        let candidates=s.db.operations.filter{ o in finamiContractMatches(obligation:obligation,operation:o) && finamiHistoricalPaymentRecord(obligation:obligation,operation:o,accounts:s.db.accounts,records:s.db.paidRecords ?? []) != nil }
        if !candidates.isEmpty { DisclosureGroup(obligation.name) {
            Text("Збіг суми або маски договору не доводить оплату. Якщо вона вже врахована в залишку, додай тільки до історії. Якщо ще не врахована, відкрий операцію та зв’яжи її з поточним платежем.").font(.caption)
            ForEach(candidates.prefix(20)) { o in
                VStack(alignment:.leading,spacing:6) {
                    Text(s.accountName(o.account)+" · "+o.date.formatted(date:.abbreviated,time:.omitted));Text(auditAmount(o)).font(.caption)
                    Button("Вже враховано в залишку"){oldPayment=finamiHistoricalPaymentRecord(obligation:obligation,operation:o,accounts:s.db.accounts,records:s.db.paidRecords ?? [])}.buttonStyle(.borderless)
                    Button("Відкрити операцію"){operation=o}.buttonStyle(.borderless)
                }
            }
        } }
    }
    private func applyIncome() {let ids=Set(incomes.map(\.id));s.change{d in for i in d.operations.indices where ids.contains(d.operations[i].id) { let category=suggestedCategory(d.operations[i].note,kind:.income,database:d);d.operations[i].kind = .income;d.operations[i].category=category;d.operations[i].classificationReviewed=true }}}
    private func mergePair(){guard let issue=selectedPair,let transfer=transfer(issue) else{return};let ids=Set(issue.operationIDs);s.change{d in d.operations.removeAll{ids.contains($0.id)};d.operations.append(transfer)};selectedPair=nil}
    private func linkHistorical(){guard let record=oldPayment,let op=s.db.operations.first(where:{$0.id==record.operationID}),let obligation=s.db.obligations.first(where:{$0.id==record.paymentID}),let fresh=finamiHistoricalPaymentRecord(obligation:obligation,operation:op,accounts:s.db.accounts,records:s.db.paidRecords ?? []) else{return};s.change{$0.paidRecords=($0.paidRecords ?? [])+[fresh]};oldPayment=nil}
}
struct FinamiRulesView: View {
    @EnvironmentObject private var s: Store
    @State private var selected: [String:String] = [:]
    @State private var merchant = ""
    @State private var chosen = "Без категорії"
    @State private var income = false
    @State private var confirm = false
    private var expense: [String] { s.db.expenseCategories.filter{!(s.db.hiddenExpenseCategories ?? []).contains($0)} }
    private var incomes: [String] { s.db.incomeCategories.filter{!(s.db.hiddenIncomeCategories ?? []).contains($0)} }
    private var groups: [FinamiCategoryGroup] { finamiCategoryGroups(operations:s.db.operations,expense:expense,income:incomes,learned:s.db.merchantRules ?? [:]) }
    var body: some View {
        List {
            Section("Словник") { Button("Додати погоджений набір категорій і правил") { install() }; Text("Додає категорії та правила продавців, не змінюючи старі операції. Невідомі Clover і KIOSK залишаються без автоматичної категорії.").font(.caption) }
            Section("Нове правило / заміна") { TextField("Назва продавця",text:$merchant);Toggle("Для доходів",isOn:$income);Picker("Категорія",selection:$chosen){Text("Обрати").tag("Без категорії");ForEach((income ? incomes:expense).filter{$0 != "Без категорії"},id:\.self){Text($0).tag($0)}};Button("Зберегти правило"){saveRule()}.disabled(finamiMerchantKey(merchant).isEmpty || !(income ? incomes:expense).contains(chosen) || chosen == "Без категорії") }
            Section("Без категорії · \(groups.reduce(0){$0+$1.ids.count})") { ForEach(groups) { group in VStack(alignment:.leading) {Text(group.merchant).bold();Text("\(group.ids.count) операцій").font(.caption);Picker("Категорія",selection:Binding(get:{selected[group.id] ?? group.suggestion},set:{selected[group.id]=$0})){Text("Залишити без категорії").tag("Без категорії");ForEach((group.kind == .income ? incomes:expense).filter{$0 != "Без категорії"},id:\.self){Text($0).tag($0)}} } };Button("Застосувати вибрані категорії") {confirm=true}.disabled(groups.isEmpty) }
            Section("Збережені правила") { ForEach((s.db.merchantRules ?? [:]).keys.sorted(),id:\.self){key in VStack(alignment:.leading){Text(key);Text(s.db.merchantRules?[key] ?? "").font(.caption)}.swipeActions{Button(role:.destructive){s.change{$0.merchantRules?.removeValue(forKey:key)}}label:{Label("Видалити",systemImage:"trash")}} } }
        }.navigationTitle("Правила категорій").confirmationDialog("Застосувати лише вибрані категорії? Суми не зміняться.",isPresented:$confirm){Button("Застосувати"){apply()}}
    }
    private func saveRule() {
        var rules = s.db.merchantRules ?? [:]
        let before = rules
        finamiRememberMerchant(merchant, kind: income ? .income : .expense, category: chosen, rules: &rules)
        guard rules != before else { s.error = "Правило вже існує або назва продавця надто загальна."; return }
        if s.change({ $0.merchantRules = rules }) { merchant = ""; chosen = "Без категорії" }
    }
    private func apply() { let proposals=groups.compactMap { group -> (FinamiCategoryGroup,String)? in let c=selected[group.id] ?? group.suggestion; return c != "Без категорії" && (group.kind == .income ? incomes:expense).contains(c) ? (group,c):nil }; if s.change({d in var rules=d.merchantRules ?? [:];var changes:[String:String]=[:];for (group,c) in proposals {let prefix=group.kind.rawValue+":";rules=rules.filter{!$0.key.hasPrefix(prefix) || prefix+finamiMerchantKey(String($0.key.dropFirst(prefix.count))) != group.id};rules[group.id]=c;for id in group.ids {changes[id]=c}};for i in d.operations.indices {if let c=changes[d.operations[i].id] {d.operations[i].category=c}};d.merchantRules=rules}) {selected=[:]} }
    private func install() { s.change { d in
        let parent="🍺 Алкоголь", beer="Пиво", wine="Вино", spirits="Міцні напої", pets="🐾 Тварини", petShop="Зоомагазини", sweets="Солодощі", games="Азартні ігри"
        for c in [parent,beer,wine,spirits,petShop,sweets,games] where !d.expenseCategories.contains(c) {d.expenseCategories.append(c)}
        var parents=d.categoryParents ?? [:];for c in [beer,wine,spirits] {if parents[c]==nil {parents[c]=parent}};if d.expenseCategories.contains(pets),parents[petShop]==nil {parents[petShop]=pets};if d.expenseCategories.contains("🛒 Продукти"),parents[sweets]==nil{parents[sweets]="🛒 Продукти"};d.categoryParents=parents
        let additions=["baddi":petShop,"chill time":beer,"dlyasvoyih":beer,"nashe pivo":beer,"okrasa":"☕ Кава","roshen":sweets,"betking":games]
        var rules=d.merchantRules ?? [:];for (key,value) in additions where d.expenseCategories.contains(value) {let k="expense:"+finamiMerchantKey(key);if !rules.keys.contains(where:{$0.hasPrefix("expense:") && finamiMerchantKey(String($0.dropFirst(8)))==finamiMerchantKey(key)}) {rules[k]=value}};d.merchantRules=rules
    } }
}
