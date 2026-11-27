import SwiftUI

struct FinamiQuickMenuTile: View {
    var title:String
    var icon:String
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            FinamiIconTile(icon:icon,tint:finoraAccent,side:36)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }.frame(maxWidth:.infinity,minHeight:84,alignment:.leading).padding(12).modifier(FinamiCardStyle(tint:finoraAccent))
    }
}
struct FinamiSimpleHome: View {
    @EnvironmentObject private var s:Store
    @State private var operation:Operation?
    @State private var payment:FinamiPayment?
    private var p:AppearancePreferences { s.db.preferences ?? .init() }
    // Conservative privacy: an existing hidden dashboard total stays hidden in this alternate layout.
    private var masked:Bool { s.privateAmounts || DashboardItem.merged(s.db.dashboard).contains { $0.hideAmounts == true } }
    private var accountList:[Account] { finamiOrderedAccounts(s.db.accounts.filter{$0.hiddenInOverview != true}) }
    private var totalsMasked:Bool { masked || s.includedAccounts.contains{$0.hideAmounts == true} }
    private func amount(_ value:Int64,_ code:String="UAH",hide:Bool=false)->String { hide || masked ? "••••" : s.visibleMoney(value,code) }
    private func metric(_ title:String,_ value:Int64)->some View { LabeledContent(title,value:amount(value,hide:totalsMasked)).font(.subheadline) }
    private var summary:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Власні кошти").foregroundStyle(.secondary).font(.subheadline).accessibilityIdentifier("qa.home.simple.summary")
            Text(amount(s.totalOwnFunds,hide:totalsMasked)).font(.largeTitle.bold()).monospacedDigit().minimumScaleFactor(0.55)
            Divider()
            metric("Доступний кредит",s.totalAvailableCredit)
            metric("Використано кредиту",s.totalCreditUsed)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiAuroraSurface(tint:finamiDesignAccent(p.designAccent) ?? finoraAccent))
    }
    private func add(_ kind:Kind) { operation=Operation(kind:kind,category:"Без категорії",account:s.db.accounts.first?.id ?? cash) }
    private var actions:some View {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
            Button { add(.expense) } label:{FinamiQuickMenuTile(title:"Витрата",icon:"minus.circle")}
            Button { add(.income) } label:{FinamiQuickMenuTile(title:"Дохід",icon:"plus.circle")}
            Button { add(.transfer) } label:{FinamiQuickMenuTile(title:"Переказ",icon:"arrow.left.arrow.right")}
            NavigationLink { FinamiBalanceView(initialMode:"anchor") } label:{FinamiQuickMenuTile(title:"Звірка",icon:"checkmark.circle")}
        }.buttonStyle(.plain)
    }
    private func paymentRow(_ item:FinamiPayment)->some View {
        Button { payment=item } label: {
            HStack(spacing:10) {
                FinamiPaymentGlyph(icon:"calendar",side:42)
                VStack(alignment:.leading,spacing:4) {
                    Text(item.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                    Text(item.name).font(.subheadline.weight(.semibold))
                    if let loan=s.db.obligations.first(where:{$0.id==item.id}),p.modernPaymentTotal != false { Text("Всього: "+amount(loan.target,item.currency)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength:6)
                VStack(alignment:.trailing,spacing:4) {
                    Text(amount(item.amount,item.currency,hide:(p.designHiddenSubscriptions ?? []).contains(item.id))).font(.subheadline.bold()).monospacedDigit()
                    Text("До сплати").font(.caption).foregroundStyle(.secondary)
                    if let monthly=item.recurringAmount,monthly != item.amount,p.modernPaymentMonthly != false { Text("Місяць: "+amount(monthly,item.currency)).font(.caption) }
                }
            }.padding(12).frame(minHeight:60).modifier(FinamiCardStyle(tint:finoraAccent))
        }.buttonStyle(.plain)
    }
    var body:some View {
        ScrollView { LazyVStack(alignment:.leading,spacing:12) {
            summary
            actions
            let review = s.db.operations.filter { $0.needsCaptureAttention }
            let count = review.count + s.capturePending.count
            if count > 0 {
                NavigationLink { FinamiReportReviewList(ids: review.map(\.id), account: nil, maskAmounts: masked, includeInbox: true) } label: {
                    FinamiCollapsedDashboardCard(title: "Необхідна увага", summary: "\(count) · Відкрити операції", icon: "exclamationmark.bubble.fill", tint: .orange, template: nil)
                }.buttonStyle(.plain)
            }
            Text("Рахунки").font(.headline)
            FinamiCompactAccountsGrid(accounts:accountList,mode:"all",date:Date(),onAccountsScreen:false,forceList:true).environment(\.finamiMask,masked)
            if !s.upcomingPayments.isEmpty {
                NavigationLink { CalendarView() } label:{ HStack {Text("Найближчі платежі").font(.headline);Spacer();Image(systemName:"chevron.right")} }.buttonStyle(.plain)
                if p.designStyle(for: "upcoming") != nil || p.componentSizes?["upcoming"] != nil || p.designUpcomingFields != nil {
                    FinamiUpcomingDesign(item: DashboardItem.merged(s.db.dashboard).first { $0.kind == .obligations } ?? .init(kind: .obligations, enabled: true, size: .medium), open: { payment = $0 }).environment(\.finamiMask,masked)
                } else { ForEach(Array(s.upcomingPayments.prefix(5))) { item in paymentRow(item) } }
            }
        }.padding() }.background(finamiScreenBackground(s.db.preferences)).navigationTitle(p.homeTitle ?? "Головна")
        .toolbar {
            NavigationLink {FinamiGlobalSearch()} label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("Пошук Finami")
            Button {s.changeAppearance{$0.hideAmounts = !s.privateAmounts}} label:{Image(systemName:s.privateAmounts ? "eye.slash":"eye")}.accessibilityLabel("Приховати або показати суми")
            NavigationLink {AppearanceView()} label:{Image(systemName:"paintpalette")}.accessibilityLabel("Finami Design")
        }.sheet(item:$operation){OpEditor(original:$0)}.sheet(item:$payment){FinamiPaymentDetails(payment:$0)}
    }
}
