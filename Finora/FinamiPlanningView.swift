import SwiftUI
import Charts

struct FinamiPlanSnapshot {
    var projection: FinamiPlanningResult?
    var fixed: Int64
    var unknown: Int
    var overdue: Int
}
@MainActor extension Store {
    func planningSnapshot(_ settings: ForecastPreferences, now: Date = Date()) -> FinamiPlanSnapshot {
        let cal = Calendar.current, start = cal.startOfDay(for:now)
        let horizon = max(1,min(365,settings.days))
        let end = cal.date(byAdding:.day,value:horizon,to:start) ?? start
        var entries: [FinamiPlanningEntry] = [], unknown = 0, overdue = 0
        var fixed: Int64 = 0
        unknown += includedAccounts.filter { $0.code != "UAH" && ($0.code != "USD" || currentRate == nil) && ownFunds($0) > 0 }.count
        func converted(_ amount:Int64,_ code:String)->Int64? {
            if code == "UAH" { return amount }
            if code == "USD", let rate=currentRate { return fxMinor(amount,rate:rate) }
            return nil
        }
        func addPayment(_ amount:Int64,_ code:String,_ date:Date) {
            guard amount > 0 else { return }
            if let n=converted(amount,code),n > 0 {
                let (sum,overflow)=fixed.addingReportingOverflow(n)
                guard !overflow else { unknown += 1;return }
                fixed=sum;entries.append(.init(date:date,amount:-n))
            } else { unknown += 1 }
        }
        if settings.includeSchedule != false, end > start {
            let events=calendarEvents(interval:DateInterval(start:start,end:end)).filter{!$0.paid}
            for event in events { addPayment(event.amount,event.currency,event.date) }
            let late=upcomingPayments.filter{$0.date < start && $0.amount > 0}
            overdue=late.count
            for payment in late { addPayment(payment.amount,payment.currency,start) }
        }
        if settings.planned > 0 { entries.append(.init(date:start,amount:-settings.planned)) }
        if let date=settings.incomeDate, settings.expected > 0 { entries.append(.init(date:cal.startOfDay(for:date),amount:settings.expected)) }
        let projection=finamiPlanning(start:start,horizon:horizon,opening:totalOwnFunds,reserve:settings.reserve,daily:settings.daily ?? 0,entries:entries,calendar:cal)
        return .init(projection:projection,fixed:fixed,unknown:unknown,overdue:overdue)
    }
}

