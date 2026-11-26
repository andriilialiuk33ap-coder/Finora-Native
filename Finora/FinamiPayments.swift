import SwiftUI
import PhotosUI
import UIKit

struct FinamiPayment: Identifiable {
    var id:String; var name:String; var kind:String; var date:Date; var amount:Int64; var currency:String; var remaining:Int64?; var subscription:Bool
    var overdue:Bool { Calendar.current.startOfDay(for:date) < Calendar.current.startOfDay(for:Date()) }
}
extension Store {
    var upcomingPayments:[FinamiPayment] {
        let debts = db.obligations.filter { $0.remaining > 0 && [.installment,.owe,.recurring].contains($0.kind) }.map { o in FinamiPayment(id:o.id,name:o.name,kind:o.kind.title,date:o.due,amount:o.monthly > 0 ? min(o.monthly,o.remaining) : o.remaining,currency:"UAH",remaining:o.remaining,subscription:false) }
        let subs = (db.subscriptions ?? []).filter(\.active).map { r in FinamiPayment(id:r.id,name:r.name,kind:"Підписка",date:r.next,amount:r.amount,currency:r.currency,remaining:nil,subscription:true) }
        return (debts+subs).sorted { $0.date < $1.date }
    }
    func scheduledThisMonth(currency: String, now: Date = Date()) -> Int64 {
        let cal = Calendar.current
        guard let end = cal.dateInterval(of: .month, for: now)?.end else { return 0 }
        let start = cal.startOfDay(for: now)
        var total: Int64 = 0
        for p in upcomingPayments where p.currency == currency {
            let period = p.subscription ? db.subscriptions?.first(where: {$0.id == p.id})?.period : nil
            total += finamiScheduledAmounts(start:p.date, amount:p.amount, remaining:p.remaining, component:period?.component ?? .month, step:period?.step ?? 1, from:start, until:end, calendar:cal).reduce(0,+)
        }
        return total
    }
    // One atomic write advances the schedule, records the chosen account, and optionally adds a ledger entry.
    func confirmPayment(_ payment: FinamiPayment, mode: FinamiPaymentMode, accountID: String, operationID: String, paidDate: Date, kind: Kind, allowSeparate: Bool = false, operationDraft: Operation? = nil, learnCategory: Bool = false) -> Bool {
        guard let live=upcomingPayments.first(where:{$0.id==payment.id}),live.date==payment.date,live.amount==payment.amount,live.amount>0, live.currency == payment.currency, paidDate <= Date(), !(db.paidRecords ?? []).contains(where: { $0.paymentID == payment.id && $0.scheduledDate == payment.date }) else {error="Платіж уже змінено. Відкрий його знову.";return false}
        let account = db.accounts.first { $0.id == accountID && $0.code == payment.currency }
        let candidates = finamiEligiblePaymentOperations(db.operations, records: db.paidRecords ?? [], account: accountID, currency: payment.currency, amount: payment.amount, date: paidDate)
        let existing = candidates.first { $0.id == operationID }
        var newOperation: Operation?
        if let draft = operationDraft {
            guard mode == .newOperation, let account,
                  finamiPaymentDraftMatches(draft, account: account, currency: payment.currency, amount: payment.amount),
                  draft.date == paidDate,
                  !(db.paidRecords ?? []).contains(where: { $0.operationID == draft.id }),
                  draft.kind != .transfer || (draft.destination != draft.account && db.accounts.contains(where: { $0.id == draft.destination }) && (draft.destinationMinor ?? draft.amount) > 0) else {
                error = "Операція не відповідає вибраному платежу або вже прив’язана."; return false
            }
            guard db.operations.contains(where: { $0.id == draft.id }) || candidates.isEmpty || allowSeparate else {
                error = "Є схоже списання. Відкрий наявну операцію або підтвердь окрему оплату."; return false
            }
            newOperation = draft
        } else if mode == .newOperation {
            guard candidates.isEmpty || allowSeparate else { error = "Є схоже списання. Прив’яжи його або підтвердь, що це інша оплата."; return false }
            let category = payment.subscription ? "📺 Підписки" : payment.kind == "Розстрочка" ? "💳 Розстрочка" : "Без категорії"
            guard let account, let operation = finamiNewPaymentOperation(name: payment.name, account: account, currency: payment.currency, amount: payment.amount, date: paidDate, kind: kind, rate: currentRate, categories: db.expenseCategories, preferredCategory:category) else { error = "Перевір рахунок, валюту та курс."; return false }
            newOperation = operation
        } else if mode == .existing {
            guard account != nil, existing != nil else { error = "Операцію вже використано або вона не відповідає платежу."; return false }
        }
        let record = FinamiPaidRecord(paymentID: payment.id, scheduledDate: payment.date, paidDate: mode == .existing ? (existing?.date ?? paidDate) : paidDate, amount: payment.amount, currency: payment.currency, accountID: mode == .markOnly ? nil : accountID, operationID: mode == .newOperation ? newOperation?.id : mode == .existing ? existing?.id : nil)
        let previous=(db.reminders ?? []).filter{$0.linkedID==payment.id}
        var renewed:[PersonalReminder]=[]
        let ok=change { d in
            var next:Date?=nil
            if payment.subscription,let i=d.subscriptions?.firstIndex(where:{$0.id==payment.id}),var r=d.subscriptions?[i] {
                let end=Calendar.current.date(byAdding:r.period.component,value:r.period.step,to:r.next) ?? r.next
                r.payments.append(.init(date:record.paidDate,amount:payment.amount,currency:payment.currency,through:end));r.next=end;d.subscriptions?[i]=r;next=end
            } else if let i=d.obligations.firstIndex(where:{$0.id==payment.id}) {
                guard finamiAdvanceObligation(&d.obligations[i], scheduled: payment.date, amount: payment.amount) else { return }
                if d.obligations[i].remaining>0 {next=d.obligations[i].due}
            } else { return }
            if let newOperation {
                d.operations.removeAll { $0.id == newOperation.id }
                d.operations.append(newOperation)
                if learnCategory && (newOperation.kind == .expense || newOperation.kind == .income) && !newOperation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var rules = d.merchantRules ?? [:]; rules[ruleKey(newOperation.note, kind: newOperation.kind)] = newOperation.category; d.merchantRules = rules
                }
            }
            d.paidRecords = (d.paidRecords ?? []) + [record]
            d.reminders?.removeAll{$0.linkedID==payment.id}
            if let next=next { for r in previous { var copy=r;copy.date=next.addingTimeInterval(r.date.timeIntervalSince(payment.date)); if copy.date>Date() {renewed.append(copy)} };d.reminders=(d.reminders ?? [])+renewed }
        }
        guard ok, (db.paidRecords ?? []).contains(where: { $0.id == record.id }) else { return false }
        if ok {previous.forEach{ReminderScheduler.cancel($0)};let scheduled=renewed;Task { @MainActor in for r in scheduled { do {try await ReminderScheduler.schedule(r)} catch {self.error="Платіж збережено. Нагадування: "+error.localizedDescription} } }}
        return ok
    }
}
struct FinamiPaymentCard:View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var payment:FinamiPayment
    var showRemaining = true
    var showDate = true
    var showImage = true
    var dashboardSize: DashboardSize? = nil
    var body:some View { VStack(alignment:.leading,spacing:dashboardSize == .small ? 5 : dashboardSize == .large ? 16 : 10) {
        HStack(alignment:.top) { VStack(alignment:.leading,spacing:5) { Text(payment.kind).font(.caption).foregroundStyle(.secondary);Text(payment.name).font(.headline).fixedSize(horizontal:false,vertical:true) };Spacer(minLength:8);if showImage && dashboardSize != .small { if let data=s.db.paymentPhotos?[payment.id],let image=FinamiImageCache.shared.image(data) {Image(uiImage:image).resizable().scaledToFill().frame(width:62,height:62).clipShape(RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)}else{FinamiArt(icon:payment.subscription ? "repeat" : "calendar.badge.clock",tint:.indigo,size:62)} } }
        Text(masked ? "••••" : s.visibleMoney(payment.amount,payment.currency)).font(dashboardSize == .small ? .title3.bold() : dashboardSize == .medium ? .title.bold() : .largeTitle.bold()).monospacedDigit().fixedSize(horizontal:false,vertical:true)
        if showDate { Label(payment.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier:"uk_UA"))),systemImage:"calendar").foregroundStyle(payment.overdue ? Color.orange : Color.secondary) }
        if payment.overdue {Label("Прострочено",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)}
        if showRemaining, let remaining=payment.remaining {FinamiMetric(title:"Залишок",value:masked ? "••••" : s.visibleMoney(remaining))}
        HStack {Text("Деталі платежу").font(.subheadline.weight(.medium));Spacer();Image(systemName:"chevron.right")}.foregroundStyle(.tint)
    }.padding(dashboardSize == .small ? 6 : dashboardSize == .large ? 20 : 14).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.indigo)) }
}
struct FinamiMonthPayments:View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var dashboardSize: DashboardSize? = nil
    var body:some View { VStack(alignment:.leading,spacing:dashboardSize == .small ? 4 : dashboardSize == .large ? 12 : 8) {if dashboardSize != .small { Text("Заплановано до кінця місяця").font(.headline) };ForEach(["UAH","USD"],id:\.self) { currency in let total=s.scheduledThisMonth(currency:currency); if total>0 || currency=="UAH" {Text(masked ? "••••" : s.visibleMoney(total,currency)).font(dashboardSize == .small ? .title3.bold() : dashboardSize == .large ? .largeTitle.bold() : .title.bold()).monospacedDigit()} };if dashboardSize != .small { Text("Прогноз за графіком; прострочені платежі показано окремо.").font(.caption).foregroundStyle(.secondary) } }.padding(dashboardSize == .small ? 6 : dashboardSize == .large ? 20 : 14).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.indigo)) }
}
struct FinamiPaymentDetails:View {
    @EnvironmentObject var s:Store; @Environment(\.dismiss) var dismiss
    var payment:FinamiPayment
    @State private var photo:PhotosPickerItem?
    @State private var confirm=false
    @State private var paymentSaved=false
    @State private var photoLoading=false
    var body:some View { NavigationStack { Form {
        Section {FinamiPaymentCard(payment:payment)}
        Section("Керування") {
            Button {confirm=true} label: { Label("Сплатив з картки / рахунку", systemImage:"creditcard.fill") }.accessibilityIdentifier("qa.payment.pay")
            if payment.subscription,let r=s.db.subscriptions?.first(where:{$0.id==payment.id}) {NavigationLink("Редагувати підписку") {SubscriptionEditor(original:r)}}
            else if let o=s.db.obligations.first(where:{$0.id==payment.id}) {NavigationLink("Редагувати платіж / дату") {ObligationEditor(original:o)}}
            PhotosPicker(selection:$photo,matching:.images) {Label("Вибрати фотографію",systemImage:"photo")}.disabled(photoLoading)
            if photoLoading { ProgressView("Обробка фото…") }
            if s.db.paymentPhotos?[payment.id] != nil {Button("Видалити фотографію",role:.destructive){s.change{$0.paymentPhotos?.removeValue(forKey:payment.id)}}}
        }
        if !(s.db.paidRecords ?? []).filter({$0.paymentID == payment.id}).isEmpty {
            Section("Історія оплат") {
                ForEach((s.db.paidRecords ?? []).filter{$0.paymentID == payment.id}.sorted{$0.paidDate > $1.paidDate}) { record in
                    VStack(alignment:.leading, spacing:4) { Text(s.visibleMoney(record.amount,record.currency)).bold(); Text(record.paidDate.formatted(date:.abbreviated,time:.omitted) + " · " + (record.accountID.map{s.accountName($0)} ?? "Без списання")).font(.caption); if let id = record.operationID, !s.db.operations.contains(where:{$0.id == id}) { Text("Пов’язану операцію видалено").font(.caption).foregroundStyle(.orange) } }
                }
            }
        }
        Section("Нагадування") {
            ForEach((s.db.reminders ?? []).filter{$0.linkedID==payment.id}) {r in NavigationLink {ReminderEditor(original:r)} label:{Label(r.date.formatted(date:.abbreviated,time:.shortened),systemImage:r.enabled ? "bell.fill" : "bell.slash")}}
            .onDelete { offsets in let all=(s.db.reminders ?? []).filter{$0.linkedID==payment.id};let ids=offsets.map{all[$0]};if s.change({d in d.reminders?.removeAll{r in ids.contains{$0.id==r.id}}}){ids.forEach{ReminderScheduler.cancel($0)}} }
            NavigationLink {ReminderEditor(original:.init(title:payment.name,date:max(Date().addingTimeInterval(3600),payment.date.addingTimeInterval(-86400)),linkedID:payment.id,hideDetails:true))} label:{Label("Додати нагадування",systemImage:"bell.badge")}
            Text("Можна створити кілька нагадувань із власними датою та часом.").font(.caption)
        }
    }.navigationTitle("Деталі платежу").toolbar{ToolbarItem(placement:.cancellationAction){Button("Готово"){dismiss()}}}.sheet(isPresented:$confirm,onDismiss:{if paymentSaved {dismiss()}}) { FinamiPaymentCheckout(payment:payment,onComplete:{paymentSaved=true;confirm=false}) }
        .onChange(of:photo) { item in
            guard let item, !photoLoading else {return};photoLoading=true
            Task { @MainActor in
                defer { photoLoading=false;photo=nil }
                guard let data=try? await item.loadTransferable(type:Data.self),
                      let jpeg=await Task.detached(priority:.userInitiated, operation:{finamiThumbnailJPEG(data,maxPixels:800)}).value else {s.error="Не вдалося обробити фото.";return}
                s.change { d in var all=d.paymentPhotos ?? [:];all[payment.id]=jpeg;d.paymentPhotos=all }
            }
        }
    } }
}

