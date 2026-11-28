import SwiftUI
import UserNotifications

private struct FinamiDashboardRow: Identifiable { var items: [DashboardItem]; var id: String { items.first?.id ?? "empty" } }
struct CustomDashboard: View {
    @EnvironmentObject var s: Store
    @State private var date = Date()
    @State private var add = false
    @State private var quickDraft: Operation?
    @State private var configure = false
    @State private var reorder = false
    @State private var voice = false
    @State private var scan = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var items: [DashboardItem] {
        let enabled = DashboardItem.merged(s.db.dashboard).filter(\.enabled).map { item -> DashboardItem in
            guard s.db.preferences?.designDashboard == "analytics", [.categories,.cashflow,.forecast,.statistics].contains(item.kind) else { return item }
            var display=item;display.size = .large;return display
        }
        guard s.db.preferences?.hideEmptyDashboard == true else { return enabled }
        return enabled.filter { item in
            switch item.kind {
            case .accounts: return s.db.accounts.contains { $0.hiddenInOverview != true }
            case .budget: return s.db.budget > 0
            case .forecast: return s.db.forecast != nil
            case .goals: return s.db.obligations.contains { $0.kind == .goal && $0.remaining > 0 }
            case .reminders: return (s.db.reminders ?? []).contains { $0.enabled && $0.date > Date() }
            default: return true // never hide debts or ambiguous financial data
            }
        }
    }
    var rows: [[DashboardItem]] {
        var result: [[DashboardItem]] = []; var pair: [DashboardItem] = []
        for item in items {
            if s.db.preferences?.designDashboard != "premium" && !(s.db.preferences?.collapsedDashboard ?? []).contains(item.id) && item.size == .small && ![.balance,.ownFunds,.creditLimit,.creditPortfolio,.obligations,.allAvailable,.monthlyPayments,.accounts,.paymentCalendar].contains(item.kind) && !dynamicTypeSize.isAccessibilitySize { pair.append(item); if pair.count == 2 { result.append(pair); pair = [] } }
            else { if !pair.isEmpty { result.append(pair); pair = [] }; result.append([item]) }
        }
        if !pair.isEmpty { result.append(pair) }; return result
    }
    @ViewBuilder private var quickActions: some View {
        if s.db.preferences?.qualityQuickActions != false {
            FinamiDashboardQuickActions { kind in
                quickDraft = Operation(kind: kind, category: "Без категорії", account: s.db.accounts.first?.id ?? cash)
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            LazyVStack(spacing: (s.db.preferences ?? .init()).finamiSpacing) {
                MonthControl(date: $date, dashboardStyle: true)
                if !items.contains(where: { $0.kind == .review }) {
                    NavigationLink { FinamiReportReviewList(ids: [], account: nil, maskAmounts: true, includeInbox: true) } label: {
                        Label("Потребують уточнення: \(s.db.operations.filter { $0.needsCaptureAttention }.count + s.capturePending.count)", systemImage: "exclamationmark.bubble")
                    }
                }
                if items.isEmpty { Panel { Text("Немає видимих блоків"); Button("Налаштувати огляд") { configure = true } } }
                ForEach(rows.map { FinamiDashboardRow(items: $0) }) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entry.items) { item in DashboardTile(item: item, date: date) }
                    }
                    if entry.items.contains(where: { $0.kind == .ownFunds }) { quickActions }
                }
                if !items.contains(where: { $0.kind == .ownFunds }) { quickActions }
            }.padding()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack { Button { add = true } label: { Label("Додати операцію", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5).frame(minHeight:44) }.buttonStyle(.borderedProminent); Button { voice=true } label:{Image(systemName:"mic.fill").frame(minWidth:44,minHeight:44)}.buttonStyle(.bordered).accessibilityLabel("Голосовий запис"); Button { scan = true } label: { Image(systemName: "doc.viewfinder").frame(minWidth:44,minHeight:44) }.buttonStyle(.bordered).accessibilityLabel("Імпорт зі скриншота").accessibilityIdentifier("qa.home.scan") }.padding(.horizontal).padding(.vertical,7).background(Color(uiColor:.systemGroupedBackground))
        }.background(finamiScreenBackground(s.db.preferences)).navigationTitle(s.db.preferences?.homeTitle ?? "Головна")
            .toolbar { NavigationLink { FinamiGlobalSearch() } label: { Image(systemName:"magnifyingglass") }.accessibilityLabel("Пошук Finami"); Button { s.changeAppearance { p in p.hideAmounts = !(p.hideAmounts ?? false) } } label: { Image(systemName:s.privateAmounts ? "eye.slash" : "eye") }.accessibilityLabel("Приховати або показати суми"); Button { reorder = true } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Змінити порядок блоків"); Button { configure = true } label: { Image(systemName: "slider.horizontal.3").font(.title2) }.accessibilityLabel("Налаштувати блоки") }
            .sheet(isPresented: $add) { OpEditor(original: Operation(category: "Без категорії", account: s.db.accounts.first?.id ?? cash)) }
            .sheet(item: $quickDraft) { OpEditor(original: $0) }
            .sheet(isPresented:$voice) { FinamiVoice() }
            .sheet(isPresented:$scan) { NavigationStack { FinamiScanView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { scan = false } } } } }
            .sheet(isPresented: $reorder) { NavigationStack { FinamiOrderEditor(target: .dashboard) } }
            .sheet(isPresented: $configure) { NavigationStack { DashboardSettings().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { configure = false } } } } }
    }
}
struct DashboardTile: View {
    @EnvironmentObject var s: Store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var item: DashboardItem; var date: Date
    var ops: [Operation] { s.month(date) }
    private var metrics: FinamiDashboardMetrics { s.dashboardMetrics(date) }
    var inc: Int64 { metrics.income }
    var exp: Int64 { metrics.expense }
    var balance: Int64 { s.includedAccounts.reduce(0) { $0 + s.balance($1) } }
    var small: Bool { item.size == .small && ![.balance,.ownFunds,.creditLimit,.creditPortfolio,.obligations,.allAvailable,.monthlyPayments,.accounts,.paymentCalendar].contains(item.kind) && !dynamicTypeSize.isAccessibilitySize }
    @State private var paymentDetails: FinamiPayment?
    @State private var accountSettings = false
    var masked: Bool {
        if s.privateAmounts || item.hideAmounts == true { return true }
        // A combined overview must not disclose individually hidden account amounts.
        if item.kind == .ownFunds {
            let hidden = Set(s.db.accounts.filter { $0.hideAmounts == true }.map(\.id))
            if s.includedAccounts.contains(where: { hidden.contains($0.id) }) { return true }
            if !hidden.isEmpty && ops.contains(where: { hidden.contains($0.account) || ($0.kind == .transfer && hidden.contains($0.destination)) }) { return true }
        }
        return false
    }
    func display(_ n:Int64)->String { masked ? "••••" : s.displayed(n) }
    func visible(_ n:Int64,_ code:String = "UAH")->String { masked ? "••••" : s.visibleMoney(n,code) }
    var showCharts:Bool { s.db.preferences?.noCharts == false && !masked }
    var detailed: Bool { item.size == .large }
    var compact: Bool { item.size == .small }
    var collapsed: Bool { (s.db.preferences?.collapsedDashboard ?? []).contains(item.id) }
    var tileSpacing: CGFloat { compact ? 6 : detailed ? 16 : 10 }
    var tilePadding: CGFloat { compact ? 10 : detailed ? (s.db.preferences?.modernCompactSpacing == true ? 14 : 20) : 12 }
    var tileMinHeight: CGFloat { compact ? 80 : detailed ? 154 : 108 }
    var color: Color {
        let p = s.db.preferences ?? .init()
        if let name = item.accentName, let custom = IzanamiTheme.all.first(where: {$0.name == name}) { return custom.color }
        if item.kind == .ownFunds { return finamiDesignAccent(p.designAccent) ?? (FinamiDesign(rawValue:p.design ?? "Signature") ?? .signature).tint }
        return (p.colorfulDashboard ?? true) ? item.kind.tileColor : (IzanamiTheme.all.first(where:{$0.name==p.theme})?.color ?? (FinamiDesign(rawValue:p.design ?? "Signature") ?? .signature).tint)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: tileSpacing) {
            if collapsed {
                let summary = collapsedSummary
                if item.kind == .review {
                    NavigationLink { reviewDestination } label: {
                        FinamiCollapsedDashboardCard(title:item.kind.title,summary:"\(reviewCount) · " + (reviewCount == 0 ? "Усе уточнено" : "Відкрити операції"),icon:item.kind.icon,tint:color,template:item.template)
                    }.buttonStyle(.plain).accessibilityLabel("Потребують уточнення").accessibilityValue(String(reviewCount)).accessibilityIdentifier("qa.dashboard.review.collapsed")
                } else {
                    Button { toggleCollapsed() } label: {
                        FinamiCollapsedDashboardCard(title:item.kind.title,summary:summary,icon:item.kind.icon,tint:color,template:item.template)
                    }.buttonStyle(.plain).accessibilityLabel("Розгорнути " + item.kind.title).accessibilityValue(summary).accessibilityIdentifier("qa.dashboard.collapsed." + item.id)
                }
            } else {
            if small {
                HStack {FinamiIconTile(icon:item.kind.icon,tint:color,side:32);Spacer(minLength:0);privacyButton}
                tileTitle
            } else if item.kind == .accounts {
                HStack(alignment:.center,spacing:8) {
                    FinamiIconTile(icon:item.kind.icon,tint:color,side:36)
                    tileTitle.frame(maxWidth:.infinity,alignment:.leading)
                    Button { accountSettings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:44,height:44) }.buttonStyle(.plain).accessibilityLabel("Налаштування карток рахунків").accessibilityIdentifier("qa.home.accounts.settings")
                    privacyButton
                }.padding(.horizontal, 4).padding(.vertical, 2)
            } else {
                HStack(alignment:.center,spacing:9){FinamiIconTile(icon:item.kind.icon,tint:color,side:compact ? 28 : detailed ? 44 : 36);tileTitle;Spacer(minLength:0);privacyButton}
            }
            content
            }
        }
        .frame(maxWidth: .infinity, minHeight: item.kind == .accounts || collapsed ? nil : tileMinHeight, alignment: .topLeading)
        .padding(item.kind == .accounts || collapsed ? 0 : tilePadding)
        .modifier(FinamiDashboardSurface(isAccounts: item.kind == .accounts || collapsed, tint: color, template: item.template, aurora: item.kind == .ownFunds))
        .environment(\.finamiMask, masked)
        .contextMenu { Button(collapsed ? "Розгорнути блок" : "Згорнути блок") { toggleCollapsed() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qa.dashboard.tile." + item.id)
        .sheet(item:$paymentDetails) { FinamiPaymentDetails(payment:$0).environment(\.finamiMask, masked || (s.db.preferences?.designHiddenSubscriptions ?? []).contains($0.id)) }
        .sheet(isPresented:$accountSettings) { NavigationStack { FinamiHomeAccountsSettings().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Готово") { accountSettings = false } } } } }
    }
    private var reviewOperations: [Operation] { s.db.operations.filter { $0.needsCaptureAttention } }
    private var reviewCount: Int { reviewOperations.count + s.capturePending.count }
    private var reviewDestination: some View {
        FinamiReportReviewList(ids: reviewOperations.map(\.id), account: nil, maskAmounts: masked, includeInbox: true)
    }
    private var titleLabel: some View {
        Text(item.kind == .accounts ? "Мої рахунки" : item.kind.title)
            .font(small ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(small ? Color.secondary : Color.primary)
            .fixedSize(horizontal:false,vertical:true).frame(minHeight:44,alignment:.leading)
    }
    @ViewBuilder private var tileTitle: some View {
        if item.kind == .review {
            NavigationLink { reviewDestination } label: { titleLabel }
                .buttonStyle(.plain).accessibilityIdentifier("qa.dashboard.review.title")
        } else {
            Button { toggleCollapsed() } label: { titleLabel }
                .buttonStyle(.plain).accessibilityLabel("Згорнути " + item.kind.title)
        }
    }
    private var collapsedSummary: String {
        if masked { return "Суми приховано" }
        if item.kind == .accounts {
            return FinamiDashboardPreviewPolicy.accounts(count:s.db.accounts.filter{$0.hiddenInOverview != true}.count,masked:false)
        }
        let payments: [FinamiPayment]
        switch item.kind {
        case .obligations: payments = s.upcomingPayments
        case .subscriptions: payments = s.upcomingPayments.filter(\.subscription)
        case .installments: payments = s.upcomingPayments.filter { $0.kind == ObligationKind.installment.title }
        case .recurring: payments = s.upcomingPayments.filter { $0.subscription || $0.kind == ObligationKind.recurring.title || $0.kind == ObligationKind.installment.title }
        default: return "Натисни, щоб розгорнути"
        }
        let next = payments.first
        let prefs = s.db.preferences ?? .init()
        let dateText = item.showPaymentDate == false || (item.kind == .obligations && !prefs.designShowsUpcoming("date")) ? nil : next.map { $0.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier:"uk_UA"))) }
        let amountText = item.showPaymentTotal == false || (item.kind == .obligations && !prefs.designShowsUpcoming("amount")) ? nil : next.map { (prefs.designHiddenSubscriptions ?? []).contains($0.id) ? "••••" : visible($0.amount,$0.currency) }
        return FinamiDashboardPreviewPolicy.payments(count:payments.count,nextAmount:amountText,nextDate:dateText,overdue:next?.overdue == true,masked:false)
    }
    private func toggleCollapsed() { s.changeAppearance { p in var ids = Set(p.collapsedDashboard ?? []); if ids.contains(item.id) { ids.remove(item.id) } else { ids.insert(item.id) }; p.collapsedDashboard = ids.sorted() } }
    var privacyButton: some View {
        Button { s.change { d in var all=DashboardItem.merged(d.dashboard);if let i=all.firstIndex(where:{$0.id==item.id}){all[i].hideAmounts = !(all[i].hideAmounts ?? false)};d.dashboard=all } } label:{Image(systemName:masked ? "eye.slash" : "eye").frame(minWidth:44,minHeight:44)}.buttonStyle(.plain).accessibilityLabel("Показати або приховати суми блоку").disabled(s.privateAmounts).accessibilityIdentifier("qa.dashboard.hide." + item.id)
    }
    var cardBackground: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if item.kind == .balance {
                LinearGradient(colors: [color.opacity(0.18), color.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    func value(_ text: String) -> some View {
        Text(text).font(compact ? .title3.weight(.semibold) : detailed ? .largeTitle.weight(.bold) : .title.weight(.bold))
            .monospacedDigit().lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.68)
            .foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder func amount(_ n: Int64) -> some View {
        let pieces = display(n).components(separatedBy: " · ")
        value(pieces.first ?? money(n))
        if pieces.count > 1 {
            Text(pieces[1]).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
    func detail(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    func metric(_ title: String, _ n: Int64, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(display(n)).font(.headline).monospacedDigit().foregroundStyle(tint)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var overviewFlowMetrics: some View {
        if s.db.preferences?.showIncome == true { metric("Доходи", inc, .green) }
        if s.db.preferences?.showExpenses != false { metric("Витрати", exp, .orange) }
    }
    var cashFlow: some View {
        VStack(alignment:.leading,spacing:12) {
            if s.db.preferences?.showIncome == true { metric("Доходи",inc,.green) }
            if s.db.preferences?.showExpenses != false { metric("Витрати",exp,.orange) }
            if s.db.preferences?.showIncome != true && s.db.preferences?.showExpenses == false { detail("Показники приховано") }
        }
    }
    var categoryGroups: [(key: String, value: Int64)] {
        metrics.categories.filter { item.categorySelection?.contains($0.key) ?? true }
    }
    var categories: some View {
        let groups = categoryGroups
        let total = groups.reduce(Int64(0)) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 11) {
            if groups.isEmpty { detail("Немає витрат за період") }
            else if compact { amount(item.categorySelection == nil ? exp : total); detail("Категорій: \(groups.count)") }
            else {
                amount(item.categorySelection == nil ? exp : total)
                ForEach(Array(groups.prefix(max(1,min(30,item.categoryCount ?? (detailed ? 10 : 4)))).enumerated()), id: \.element.key) { entry in
                    DashboardCategoryLine(title: entry.element.key, amount: entry.element.value, total: total, color: categoryColor(entry.offset), showChart:showCharts)
                }
                if groups.count > (item.categoryCount ?? (detailed ? 10 : 4)) { detail("Показано найбільші категорії") }
            }
        }
    }
    func categoryColor(_ index: Int) -> Color {
        let palette: [Color] = [.purple, .teal, .blue, .orange, .pink, .green, .indigo, .cyan]
        return (s.db.preferences?.colorfulDashboard ?? true) ? palette[index % palette.count] : color
    }
    @ViewBuilder var accounts: some View {
        let shown = finamiOrderedAccounts(s.db.accounts).filter { $0.hiddenInOverview != true }
        if shown.isEmpty { detail("Немає рахунків. Додай рахунок у вкладці «Рахунки» або увімкни його в налаштуваннях блоку.") }
        if (s.db.preferences ?? .init()).finamiLayout != "cards" {
            FinamiCompactAccountsGrid(accounts:shown,mode:"all",date:date,template:item.template)
        } else {
            VStack(spacing: 10) { ForEach(shown) { a in FinamiHomeAccountCard(accountID:a.id,date:date,fallbackTint:color,dashboardSize:item.size,template:item.template) } }
        }
    }
    @ViewBuilder var content: some View {
        switch item.kind {
        case .balance: amount(balance); detail("Чистий баланс рахунків · без невикористаного кредиту")
        case .creditLimit: amount(s.totalCreditLimit);detail("Ліміт усіх включених кредитних рахунків")
        case .creditPortfolio: FinamiCreditSummary(showLimit:item.showLimit ?? true,showUsed:item.showUsed ?? true,showAvailable:item.showAvailable ?? true, dashboardSize: item.size)
        case .allAvailable: amount(s.totalOwnFunds+s.totalAvailableCredit);detail("Власні кошти разом із доступним кредитом")
        case .monthlyPayments: FinamiMonthPayments(dashboardSize: item.size)
        case .paymentCalendar: FinamiCalendarGrid(compact: compact, masked: masked)
        case .cashflow: cashFlow
        case .categories: categories
        case .recent:
            if ops.isEmpty { detail("Немає операцій") }
            else {
                let shown = Array(metrics.recent.prefix(compact ? 1 : detailed ? 5 : 2))
                ForEach(shown) { o in
                    if small { Text(visible(o.amount)).font(.subheadline.weight(.semibold)).monospacedDigit(); detail(o.note.isEmpty ? o.category : o.note) }
                    else { OperationRow(o: o) }
                    if o.id != shown.last?.id { Divider() }
                }
            }
        case .accounts: accounts
        case .budget:
            if s.db.budget > 0 {
                amount(max(0,s.db.budget-exp)); detail("Залишок бюджету · з \(visible(s.db.budget))")
                if showCharts { ProgressView(value: max(0,min(1, Double(exp)/Double(s.db.budget)))).tint(color) }
            } else { detail("Не задано") }
        case .obligations:
            FinamiUpcomingDesign(item: item, open: { paymentDetails = $0 })
        case .subscriptions: paymentSummary(s.upcomingPayments.filter(\.subscription), showRemaining: false)
        case .reminders: value(String((s.db.reminders ?? []).filter{$0.enabled && $0.date > Date()}.count)); detail("Майбутніх нагадувань")
        case .forecast:
            if let f=s.db.forecast {
                let snapshot=s.planningSnapshot(f)
                if let projection=snapshot.projection {
                    amount(projection.closing); detail("Прогнозований залишок · \(f.days) днів")
                    if snapshot.unknown > 0 { detail("Прогноз неповний: немає курсу") }
                    else { metric("Орієнтир на день",projection.safeDaily,.teal) }
                } else { detail("Перевір параметри прогнозу") }
            } else { detail("За бажанням") }
            NavigationLink("Налаштувати прогноз") { FinamiPlanningView() }
        case .uncategorized: value(String(ops.filter{$0.category == "Без категорії"}.count)); detail("Операцій без категорії")
        case .goals: obligationSummary([.goal])
        case .debt: metric("Мені винні", s.db.obligations.filter{$0.kind == .owed}.reduce(0){$0+$1.remaining}, .green); metric("Я винен", s.db.obligations.filter{$0.kind == .owe}.reduce(0){$0+$1.remaining}, .orange)
        case .installments: paymentSummary(s.upcomingPayments.filter { $0.kind == ObligationKind.installment.title }, showRemaining: true)
        case .recurring: paymentSummary(s.upcomingPayments.filter { $0.subscription || $0.kind == ObligationKind.recurring.title || $0.kind == ObligationKind.installment.title }, showRemaining: false)
        case .statistics: value(String(ops.count)); detail("Операцій · потік \(visible(inc-exp))")
        case .fees: amount(s.totals(ops.filter{$0.expenseGroup == "🏦 Комісії"}, .expense))
        case .ownFunds:
            amount(s.totalOwnFunds); detail("Без кредитних коштів")
            if s.db.preferences?.showIncome == true || s.db.preferences?.showExpenses != false {
                Divider().padding(.vertical, 2)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { overviewFlowMetrics }
                } else {
                    HStack(alignment: .top, spacing: 12) { overviewFlowMetrics }
                }
            }
        case .creditDebt: amount(s.totalAccountDebt); detail("Використані кредитні кошти")
        case .availableCredit: amount(s.totalAvailableCredit); detail("Не є власними коштами")
        case .review:
            NavigationLink { reviewDestination } label: {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        value(String(reviewCount))
                        detail(reviewCount == 0 ? "Усе уточнено" : "Необхідна увага · відкрити")
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Уточнити операції").accessibilityValue(String(reviewCount)).accessibilityIdentifier("qa.dashboard.review.open")
        case .savings: value(masked ? "••••" : inc > 0 ? ((Double(inc-exp)/Double(inc)).formatted(.percent.precision(.fractionLength(1)))) : "—"); detail("Частка доходу після витрат")
        }
    }
    @ViewBuilder func paymentSummary(_ payments: [FinamiPayment], showRemaining: Bool) -> some View {
        if payments.isEmpty { detail("Немає активних платежів") }
        else {
            let remainingMode = showRemaining && item.showPaymentRemaining != false
            let interval = Calendar.current.dateInterval(of: .month, for: date)
            let ids = Set(payments.map(\.id))
            let planned = interval.map { s.calendarEvents(interval:$0).filter { event in !event.paid && ids.contains(event.paymentID) } } ?? []
            if item.showPaymentTotal != false {
                ForEach(Array(Set(payments.map(\.currency))).sorted(), id: \.self) { code in
                    let total = remainingMode ? payments.filter { $0.currency == code }.reduce(Int64(0)) { $0 + ($1.remaining ?? $1.amount) } : planned.filter { $0.currency == code }.reduce(Int64(0)) { $0 + $1.amount }
                    Text(payments.contains { (s.db.preferences?.designHiddenSubscriptions ?? []).contains($0.id) && $0.currency == code } ? "••••" : visible(total, code)).font(.title2.bold()).monospacedDigit()
                }
                detail(remainingMode ? "Залишок боргу" : "Неоплачене за графіком · " + monthName(date))
            }
            if item.showPaymentNames != false {
                ForEach(Array(payments.prefix(max(1, min(20, item.categoryCount ?? (compact ? 1 : detailed ? 6 : 3)))))) { p in
                    Button { paymentDetails = p } label: {
                        let loan = s.db.obligations.first { $0.id == p.id }
                        FinamiModernPaymentRow(name:p.name,kind:p.kind,date:p.date,currency:p.currency,due:p.amount,total:loan?.target,monthly:loan?.monthly,remaining:p.remaining,status:p.overdue ? "Прострочено" : "Очікує оплати",showDate:item.showPaymentDate != false,showImage:item.showPaymentImage != false,showRemaining:remainingMode,masked:masked || (s.db.preferences?.designHiddenSubscriptions ?? []).contains(p.id))
                    }.buttonStyle(.plain)
                }

            }
            FinamiAllPaymentsLink(count: payments.count, filter: item.kind == .installments ? "installments" : item.kind == .subscriptions ? "subscriptions" : "recurring", masked: masked)
            if item.showPaymentTotal == false && item.showPaymentNames == false { detail("Показники приховано") }
        }
    }
    @ViewBuilder func obligationSummary(_ kinds: [ObligationKind]) -> some View {
        let matching = s.db.obligations.filter { kinds.contains($0.kind) }
        amount(matching.reduce(0){$0+$1.remaining}); detail("\(matching.count) записів")
    }
}
struct DashboardCategoryLine: View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var title: String; var amount: Int64; var total: Int64; var color: Color; var showChart: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.subheadline).lineLimit(2)
                Spacer(minLength: 3)
                Text(masked ? "••••" : s.visibleMoney(amount)).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            if showChart && !s.privateAmounts && !masked { ProgressView(value: total > 0 ? min(1, max(0, Double(amount)/Double(total))) : 0).tint(color).accessibilityLabel(title).accessibilityValue(money(amount)) }
        }
    }
}

