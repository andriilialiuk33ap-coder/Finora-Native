import SwiftUI
import Charts

struct FinamiNextReviewView: View {
    @EnvironmentObject private var s:Store
    @State private var pairs:[FinamiReviewPair]=[]
    @State private var prices:[FinamiPriceChange]=[]
    @State private var edit:Operation?
    @State private var running=false
    @State private var analyzedVersion:UInt64?
    private func refresh() async {
        running=true
        let rows=s.db.operations, version=s.databaseVersion
        let result=await Task.detached(priority:.userInitiated) { (finamiReviewPairs(rows),finamiPriceChanges(rows)) }.value
        if s.databaseVersion == version {pairs=result.0;prices=result.1;analyzedVersion=version}
        running=false
    }
    private func row(_ id:String)->some View {
        let operation=s.db.operations.first{$0.id==id}
        return Group {
            if let operation {
                Button {edit=operation} label:{OperationRow(o:operation).environment(\.finamiMask,s.db.accounts.contains{$0.id==operation.account && $0.hideAmounts==true})}.buttonStyle(.plain)
            }
        }
    }
    var body: some View {
        List {
            Section {
                Text("Лише підказки. Схожі покупки можуть бути справжніми. Нічого не видаляється автоматично.").font(.caption)
                Button("Перевірити зараз") {Task {await refresh()}}.disabled(running)
                if running {ProgressView()}
                if let version=analyzedVersion,version != s.databaseVersion {Text("База змінилася. Онови перевірку.").foregroundStyle(.orange)}
            }
            if analyzedVersion==s.databaseVersion {
                Section("Схожі операції · \(pairs.count)") {
                    if pairs.isEmpty {Text("Не знайдено за поточними правилами").foregroundStyle(.secondary)}
                    ForEach(pairs) {pair in VStack(alignment:.leading,spacing:8){row(pair.first);Divider();row(pair.second)}}
                    if pairs.count==100 {Text("Показано не більше 100 пар за один аналіз.").font(.caption)}
                }
                Section("Зміни ціни підписок · \(prices.count)") {
                    if prices.isEmpty {Text("Не знайдено за поточними правилами").foregroundStyle(.secondary)}
                    ForEach(prices) {price in
                        let masked=s.privateAmounts || s.db.accounts.contains{$0.id==price.account && $0.hideAmounts==true}
                        VStack(alignment:.leading,spacing:6) {
                            Text(finamiMerchantDisplay(price.merchant)).font(.headline)
                            Text(masked ? "••••" : currencyMoney(price.previous,price.currency)+" → "+currencyMoney(price.current,price.currency)).font(.subheadline)
                            row(price.currentID)
                        }
                    }
                    Text("Потрібні три щомісячні операції у категорії підписок зі стабільною попередньою ціною. Не гарантує виявлення всіх підписок.").font(.caption)
                }
            }
        }.navigationTitle("Перевірка операцій").task {await refresh()}.sheet(item:$edit){OpEditor(original:$0)}
    }
}