// Uses actual own funds, never available credit, and existing schedule projections.
struct FinamiPlanningView: View {
    @EnvironmentObject private var s: Store
    @State private var expected = "", planned = "", reserve = "", daily = ""
    @State private var days = 30
    @State private var payday = Date()
    @State private var usePayday = false
    @State private var includeSchedule = true
    @State private var loaded = false
    private var valid: Bool { [expected,planned,reserve,daily].allSatisfy { $0.isEmpty || (cents($0) ?? -1) >= 0 } }
    private var start: Date { Calendar.current.startOfDay(for: Date()) }
    private var end: Date { Calendar.current.date(byAdding: .day, value: days, to: start) ?? start }
    private func cash(_ value: Int64) -> String { s.visibleMoney(value) }
    private var settings: ForecastPreferences {
        .init(expected:cents(expected) ?? 0,planned:cents(planned) ?? 0,reserve:cents(reserve) ?? 0,days:days,daily:cents(daily) ?? 0,incomeDate:usePayday ? payday : nil,includeSchedule:includeSchedule)
    }
    private var snapshot: FinamiPlanSnapshot {
        valid ? s.planningSnapshot(settings) : .init(projection:nil,fixed:0,unknown:0,overdue:0)
    }
    var body: some View {
        let result = snapshot
        Form {
            Section("Параметри сценарію") {
                Text("План не створює операцій. Доходи та комісії біржі вносяться вручну в журналі; тут — тільки майбутня сума у гривнях.").font(.caption).foregroundStyle(.secondary)
                FinamiField("Резерв, ₴", text: $reserve, keyboard: .decimalPad)
                FinamiField("Повсякденні витрати на день, ₴", text: $daily, keyboard: .decimalPad)
                FinamiField("Додаткові платежі (поза графіком), ₴", text: $planned, keyboard: .decimalPad)
                Toggle("Врахувати графіки платежів", isOn: $includeSchedule)
                Toggle("Очікується дохід", isOn: $usePayday)
                if usePayday {
                    FinamiField("Очікуваний дохід після комісій, ₴", text: $expected, keyboard: .decimalPad)
                    DatePicker("Дата доходу", selection: $payday, displayedComponents: .date)
                }
                Stepper("Горизонт: \(days) днів", value: $days, in: 1...365)
                HStack { ForEach([7,30,90,365],id:\.self) { n in Button("\(n)"){days=n}.buttonStyle(.bordered).tint(days == n ? Color.accentColor : Color.secondary) } }
            }
            Section("Результат") {
                LabeledContent("Власні кошти", value: cash(s.totalOwnFunds))
                LabeledContent("Платежі за графіком", value: cash(result.fixed))
                if result.overdue > 0 { Text("Прострочені платежі: \(result.overdue). Найближчу суму включено сьогодні; наступні дати потребують перевірки.").font(.caption).foregroundStyle(.orange) }
                if result.unknown > 0 { Text("Не враховано валютних залишків або платежів без курсу: \(result.unknown). Прогноз неповний.").font(.caption).foregroundStyle(.orange) }
                if !usePayday && (cents(expected) ?? 0) > 0 { Text("Для врахування збереженого доходу вкажи дату.").font(.caption).foregroundStyle(.orange) }
                if usePayday, Calendar.current.startOfDay(for: payday) < start { Text("Дата доходу минула; сума не включена до прогнозу.").font(.caption).foregroundStyle(.orange) }
                if usePayday, Calendar.current.startOfDay(for: payday) >= end { Text("Дата доходу за межами горизонту.").font(.caption).foregroundStyle(.orange) }
                if let r = result.projection {
                    LabeledContent("Вільно без майбутнього доходу", value: cash(r.freeBeforeIncome))
                    LabeledContent("Орієнтир на день", value: result.unknown == 0 ? cash(r.safeDaily) : "—")
                    LabeledContent("Очікуваний залишок", value: cash(r.closing))
                    if let date = r.firstReserveShortfall { Label("Ризик нестачі: " + date.formatted(.dateTime.day().month(.wide)), systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    if !s.privateAmounts {
                        Chart {
                            ForEach(r.days) { point in
                                LineMark(x: .value("Дата",point.date), y: .value("Баланс",Double(point.balance)/100)).foregroundStyle(Color.accentColor)
                            }
                            RuleMark(y: .value("Резерв",Double(cents(reserve) ?? 0)/100)).foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth:1,dash:[4,4]))
                        }.frame(height: 170).accessibilityLabel("Прогноз власних коштів")
                    }
                } else { Text("Перевір введені суми.").foregroundStyle(.orange) }
                Text("Дохід у день платежу враховується після списань. Курс USD — поточний, майбутні курси невідомі. Кредитний ліміт не є доходом. Віртуальні бюджети не віднімаються повторно.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("Віртуальні конверти") { FinamiEnvelopesView() }
                NavigationLink("Кредитний центр") { FinamiCreditCenter() }
                NavigationLink("Календар платежів") { CalendarView() }
                NavigationLink("Фінансові цілі") { Obligations(kind:.goal) }
                Button("Зберегти сценарій") { let plan=settings; s.change { $0.forecast = plan } }.disabled(!valid)
                Button("Очистити сценарій",role:.destructive) { if s.change({$0.forecast=nil}) { expected="";planned="";reserve="";daily="";days=30;usePayday=false;includeSchedule=true;payday=Date() } }
            }
        }.navigationTitle("Фінансове планування").onAppear {
            guard !loaded else { return }; loaded = true
            if let f = s.db.forecast {
                expected = amountText(f.expected); planned = amountText(f.planned); reserve = amountText(f.reserve); daily = amountText(f.daily ?? 0)
                days = max(1,min(365,f.days)); usePayday = f.incomeDate != nil; payday = f.incomeDate ?? Date(); includeSchedule = f.includeSchedule ?? true
            }
        }
    }
}
struct FinamiEnvelopesView: View {
    @EnvironmentObject private var s: Store
    @State private var month = Date()
    var body: some View {
        List {
            Section { MonthControl(date:$month); Text("Конверти — це наявні ліміти категорій, а не окремі гроші. Вони не створюють переказів і не зменшують баланс.").font(.caption) }
            Section("Ліміти категорій") {
                let ops = s.month(month)
                ForEach(s.db.expenseCategories.filter{ (s.db.limits[$0] ?? 0) > 0 },id:\.self) { category in
                    let spent = s.totals(ops.filter{$0.expenseGroup == category},.expense)
                    if let envelope = finamiEnvelope(limit:s.db.limits[category] ?? 0,spent:spent) {
                        VStack(alignment:.leading,spacing:6) {
                            Text(category).font(.headline)
                            LabeledContent("Використано",value:s.visibleMoney(envelope.spent))
                            LabeledContent(envelope.remaining < 0 ? "Перевищення" : "Залишок",value:s.visibleMoney(abs(envelope.remaining)))
                            if !s.privateAmounts { ProgressView(value:max(0,min(1,Double(envelope.spent)/Double(envelope.limit)))).tint(envelope.remaining < 0 ? .orange : .accentColor) }
                        }
                    }
                }
                if !s.db.limits.values.contains(where:{$0 > 0}) { Text("Налаштуй ліміти категорій у бюджетах.").foregroundStyle(.secondary) }
                NavigationLink("Змінити ліміти") { Budgets() }
            }
        }.navigationTitle("Віртуальні конверти")
    }
}
struct FinamiCreditCenter: View {
    @EnvironmentObject private var s: Store
    @State private var payment: FinamiPayment?
    @State private var editAccount: Account?
    var body: some View {
        List {
            Section("Кредитні рахунки") {
                LabeledContent("Загальний ліміт",value:s.visibleMoney(s.totalCreditLimit))
                LabeledContent("Використано",value:s.visibleMoney(s.totalCreditUsed))
                LabeledContent("Невикористаний ліміт",value:s.visibleMoney(s.totalAvailableCredit))
                ForEach(s.includedAccounts.filter(\.isCredit)) { a in
                    VStack(alignment:.leading,spacing:6) {
                        Text(a.name).font(.headline)
                        LabeledContent("Ліміт",value:a.hideAmounts == true ? "••••" : s.visibleMoney(a.limit,a.code))
                        LabeledContent("Борг за рахунком",value:a.hideAmounts == true ? "••••" : s.visibleMoney(s.debt(a),a.code))
                        LabeledContent("Власні кошти",value:a.hideAmounts == true ? "••••" : s.visibleMoney(s.ownFunds(a),a.code))
                        if a.limit > 0 && !s.privateAmounts && a.hideAmounts != true { ProgressView(value:min(1,Double(s.debt(a))/Double(a.limit))) }
                        Button("Редагувати рахунок") { editAccount=a }.buttonStyle(.borderless)
                    }
                }
            }
            Section("Розстрочки та інші борги") {
                let loans = s.db.obligations.filter{ [.installment,.owe].contains($0.kind) && $0.remaining > 0 }
                ForEach(loans) { loan in
                    NavigationLink { ObligationEditor(original:loan) } label: {
                        VStack(alignment:.leading,spacing:6) {
                            Text(loan.name).font(.headline)
                            LabeledContent("Загальна сума",value:s.visibleMoney(loan.target))
                            LabeledContent("Залишок",value:s.visibleMoney(loan.remaining))
                            LabeledContent("Щомісячний платіж",value:loan.monthly > 0 ? s.visibleMoney(loan.monthly) : "Не задано")
                            LabeledContent("До сплати",value:s.visibleMoney(loan.nextCharge))
                            Text(loan.due.formatted(.dateTime.day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if loans.isEmpty { Text("Немає активних боргів.").foregroundStyle(.secondary) }
                Text("Борги за картками і розстрочками показані окремо: вони можуть використовувати спільний ліміт. Не додаємо їх автоматично.").font(.caption)
                NavigationLink("Розстрочки") { Obligations(kind:.installment) }
            }
            Section("Найближчі платежі") {
                ForEach(Array(s.upcomingPayments.prefix(12))) { p in
                    Button { payment = p } label: { VStack(alignment:.leading) { Text(p.name); LabeledContent(p.date.formatted(.dateTime.day().month(.wide)),value:s.visibleMoney(p.amount,p.currency)).font(.caption) } }.buttonStyle(.plain)
                }
                NavigationLink("Повний календар") { CalendarView() }
            }
        }.navigationTitle("Кредитний центр").sheet(item:$payment) { FinamiPaymentDetails(payment:$0) }.sheet(item:$editAccount) { AccountEditor(a:$0) }
    }
}
