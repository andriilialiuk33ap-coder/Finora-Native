import SwiftUI
import UserNotifications

struct SubscriptionsView: View {
    @EnvironmentObject var s: Store; @State private var edit: SubscriptionRecord?
    @State private var subscriptionFilter = "all"
    var list: [SubscriptionRecord] { (s.db.subscriptions ?? []).sorted{$0.next < $1.next} }
    var body: some View {
        List {
            Section { NavigationLink("Виявити підписки за операціями") { FinamiRecurringSuggestionsView() } }
            Section("Активні") { ForEach(["UAH","USD"], id: \.self) { currency in let active = list.filter{$0.active && $0.currency == currency}; if !active.isEmpty { let total = active.reduce(0.0) { n,r in n + Double(r.amount) * (r.period == .week ? 52.0/12 : r.period == .year ? 1.0/12 : 1) }; LabeledContent("Місячна оцінка \(currency)", value: (!s.privateAmounts && (s.db.preferences?.designHiddenSubscriptions ?? []).isEmpty) ? s.visibleMoney(FinamiDesignPolicy.safeMinor(total),currency) : "••••") } } }
            if s.db.preferences?.designStyle(for: "subscriptions") == "subscriptionPro" {
                Section("Річна оцінка") { ForEach(["UAH", "USD"], id: \.self) { code in
                    let active = list.filter { $0.active && $0.currency == code }
                    if !active.isEmpty { LabeledContent(code, value: (s.privateAmounts || active.contains { (s.db.preferences?.designHiddenSubscriptions ?? []).contains($0.id) }) ? "••••" : s.visibleMoney(FinamiDesignPolicy.safeMinor(active.reduce(0.0) { $0 + Double($1.amount) * FinamiDesignPolicy.annualFactor($1.period.rawValue) }),code)) }
                } }
            }
            Picker("Стан", selection: $subscriptionFilter) { Text("Усі").tag("all"); Text("Активні").tag("active"); Text("На паузі").tag("paused") }.pickerStyle(.segmented)
            ForEach(list.filter { subscriptionFilter == "all" || (subscriptionFilter == "active" ? $0.active : !$0.active) }) { r in
                let collapsed = s.db.preferences?.isDesignCardCollapsed(r.id, subscription: true) ?? false
                HStack(spacing: 4) {
                    Button { edit = r } label: {
                        FinamiSubscriptionDesign(record: r, collapsed: collapsed)
                    }.buttonStyle(.plain)
                    Button { s.changeAppearance { p in var ids = Set(p.designHiddenSubscriptions ?? []); if ids.contains(r.id) { ids.remove(r.id) } else { ids.insert(r.id) }; p.designHiddenSubscriptions = ids.sorted() } } label: { Image(systemName: (s.db.preferences?.designHiddenSubscriptions ?? []).contains(r.id) ? "eye.slash" : "eye").frame(minWidth:44,minHeight:44) }.buttonStyle(.borderless).accessibilityLabel("Видимість суми підписки")
                    Button { s.changeAppearance { $0.toggleDesignCard(r.id, subscription: true) } } label: {
                        Image(systemName:collapsed ? "chevron.down" : "chevron.up").frame(minWidth:44,minHeight:44)
                    }.buttonStyle(.borderless).accessibilityLabel(collapsed ? "Розгорнути підписку" : "Згорнути підписку").accessibilityIdentifier("qa.subscription.collapse." + r.id)
                }
            }
        }.navigationTitle("Підписки").toolbar { Button { edit = SubscriptionRecord() } label: { Image(systemName:"plus.circle.fill").font(.title2) } }.sheet(item:$edit){ SubscriptionEditor(original:$0) }
    }
}
struct SubscriptionEditor: View {
    @Environment(\.finamiMask) private var masked
    @EnvironmentObject var s: Store; @Environment(\.dismiss) var dismiss
    @State var r: SubscriptionRecord; @State var amount: String; @State private var payment = ""; @State private var paidDate = Date(); @State private var confirm = false
    init(original: SubscriptionRecord) { _r = State(initialValue:original); _amount = State(initialValue:amountText(original.amount)) }
    var valid: Bool { !r.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && (cents(amount) ?? 0)>0 }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Назва сервісу",text:$r.name)
                FinamiField("Тариф", text: $amount, keyboard: .decimalPad)
                Picker("Валюта",selection:$r.currency){Text("UAH").tag("UAH");Text("USD").tag("USD")}
                Picker("Період",selection:$r.period){ForEach(SubscriptionPeriod.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                DatePicker("Наступна оплата",selection:$r.next,displayedComponents:.date)
                Toggle("Активна",isOn:$r.active); Toggle("Автосписання в сервісі",isOn:$r.automatic)
                TextField("Примітка",text:$r.notes)
                Section("Оформлення") {
                    Picker("Іконка", selection: Binding(get: { s.db.preferences?.designSubscriptionIcons?[r.id] ?? "auto" }, set: { v in s.changeAppearance { p in var values = p.designSubscriptionIcons ?? [:]; values[r.id] = v; p.designSubscriptionIcons = values } })) {
                        Text("Автоматично").tag("auto")
                        ForEach(["repeat", "tv", "music.note", "cloud", "play.rectangle", "gamecontroller", "book", "star"], id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                    Picker("Колір", selection: Binding(get: { s.db.preferences?.designSubscriptionColors?[r.id] ?? "auto" }, set: { v in s.changeAppearance { p in var values = p.designSubscriptionColors ?? [:]; values[r.id] = v; p.designSubscriptionColors = values } })) {
                        Text("Автоматично").tag("auto")
                        ForEach(FinamiDesignPolicy.accents, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Історія оплат") {
                    ForEach(r.payments.sorted{$0.date > $1.date}) { p in VStack(alignment:.leading){Text(masked || (s.db.preferences?.designHiddenSubscriptions ?? []).contains(r.id) ? "••••" : s.visibleMoney(p.amount,p.currency)).bold();Text("Сплачено: \(p.date.formatted(date:.abbreviated,time:.omitted)) · До: \(p.through.formatted(date:.abbreviated,time:.omitted))").font(.caption)} }
                    DatePicker("Дата фактичної оплати",selection:$paidDate,displayedComponents:.date)
                    FinamiField("Фактична сума (необов’язково)", text: $payment, keyboard: .decimalPad)
                    Button("Записати оплату") { guard let n = cents(payment.isEmpty ? amount : payment), n > 0 else { return }; let base = max(r.next,paidDate); let end = Calendar.current.date(byAdding:r.period.component,value:r.period.step,to:base) ?? base; r.payments.append(.init(date:paidDate,amount:n,currency:r.currency,through:end));r.next=end;payment="" }.disabled(!valid || (!payment.isEmpty && (cents(payment) ?? 0)<=0))
                    Text("Історія підписки не додає витрати в рахунок автоматично, щоб не подвоїти банківську операцію.").font(.caption)
                }
                if s.db.subscriptions?.contains(where:{$0.id == r.id}) == true {
                    NavigationLink("Додати нагадування") { ReminderEditor(original:.init(title:r.name,date:r.next,linkedID:r.id)) }
                    Button("Видалити підписку",role:.destructive){confirm=true}
                }
            }.navigationTitle("Підписка").toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Зберегти"){guard let n=cents(amount),valid else{return};r.amount=n;if s.change({d in var all=d.subscriptions ?? [];all.removeAll{$0.id == r.id};all.append(r);d.subscriptions=all}){dismiss()}}.disabled(!valid)}
            }.confirmationDialog("Видалити підписку?",isPresented:$confirm){Button("Видалити",role:.destructive){let linked=(s.db.reminders ?? []).filter{$0.linkedID == r.id};if s.change({d in d.subscriptions?.removeAll{$0.id == r.id};d.reminders?.removeAll{$0.linkedID == r.id}}){linked.forEach{ReminderScheduler.cancel($0)};dismiss()}}}
        }
    }
}