struct FinamiNextInsightsView: View {
    @EnvironmentObject private var s:Store
    @State private var end=Date()
    @State private var months=12
    private struct Query:Hashable {let version:UInt64;let end:Date;let months:Int}
    @State private var computed:[FinamiMonthInsight]=[]
    @State private var applied:Query?
    private var query:Query {Query(version:s.databaseVersion,end:Calendar.current.startOfDay(for:end),months:months)}
    private func refresh(_ q:Query) async {
        let accounts=s.db.accounts, operations=s.db.operations
        let cutoff=min(Date(),Calendar.current.date(byAdding:.day,value:1,to:q.end)?.addingTimeInterval(-0.001) ?? q.end)
        let rows=await Task.detached(priority:.userInitiated) {
            let allowed=Set(accounts.filter{$0.hideAmounts != true && $0.excludedFromTotals != true}.map(\.id))
            return finamiMonthInsights(operations.filter{allowed.contains($0.account)},ending:cutoff,months:q.months)
        }.value
        guard !Task.isCancelled,query==q else{return}
        computed=rows;applied=q
    }
    var body:some View {
        let current=query
        let data=applied==current ? computed:[]
        List {
            Section("Період") {
                DatePicker("До дати",selection:$end,in:...Date(),displayedComponents:.date)
                Picker("Місяців",selection:$months) {Text("3").tag(3);Text("6").tag(6);Text("12").tag(12);Text("24").tag(24)}.pickerStyle(.segmented)
                NavigationLink("Історія позиції рахунків") { FinamiPositionHistoryView() }
                Text("Розрахунок за історичною сумою UAH. Перекази, кредити та неуточнені надходження не є доходом. Приховані й виключені рахунки не враховано.").font(.caption)
            }
            if applied != current {Section {ProgressView("Розрахунок…")}}
            if !s.privateAmounts && !data.isEmpty {
                Section("Доходи та чисті витрати") {
                    Chart {
                        ForEach(data) {r in
                            BarMark(x:.value("Місяць",r.month,unit:.month),y:.value("Сума",Double(r.income)/100)).foregroundStyle(by:.value("Тип","Доходи")).position(by:.value("Тип","Доходи"))
                            BarMark(x:.value("Місяць",r.month,unit:.month),y:.value("Сума",Double(r.expense)/100)).foregroundStyle(by:.value("Тип","Витрати")).position(by:.value("Тип","Витрати"))
                        }
                    }.frame(height:180).accessibilityLabel("Доходи та витрати за місяцями")
                }
            }
            ForEach(Array(data.reversed())) {r in
                Section(monthName(r.month)) {
                    LabeledContent("Доходи",value:s.visibleMoney(r.income))
                    LabeledContent("Чисті витрати",value:s.visibleMoney(r.expense))
                    LabeledContent("Чистий потік",value:s.visibleMoney(r.net))
                    LabeledContent("Повернення",value:s.visibleMoney(r.refunds))
                    LabeledContent("Неуточнені зарахування",value:s.visibleMoney(r.unclassifiedIn))
                    LabeledContent("Неуточнені списання",value:s.visibleMoney(r.unclassifiedOut))
                    LabeledContent("Операцій / уточнити",value:"\(r.count) / \(r.review)")
                    LabeledContent("Витрат без категорії",value:"\(r.uncategorized)")
                    if r.review+r.uncategorized>0 {Label("Підсумок попередній — перевір класифікацію",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)}
                }
            }
        }.navigationTitle("Фінансові підсумки").task(id:current){await refresh(current)}
    }
}

