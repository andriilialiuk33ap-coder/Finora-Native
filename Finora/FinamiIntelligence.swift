import SwiftUI

@MainActor extension Store {
    var recurringPriceChanges: [FinamiRecurringCandidate] {
        let candidates = finamiRecurringCandidates(operations: db.operations, accounts: db.accounts)
        return candidates.filter { candidate in
            let matches = (db.subscriptions ?? []).filter { $0.active && $0.currency == candidate.currency && finamiMerchantKey($0.name) == finamiMerchantKey(candidate.merchant) }
            guard matches.count == 1, let record = matches.first, record.amount > 0,
                  candidates.filter({ $0.currency == candidate.currency && finamiMerchantKey($0.merchant) == finamiMerchantKey(candidate.merchant) }).count == 1 else { return false }
            return candidate.amount > record.amount && Double(candidate.amount - record.amount) / Double(record.amount) >= 0.05
        }
    }
    var recurringSuggestions: [FinamiRecurringCandidate] {
        let existing = Set((db.subscriptions ?? []).map { finamiMerchantKey($0.name) })
        let obligations = Set(db.obligations.filter { $0.kind == .recurring || $0.kind == .installment }.map { finamiMerchantKey($0.name) })
        let dismissed = Set(db.dismissedRecurringSuggestions ?? [])
        return finamiRecurringCandidates(operations: db.operations, accounts: db.accounts).filter {
            !existing.contains(finamiMerchantKey($0.merchant)) && !obligations.contains(finamiMerchantKey($0.merchant)) && !dismissed.contains($0.id)
        }
    }
    func acceptRecurringSuggestion(_ suggestion: FinamiRecurringCandidate) -> Bool {
        guard recurringSuggestions.contains(where: { $0 == suggestion }) else { error = "Пропозиція змінилася. Онови список."; return false }
        return change { d in
            let record = SubscriptionRecord(name: suggestion.merchant, amount: suggestion.amount, currency: suggestion.currency, period: suggestion.cadence == "week" ? .week : .month, next: suggestion.next, active: true, automatic: false, notes: "Виявлено за історією оплат; перевір тариф і наступну дату.")
            d.subscriptions = (d.subscriptions ?? []) + [record]
            d.dismissedRecurringSuggestions = (d.dismissedRecurringSuggestions ?? []) + [suggestion.id]
        }
    }
}
struct FinamiRecurringSuggestionsView: View {
    @EnvironmentObject private var s: Store
    @State private var selected: FinamiRecurringCandidate?
    var body: some View {
        let suggestions = s.recurringSuggestions
        List {
            Section { Text("Finami шукає щонайменше три повторювані списання одного продавця на одному рахунку. Це лише пропозиції: гроші не списуються, історія не змінюється.").font(.caption).foregroundStyle(.secondary) }
            Section("Знайдено: \(suggestions.count)") {
                if suggestions.isEmpty { Text("Поки немає нових пропозицій.").foregroundStyle(.secondary).accessibilityIdentifier("qa.recurring.empty") }
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.merchant).font(.headline)
                        Text(s.accountName(suggestion.account) + " · " + (suggestion.cadence == "week" ? "Щотижня" : "Щомісяця")).font(.caption).foregroundStyle(.secondary)
                        Text(s.db.accounts.first(where: {$0.id == suggestion.account})?.hideAmounts == true ? "••••" : s.visibleMoney(suggestion.amount, suggestion.currency)).font(.title3.bold())
                        Text("Наступна орієнтовна дата: " + suggestion.next.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))).font(.caption)
                        if suggestion.changedPrice { Label("Можлива зміна тарифу", systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.caption) }
                        HStack {
                            Button("Додати підписку") { selected = suggestion }.buttonStyle(.borderedProminent).accessibilityIdentifier("qa.recurring.accept")
                            Button("Пропустити") { s.change { d in d.dismissedRecurringSuggestions = Array(Set((d.dismissedRecurringSuggestions ?? []) + [suggestion.id])).sorted() } }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 5)
                }
            }
            if !(s.db.dismissedRecurringSuggestions ?? []).isEmpty { Button("Повернути пропущені пропозиції") { s.change { $0.dismissedRecurringSuggestions = [] } } }
        }.navigationTitle("Виявлення підписок").alert("Додати підписку?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("Додати") { if let selected { _ = s.acceptRecurringSuggestion(selected) }; selected = nil }
            Button("Скасувати", role: .cancel) { selected = nil }
        } message: { Text("Буде створено лише графік. Існуючі операції залишаться без змін. Тариф і дату можна відредагувати.") }
    }
}