struct FinamiPaymentCheckout: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    let payment: FinamiPayment
    let onComplete: () -> Void
    @State private var accountID = ""
    @State private var selectedMode = ""
    @State private var selectedOperation = ""
    @State private var paidDate = Date()
    @State private var paymentKind = Kind.creditRepayment
    @State private var acceptNew = false
    private var mode: FinamiPaymentMode? { FinamiPaymentMode(rawValue:selectedMode) }
    private var accounts: [Account] { s.db.accounts.filter { $0.code == payment.currency } }
    private var candidates: [Operation] { finamiEligiblePaymentOperations(s.db.operations, records:s.db.paidRecords ?? [], account:accountID, currency:payment.currency, amount:payment.amount, date:paidDate) }
    private var valid: Bool {
        guard let mode else { return false }
        if mode == .markOnly { return true }
        guard accounts.contains(where:{$0.id==accountID}) else { return false }
        if mode == .existing { return candidates.contains(where:{$0.id==selectedOperation}) }
        return (payment.currency != "USD" || s.currentRate != nil) && (candidates.isEmpty || acceptNew)
    }
    var body: some View {
        NavigationStack { Form {
            Section { LabeledContent("Платіж",value:payment.name); LabeledContent("Сума",value:s.visibleMoney(payment.amount,payment.currency)); DatePicker("Дата оплати",selection:$paidDate,in:...Date(),displayedComponents:.date) }
            Section("Звідки сплачено") {
                Picker("Рахунок", selection:$accountID) { Text("Обрати рахунок").tag(""); ForEach(accounts) { a in Text(a.name + (a.lastFour.map { " ••" + $0 } ?? "")).tag(a.id) } }.accessibilityIdentifier("qa.payment.account")
                if let a = accounts.first(where:{$0.id == accountID}), mode != .existing { LabeledContent("Доступно",value:a.hideAmounts == true ? "••••" : s.visibleMoney(s.available(a),a.code)); if s.available(a) < payment.amount { Text("Доступного залишку недостатньо за даними Finami. Перевір фактичну оплату.").foregroundStyle(.orange).font(.caption) } }
                Picker("Як записати",selection:$selectedMode) { Text("Обрати спосіб").tag(""); ForEach(FinamiPaymentMode.allCases) { Text($0.rawValue).tag($0.rawValue) } }.accessibilityIdentifier("qa.payment.mode")
                if mode == .existing { Picker("Операція",selection:$selectedOperation) { Text("Обрати існуючу").tag(""); ForEach(candidates) { o in Text(o.note + " · " + o.date.formatted(date:.abbreviated,time:.shortened)).tag(o.id) } }; if candidates.isEmpty { Text("Немає відповідних списань на цьому рахунку за 7 днів до/після вибраної дати.").font(.caption) } }
                if mode == .newOperation {
                    Picker("Тип списання",selection:$paymentKind) { Text("Витрата").tag(Kind.expense); Text("Погашення кредиту / боргу").tag(Kind.creditRepayment) }
                    Text("Обери погашення, якщо покупку вже враховано як витрату. Це не повторює витрату у звітах.").font(.caption).foregroundStyle(.secondary)
                    if !candidates.isEmpty { Toggle("Це нова окрема операція",isOn:$acceptNew); Text("Знайдено схоже списання. Краще обрати «Вже є в операціях», якщо це та сама оплата.").font(.caption).foregroundStyle(.orange) }
                }
                if mode == .markOnly { Text("Зміниться лише графік і залишок. Баланс картки не зміниться.").font(.caption) }
            }
            Section { Button("Підтвердити оплату") { guard let mode, valid else {return}; if s.confirmPayment(payment,mode:mode,accountID:accountID,operationID:selectedOperation,paidDate:paidDate,kind:paymentKind,allowSeparate:acceptNew) {onComplete()} }.disabled(!valid).accessibilityIdentifier("qa.payment.confirm"); Text("Finami записує фактичну оплату в облік, але не здійснює банківський платіж.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Записати оплату").toolbar { ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}} }
        .onAppear { paymentKind = payment.subscription || payment.kind == "Регулярний платіж" ? .expense : .creditRepayment }
        .onChange(of:accountID) { _ in selectedOperation="";acceptNew=false }
        .onChange(of:paidDate) { _ in selectedOperation="";acceptNew=false }
        }
    }
}