struct FinamiExchangeDiaryView:View {
    @EnvironmentObject private var s:Store
    @State private var editing:FinamiExchangeRecord?
    @State private var deleting:FinamiExchangeRecord?
    @State private var confirmDelete=false
    private var records:[FinamiExchangeRecord] {s.db.exchangeDiary ?? []}
    private func token(_ n:Int64)->String {s.privateAmounts ? "••••" : finamiTokenText(n)+" USDT"}
    var body:some View {
        List {
            Section("Окремий журнал біржі") {
                Text("Веди вручну зарплату та продаж USDT з точністю до 8 знаків. Це окремий журнал: не створює операцій UAH/USD, не входить у загальний баланс і не замінює банківську звірку. Початковий залишок введи як надходження.").font(.caption)
                LabeledContent("Залишок за журналом",value:finamiExchangeBalance(records).map{token($0)} ?? "Некоректна історія")
                Button {editing=FinamiExchangeRecord()} label:{Label("Додати надходження USDT",systemImage:"plus.circle")}
                Button {editing=FinamiExchangeRecord(kind:"sale")} label:{Label("Додати продаж USDT",systemImage:"arrow.left.arrow.right")}
            }
            Section("Історія") {
                if records.isEmpty {Text("Записів ще немає").foregroundStyle(.secondary)}
                ForEach(records.sorted{$0.date>$1.date}) {r in
                    Button {editing=r} label:{VStack(alignment:.leading,spacing:4){
                        Text(r.kind=="income" ? "Надходження" : "Продаж").font(.headline)
                        Text(token(r.units)).monospacedDigit()
                        if r.kind=="sale" {
                            Text("Комісія: "+token(r.fee)+" · отримано: "+s.visibleMoney(r.receivedUAH)).font(.caption)
                            if let links=r.linkedReceiptIDs,!links.isEmpty {
                                let matched=finamiExchangeReceiptTotal(ids:links,operations:s.db.operations,accounts:s.db.accounts,date:r.date)==r.receivedUAH
                                Label(matched ? "Звірено банківські рядки: \(links.count)" : "Потрібна повторна звірка",systemImage:matched ? "checkmark.circle" : "exclamationmark.circle").font(.caption).foregroundStyle(matched ? Color.green:Color.orange)
                            }
                        }
                        Text(r.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                    }}.buttonStyle(.plain).swipeActions {Button("Видалити",role:.destructive){deleting=r;confirmDelete=true}}
                }
            }
        }.navigationTitle("Журнал USDT").sheet(item:$editing){FinamiExchangeEditor(record:$0)}
         .confirmationDialog("Видалити запис журналу?",isPresented:$confirmDelete,titleVisibility:.visible) {
             Button("Видалити",role:.destructive) {
                 guard let deleting else{return}
                 let next=records.filter{$0.id != deleting.id}
                 guard finamiExchangeBalance(next) != nil else{s.error="Видалення призведе до від’ємного залишку USDT.";return}
                 s.change{$0.exchangeDiary=next}
             }
         }
    }
}
private struct FinamiExchangeEditor:View {
    @EnvironmentObject private var s:Store
    @Environment(\.dismiss) private var dismiss
    @State private var record:FinamiExchangeRecord
    @State private var units:String
    @State private var fee:String
    @State private var order:String
    @State private var received:String
    @State private var linked:Set<String>
    init(record:FinamiExchangeRecord) {
        _record=State(initialValue:record)
        _units=State(initialValue:record.units==0 ? "" : finamiTokenText(record.units))
        _fee=State(initialValue:finamiTokenText(record.fee))
        _order=State(initialValue:record.orderUAH==0 ? "" : amountText(record.orderUAH))
        _received=State(initialValue:record.receivedUAH==0 ? "" : amountText(record.receivedUAH))
        _linked=State(initialValue:Set(record.linkedReceiptIDs ?? []))
    }
    private var candidate:FinamiExchangeRecord? {
        guard let n=finamiTokenUnits(units),n>0 else{return nil}
        var r=record;r.units=n
        if r.kind=="sale" {
            guard let f=finamiTokenUnits(fee),let u=bankMinor(received),u>0,let orderValue=order.isEmpty ? Int64(0):bankMinor(order),orderValue>=0 else{return nil}
            r.fee=f;r.receivedUAH=u;r.orderUAH=orderValue;r.linkedReceiptIDs=linked.isEmpty ? nil:linked.sorted()
        } else {r.fee=0;r.orderUAH=0;r.receivedUAH=0;r.rate="";r.feeIncluded=true;r.linkedReceiptIDs=nil}
        return finamiExchangeDebit(r) == nil ? nil:r
    }
    private var updated:[FinamiExchangeRecord]? {
        guard let candidate else{return nil}
        if let ids=candidate.linkedReceiptIDs,!ids.isEmpty {
            guard finamiExchangeReceiptTotal(ids:ids,operations:s.db.operations,accounts:s.db.accounts,date:candidate.date)==candidate.receivedUAH else{return nil}
        }
        let rows=(s.db.exchangeDiary ?? []).filter{$0.id != candidate.id}+[candidate]
        return finamiExchangeBalance(rows) == nil ? nil:rows
    }
    private var receipts:[Operation] {
        let used=Set((s.db.exchangeDiary ?? []).filter{$0.id != record.id}.flatMap{$0.linkedReceiptIDs ?? []})
        return s.db.operations.filter { o in
            !used.contains(o.id) && finamiExchangeReceipt(o,accounts:s.db.accounts,date:record.date) != nil && !s.db.accounts.contains{ a in a.hideAmounts == true && (a.id==o.account || a.id==o.destination) }
        }.sorted{$0.date<$1.date}
    }
    private var receiptSection:some View {
        Section("Звірка банківських надходжень") {
            Text("Необов’язково. Вибери фактичні гривневі зарахування за сусідні дні. Вони лише пов’язуються з ордером і не створюються повторно. Приховані рахунки не пропонуються.").font(.caption)
            if !linked.isEmpty {
                let total=finamiExchangeReceiptTotal(ids:linked.sorted(),operations:s.db.operations,accounts:s.db.accounts,date:record.date)
                LabeledContent("Вибрано: \(linked.count)",value:total.map{s.visibleMoney($0)} ?? "Потребує звірки")
                Button("Очистити зв’язки") {linked.removeAll()}
            }
            if receipts.isEmpty {Text("Немає доступних банківських рядків").font(.caption).foregroundStyle(.secondary)}
            ForEach(receipts) {o in
                Toggle(isOn:Binding(get:{linked.contains(o.id)},set:{v in if v {linked.insert(o.id)}else{linked.remove(o.id)}})) {
                    VStack(alignment:.leading){Text(s.accountName(o.kind == .transfer ? o.destination:o.account));Text(o.date.formatted(date:.abbreviated,time:.shortened)+" · "+s.visibleMoney(finamiExchangeReceipt(o,accounts:s.db.accounts,date:record.date) ?? 0)).font(.caption).foregroundStyle(.secondary)}
                }
            }
        }
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("Запис") {
                    Picker("Тип",selection:$record.kind){Text("Надходження").tag("income");Text("Продаж").tag("sale")}
                    DatePicker("Дата та час",selection:$record.date,in:...Date())
                    FinamiField("Сума USDT",text:$units,keyboard:.decimalPad)
                    TextField("Примітка",text:$record.note)
                }
                if record.kind=="sale" {
                    Section("Обмін") {
                        FinamiField("Комісія USDT",text:$fee,keyboard:.decimalPad)
                        Toggle("Комісія всередині суми",isOn:$record.feeIncluded)
                        FinamiField("Курс ордера, грн/USDT",text:$record.rate,keyboard:.decimalPad)
                        FinamiField("Сума ордера UAH (необов’язково)",text:$order,keyboard:.decimalPad)
                        FinamiField("Фактично отримано UAH",text:$received,keyboard:.decimalPad)
                        if let r=candidate,let debit=finamiExchangeDebit(r) {
                            LabeledContent("Списано з біржі",value:finamiTokenText(debit)+" USDT")
                            LabeledContent("Продано без комісії",value:finamiTokenText(debit-r.fee)+" USDT")
                            if r.orderUAH>0 {LabeledContent("Різниця з ордером",value:money(r.receivedUAH-r.orderUAH))}
                        }
                        Text("Фактично отримана сума має пріоритет. Різниця з ордером не є автоматично комісією.").font(.caption)
                    }
                }
                if record.kind=="sale" {receiptSection}
                if updated==nil {Text("Перевір суми, курс, залишок USDT і суму вибраних зарахувань.").font(.caption).foregroundStyle(.orange)}
            }.navigationTitle("USDT").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Зберегти"){if let updated,s.change({$0.exchangeDiary=updated}){dismiss()}}.disabled(updated==nil)}
            }
        }
    }
}