struct FinamiCalendarEvent: Identifiable {
    let id: String
    let paymentID: String
    let date: Date
    let name: String
    let currency: String
    let amount: Int64
    let kind: String
    let projected: Bool
    let paid: Bool
    let payment: FinamiPayment?
    var tint: Color { paid ? .green : kind == "Підписка" ? .purple : kind == ObligationKind.installment.title ? .blue : .teal }
}
@MainActor extension Store {
    func calendarEvents(interval: DateInterval) -> [FinamiCalendarEvent] {
        var events: [FinamiCalendarEvent] = []
        for p in upcomingPayments {
            let period = p.subscription ? db.subscriptions?.first(where: { $0.id == p.id })?.period : nil
            for row in finamiPlannedOccurrences(id: p.id, start: p.date, amount: p.amount, remaining: p.remaining, subsequentAmount: p.recurringAmount, component: period?.component ?? .month, step: period?.step ?? 1, interval: interval) {
                events.append(.init(id: row.id, paymentID: p.id, date: row.date, name: p.name, currency: p.currency, amount: row.amount, kind: p.kind, projected: row.projected, paid: false, payment: row.projected ? nil : p))
            }
        }
        for r in db.paidRecords ?? [] where r.paidDate >= interval.start && r.paidDate < interval.end {
            let sub = db.subscriptions?.first { $0.id == r.paymentID }
            let obligation = db.obligations.first { $0.id == r.paymentID }
            let name = sub?.name ?? obligation?.name ?? "Архівний платіж"
            events.append(.init(id: "paid-" + r.id, paymentID: r.paymentID, date: r.paidDate, name: name, currency: r.currency, amount: r.amount, kind: sub != nil ? "Підписка" : obligation?.kind.title ?? "Платіж", projected: false, paid: true, payment: nil))
        }
        return events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
struct FinamiCalendarGrid: View {
    @EnvironmentObject private var s: Store
    var compact = false
    var masked = false
    @State private var month = Date()
    @State private var selected = Date()
    @State private var payment: FinamiPayment?
    @State private var filter = "all"
    @State private var status = "all"
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.locale = Locale(identifier: "uk_UA"); c.firstWeekday = 2; c.timeZone = .current; return c }
    private func show(_ value: Int64, _ currency: String) -> String { masked ? "••••" : s.visibleMoney(value, currency) }
    private func move(_ step: Int) { if let next = cal.date(byAdding: .month, value: step, to: cal.dateInterval(of: .month, for: month)?.start ?? month) { month = next; selected = next } }
    var body: some View {
        let interval = cal.dateInterval(of: .month, for: month)!
        let events = s.calendarEvents(interval: interval).filter { event in
            (filter == "all" || event.kind == filter) && (status == "all" || (status == "paid" ? event.paid : !event.paid))
        }
        let offset = (cal.component(.weekday, from: interval.start) + 5) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let cells = ((count + offset + 6) / 7) * 7
        let overdue = s.upcomingPayments.filter { $0.overdue && (filter == "all" || $0.kind == filter) && status != "paid" }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Попередній місяць")
                Spacer(); Text(monthName(month).capitalized).font(.headline); Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Наступний місяць")
            }.buttonStyle(.plain)
            if !compact {
                HStack {
                    Picker("Тип",selection:$filter) { Text("Усі типи").tag("all"); Text("Розстрочки").tag(ObligationKind.installment.title); Text("Підписки").tag("Підписка"); Text("Регулярні").tag(ObligationKind.recurring.title); Text("Борги").tag(ObligationKind.owe.title) }
                    Picker("Стан",selection:$status) { Text("Усі стани").tag("all"); Text("Очікуються").tag("open"); Text("Сплачено").tag("paid") }
                }.pickerStyle(.menu).font(.caption)
            }
            ForEach(Array(Set(events.filter { !$0.paid }.map(\.currency))).sorted(), id: \.self) { code in
                LabeledContent("Заплановано", value: show(events.filter { !$0.paid && $0.currency == code }.reduce(0) { $0 + $1.amount }, code)).font(.caption)
            }
            if !compact {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                    ForEach(["Пн","Вт","Ср","Чт","Пт","Сб","Нд"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                    ForEach(0..<cells, id: \.self) { index in
                        let day = index - offset + 1
                        if day >= 1 && day <= count, let date = cal.date(byAdding: .day, value: day-1, to: interval.start) {
                            let matches = events.filter { cal.isDate($0.date, inSameDayAs: date) }
                            Button { selected = date } label: {
                                VStack(spacing: 4) {
                                    Text("\(day)").font(.subheadline.weight(cal.isDate(selected, inSameDayAs: date) ? .bold : .regular))
                                    HStack(spacing: 2) { ForEach(Array(matches.prefix(3))) { event in Circle().fill(event.tint).frame(width: 5, height: 5) } }.frame(height: 6)
                                }.frame(maxWidth: .infinity, minHeight: 40).background(cal.isDate(selected, inSameDayAs: date) ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).accessibilityLabel("\(day), платежів: \(matches.count)")
                        } else { Color.clear.frame(height: 40) }
                    }
                }
                Text("\(selected.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA"))))").font(.headline)
            }
            let shown = compact ? Array(events.filter { !$0.paid }.prefix(3)) : events.filter { cal.isDate($0.date, inSameDayAs: selected) }
            if shown.isEmpty { Text("Немає платежів").font(.caption).foregroundStyle(.secondary) }
            ForEach(shown) { event in
                if let p = event.payment { Button { payment = p } label: { eventRow(event) }.buttonStyle(.plain) }
                else { eventRow(event) }
            }
            if !overdue.isEmpty {
                Text("Прострочено: \(overdue.count)").font(.caption.weight(.medium)).foregroundStyle(.orange)
                ForEach(Array(overdue.prefix(compact ? 1 : 3))) { p in Button { payment = p } label: { HStack { Text(p.name).lineLimit(1); Spacer(); Text(show(p.amount,p.currency)) }.font(.caption) }.buttonStyle(.plain) }
            }
            if !compact { Text("Майбутні повторення — прогноз, не операції. Сплатити можна найближчий платіж договору.").font(.caption2).foregroundStyle(.secondary) }
        }.sheet(item: $payment) { FinamiPaymentDetails(payment: $0) }.accessibilityIdentifier("qa.calendar.grid")
    }
    private func eventRow(_ e: FinamiCalendarEvent) -> some View {
        HStack(alignment: .top) {
            Image(systemName: e.paid ? "checkmark.circle.fill" : "calendar").foregroundStyle(e.tint)
            VStack(alignment: .leading, spacing: 3) { Text(e.name).font(.subheadline); Text(e.kind + " · " + (e.paid ? "Сплачено" : e.projected ? "Прогноз" : "Очікує оплати")).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 4); Text(show(e.amount,e.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }
}
