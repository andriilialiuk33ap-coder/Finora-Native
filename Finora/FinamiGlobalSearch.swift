import SwiftUI

struct FinamiGlobalSearch: View {
    @EnvironmentObject private var s: Store
    @State private var query = ""
    @State private var settledQuery = ""
    @State private var operation: Operation?
    @State private var account: Account?
    @State private var payment: FinamiPayment?
    private var term: String { query.trimmingCharacters(in:.whitespacesAndNewlines) }
    private func matches(_ text:String)->Bool { FinamiSearchPolicy.matches(term, text: text) }
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Рахунок, продавець, функція", text: $query).accessibilityIdentifier("qa.search.field")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).accessibilityLabel("Очистити пошук") }
                }.frame(minHeight: 44)
            }
            Section("Функції та налаштування") {
                if matches("категорії категорія витрати доходи іконки categories category") { NavigationLink("Категорії витрат та доходів"){Categories()}.accessibilityIdentifier("qa.search.categories") }
                if matches("звірка звірити баланс залишок кредит використано reconcile balance") { NavigationLink("Звірити баланс рахунку"){FinamiBalanceView(initialMode:"anchor")}.accessibilityIdentifier("qa.search.reconcile") }
                if matches("автоматизація apple pay sms банківські повідомлення") { NavigationLink("Автоматизація"){AutomationCenter()} }
                if matches("головна огляд блоки dashboard") { NavigationLink("Блоки головної"){DashboardSettings()} }
                if matches("usdt біржа зарплата комісія") { NavigationLink("Журнал USDT"){FinamiExchangeDiaryView()} }
                if matches("підсумки аналітика місяць") { NavigationLink("Фінансові підсумки"){FinamiNextInsightsView()} }
                if matches("дублікат перевірка ціна підписки") { NavigationLink("Центр перевірки операцій"){FinamiNextReviewView()} }
                if matches("планування прогноз бюджет зарплата") { NavigationLink("Розумне планування"){FinamiPlanningView()} }
                if matches("кредит борг розстрочки ліміт") { NavigationLink("Кредитний центр"){FinamiCreditCenter()} }
                if matches("календар платежі нагадування") { NavigationLink("Календар платежів"){CalendarView()} }
                if matches("конверти бюджет категорії ліміти") { NavigationLink("Віртуальні конверти"){FinamiEnvelopesView()} }
                if matches("імпорт експорт виписка банк аудит звірка") { NavigationLink("Імпорт, експорт та перевірка"){FinamiImportHub()} }
                if matches("підписки регулярні платежі") { NavigationLink("Підписки"){SubscriptionsView()} }
                if matches("дизайн стилі тема іконки") { NavigationLink("Finami Design"){AppearanceView()} }
                if matches("захист резервна копія face id налаштування") { NavigationLink("Захист та резервні копії"){Settings()} }
                if matches("діагностика версія збірка") { NavigationLink("Діагностика Finami"){FinamiDiagnostics()} }
            }
            if !term.isEmpty {
                Section("Рахунки") {
                    ForEach(s.db.accounts.filter{matches($0.name) || matches($0.bankName ?? "")}) { a in
                        Button {account=a} label:{Label(a.name,systemImage:"creditcard")}.buttonStyle(.plain)
                    }
                }
                Section("Найближчі платежі") {
                    ForEach(s.upcomingPayments.filter{matches($0.name) || matches($0.kind)}) { p in
                        Button {payment=p} label:{VStack(alignment:.leading){Text(p.name);Text(p.date.formatted(.dateTime.day().month(.wide))).font(.caption).foregroundStyle(.secondary)}}.buttonStyle(.plain)
                    }
                }
                Section("Операції") {
                    if settledQuery != term { ProgressView("Пошук…") } else {
                    let rows=s.queryHistory(.init(kind:"all",account:"all",category:"all",search:term,sort:.newest,hideAmounts:s.privateAmounts))
                    if rows.isEmpty {Text("Немає відповідних операцій").foregroundStyle(.secondary)}
                    ForEach(Array(rows.prefix(60))) { o in
                        Button {operation=o} label: {OperationRow(o:o).environment(\.finamiMask,s.db.accounts.first(where:{$0.id==o.account})?.hideAmounts == true)}.buttonStyle(.plain)
                    }
                    if rows.count>60 {Text("Показано 60 із \(rows.count). Уточни запит або відкрий журнал операцій.").font(.caption)}
                    }
                }
            } else { Text("Шукай назви рахунків, продавців, платежів та функцій. Суми можна шукати, якщо вони не приховані.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Пошук Finami")
         .task(id: term) {
             let value = term
             if value.isEmpty { settledQuery = ""; return }
             do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
             guard !Task.isCancelled, value == term else { return }
             settledQuery = value
         }
         .sheet(item:$operation){OpEditor(original:$0)}
         .sheet(item:$account){AccountEditor(a:$0)}
         .sheet(item:$payment){FinamiPaymentDetails(payment:$0)}
    }
}