struct FinamiPartnerCalculatorView:View {
    @EnvironmentObject private var s:Store
    @State private var editing:FinamiPartnerGroup?
    @State private var deleting:FinamiPartnerGroup?
    @State private var confirm=false
    private var groups:[FinamiPartnerGroup] {s.db.partnerGroups ?? []}
    var body:some View {
        List {
            Section {
                Text("Групуй договори одного кредитного партнера. Група — представлення наявних розстрочок, а не ще один борг у загальній сумі. Передоплата окремо до фактичного погашення.").font(.caption)
                Button {editing=FinamiPartnerGroup()} label:{Label("Новий спільний ліміт",systemImage:"plus.circle")}
            }
            ForEach(groups) {g in
                let rows=s.db.obligations.filter{$0.kind == .installment && g.obligationIDs.contains($0.id)}
                let position=finamiPartnerPosition(limit:g.limit,balances:rows.map(\.remaining),prepaid:g.prepaid)
                Section(g.name) {
                    LabeledContent("Ліміт",value:s.visibleMoney(g.limit))
                    LabeledContent("Залишок договорів",value:position.map{s.visibleMoney($0.used)} ?? "—")
                    LabeledContent("Доступно",value:rows.count==g.obligationIDs.count ? (position.map{s.visibleMoney($0.available)} ?? "—") : "Потрібна звірка")
                    LabeledContent("Баланс для оплати",value:s.visibleMoney(g.prepaid))
                    if rows.count != g.obligationIDs.count {Text("Один або кілька договорів видалено. Перевір групу.").font(.caption).foregroundStyle(.orange)}
                    ForEach(rows) {o in LabeledContent(o.name,value:s.visibleMoney(o.remaining))}
                    Button("Редагувати") {editing=g}
                    Button("Видалити групу",role:.destructive){deleting=g;confirm=true}
                }
            }
        }.navigationTitle("Спільні кредитні ліміти").sheet(item:$editing){FinamiPartnerEditor(group:$0)}
         .confirmationDialog("Видалити групу? Договори залишаться.",isPresented:$confirm,titleVisibility:.visible) {
             Button("Видалити",role:.destructive){if let deleting {s.change{$0.partnerGroups=groups.filter{$0.id != deleting.id}}}}
         }
    }
}
private struct FinamiPartnerEditor:View {
    @EnvironmentObject private var s:Store
    @Environment(\.dismiss) private var dismiss
    @State private var group:FinamiPartnerGroup
    @State private var limit:String
    @State private var prepaid:String
    @State private var selected:Set<String>
    init(group:FinamiPartnerGroup) {
        _group=State(initialValue:group)
        _limit=State(initialValue:group.limit==0 ? "" : amountText(group.limit))
        _prepaid=State(initialValue:amountText(group.prepaid))
        _selected=State(initialValue:Set(group.obligationIDs))
    }
    private var candidates:[Obligation] {
        let used=Set((s.db.partnerGroups ?? []).filter{$0.id != group.id}.flatMap(\.obligationIDs))
        return s.db.obligations.filter{$0.kind == .installment && !used.contains($0.id)}
    }
    private var updated:[FinamiPartnerGroup]? {
        guard let cap=bankMinor(limit),cap>0,let advance=bankMinor(prepaid),advance>=0 else{return nil}
        var value=group;value.limit=cap;value.prepaid=advance;value.name=value.name.trimmingCharacters(in:.whitespacesAndNewlines)
        value.obligationIDs=selected.intersection(Set(candidates.map(\.id))).sorted()
        let next=(s.db.partnerGroups ?? []).filter{$0.id != group.id}+[value]
        return finamiValidPartnerGroups(next) ? next:nil
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("Параметри ліміту UAH") {
                    TextField("Назва партнера",text:$group.name)
                    FinamiField("Ліміт",text:$limit,keyboard:.decimalPad)
                    FinamiField("Окремий баланс для оплати",text:$prepaid,keyboard:.decimalPad)
                }
                Section("Договори") {
                    Text("Договір може належати лише одній групі. Нульовий поточний платіж не означає відсутність залишку боргу.").font(.caption)
                    ForEach(candidates) {o in
                        Toggle(isOn:Binding(get:{selected.contains(o.id)},set:{value in if value {selected.insert(o.id)} else {selected.remove(o.id)}})) {
                            VStack(alignment:.leading){Text(o.name);Text(s.visibleMoney(o.remaining)).font(.caption).foregroundStyle(.secondary)}
                        }
                    }
                }
            }.navigationTitle("Кредитний партнер").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Зберегти"){if let updated,s.change({$0.partnerGroups=updated}){dismiss()}}.disabled(updated==nil)}
            }
        }
    }
}

