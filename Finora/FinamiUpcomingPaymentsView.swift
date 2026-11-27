import SwiftUI

// Full live list, not a truncated snapshot of the dashboard. Archived contracts
// are removed from future planning while preserving ledger and paid history.
struct FinamiAllUpcomingPayments: View {
    @EnvironmentObject private var s: Store
    var filter: String = "all"
    var maskAmounts = false
    @State private var selected: FinamiPayment?
    @State private var removing: FinamiPayment?

    init(filter: String = "all", maskAmounts: Bool = false) {
        self.filter = filter
        self.maskAmounts = maskAmounts
    }
    private var payments: [FinamiPayment] {
        s.upcomingPayments.filter { p in
            switch filter {
            case "installments": return !p.subscription && p.kind == ObligationKind.installment.title
            case "subscriptions": return p.subscription
            case "recurring": return p.subscription || p.kind == ObligationKind.recurring.title || p.kind == ObligationKind.installment.title
            default: return true
            }
        }
    }
    var body: some View {
        List {
            Section("Усього: \(payments.count)") {
                if payments.isEmpty { Text("Немає запланованих платежів").foregroundStyle(.secondary) }
                ForEach(payments) { p in
                    Button { selected = p } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.headline)
                                Text(p.kind + " · " + p.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                if p.overdue { Text("Прострочено").font(.caption).foregroundStyle(.orange) }
                            }
                            Spacer()
                            Text(maskAmounts || (s.db.preferences?.designHiddenSubscriptions ?? []).contains(p.id) ? "••••" : s.visibleMoney(p.amount, p.currency)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("qa.upcoming.row." + p.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !p.subscription && p.kind == ObligationKind.installment.title {
                            Button(role: .destructive) { removing = p } label: { Label("Видалити", systemImage: "trash") }
                        }
                    }
                }
            }
            if filter == "all" || filter == "installments" { NavigationLink("Усі розстрочки, включно зі сплаченими") { Obligations(kind: .installment).environment(\.finamiMask, maskAmounts) } }
            NavigationLink("Календар платежів") { CalendarView().environment(\.finamiMask, maskAmounts) }
        }.navigationTitle("Усі платежі")
        .sheet(item: $selected) { p in FinamiPaymentDetails(payment: p).environment(\.finamiMask, maskAmounts || (s.db.preferences?.designHiddenSubscriptions ?? []).contains(p.id)) }
        .confirmationDialog("Видалити розстрочку з активного плану?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Видалити в архів", role: .destructive) {
                if let p = removing {
                    let reminders = (s.db.reminders ?? []).filter { $0.linkedID == p.id }
                    if s.change({ d in finamiRemoveInstallment(p.id, from: &d) }) { reminders.forEach { ReminderScheduler.cancel($0) } }
                }
                removing = nil
            }
            Button("Скасувати", role: .cancel) { removing = nil }
        } message: { Text("Майбутні платежі буде прибрано. Банківські операції та історія оплат залишаться.") }
    }
}
struct FinamiAllPaymentsLink: View {
    var count: Int
    var filter: String = "all"
    var masked = false
    var body: some View {
        NavigationLink { FinamiAllUpcomingPayments(filter: filter, maskAmounts: masked) } label: {
            HStack { Text("Усього: \(count)").font(.subheadline.weight(.medium)); Spacer(); Text("Відкрити всі").font(.caption); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                .foregroundStyle(Color.accentColor).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("qa.upcoming.all." + filter)
    }
}