struct FinamiPositionHistoryView:View {
    @EnvironmentObject private var s:Store
    @State private var months=12
    @State private var result:[FinamiHistoricalPosition]=[]
    @State private var running=false
    @State private var version:UInt64?
    private func refresh() async {
        running=true
        let accounts=s.db.accounts,operations=s.db.operations,rate=s.currentRate,count=months,v=s.databaseVersion
        let ending=Date()
        let values=await Task.detached(priority:.userInitiated) {finamiHistoricalPositions(accounts:accounts,operations:operations,ending:ending,months:count,usdRate:rate)}.value
        if s.databaseVersion==v && count==months {result=values;version=v}
        running=false
    }
    var body:some View {
        List {
            Section("Розрахунок") {
                Picker("Місяців",selection:$months){Text("3").tag(3);Text("6").tag(6);Text("12").tag(12);Text("24").tag(24)}.pickerStyle(.segmented).onChange(of:months){_ in version=nil;result=[]}
                Text("Історична позиція рахунків за записами Finami. USD оцінено за одним поточним курсом; це не історичний курс. Початкові залишки можуть включатися до дат до фактичного відкриття рахунка, якщо дата відкриття невідома. Розстрочки й зовнішні зобов’язання тут окремо не віднімаються, щоб не подвоїти борг. Приховані та виключені рахунки не враховано.").font(.caption)
                Button("Розрахувати") {Task {await refresh()}}.disabled(running || s.privateAmounts)
                if running {ProgressView()}
                if s.privateAmounts {Text("Суми приховано.").font(.caption)}
                if let version,version != s.databaseVersion {Text("База змінилася. Повтори розрахунок.").foregroundStyle(.orange)}
            }
            if !s.privateAmounts,version==s.databaseVersion,!result.isEmpty {
                Section("Чиста позиція рахунків") {
                    Chart {ForEach(result){point in LineMark(x:.value("Дата",point.date),y:.value("UAH",Double(point.net)/100)).foregroundStyle(Color.accentColor)}}.frame(height:160)
                }
                ForEach(Array(result.reversed())) {point in
                    Section(monthName(point.date)) {
                        LabeledContent("Власні кошти",value:s.visibleMoney(point.own))
                        LabeledContent("Борг на рахунках",value:s.visibleMoney(point.debt))
                        LabeledContent("Чиста позиція",value:s.visibleMoney(point.net))
                        if point.omitted>0 {Text("Не враховано рахунків без курсу: \(point.omitted)").font(.caption).foregroundStyle(.orange)}
                    }
                }
            }
        }.navigationTitle("Історія рахунків")
    }
}
