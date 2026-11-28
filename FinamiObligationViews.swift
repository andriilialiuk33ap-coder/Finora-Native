import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct Obligations: View {
  @EnvironmentObject var s: Store
  @Environment(\.finamiMask) private var masked
  var kind: ObligationKind
  @State private var paymentDetails: FinamiPayment?
  @State private var edit: Obligation?
  @State private var remove: Obligation?
  @State private var archiveExpanded = false
  private func visibleMoney(_ amount: Int64) -> String { masked ? "••••" : s.visibleMoney(amount) }
  private func moveToArchive(_ o: Obligation) {
    let linked = (s.db.reminders ?? []).filter { $0.linkedID == o.id }
    if s.change({ d in finamiRemoveInstallment(o.id, from: &d) }) { linked.forEach { ReminderScheduler.cancel($0) } }
  }
  var body: some View {
    List {
      if kind == .installment { NavigationLink { FinamiScanView(initialMode: .installment) } label: { Label("Додати зі скриншота", systemImage: "doc.viewfinder") } }
      Section("Загальний залишок") {
        Text(visibleMoney(s.db.obligations.filter { $0.kind == kind }.reduce(0) { $0 + $1.remaining }))
          .font(.title.bold())
      }
      ForEach(s.db.obligations.filter { $0.kind == kind }) { o in
        let collapsed = kind == .installment && (s.db.preferences?.isDesignCardCollapsed(o.id, subscription: false) ?? false)
        HStack(spacing: 10) {
        Button {
          if let payment = s.upcomingPayments.first(where: { $0.id == o.id && !$0.subscription }) { paymentDetails = payment }
          else { edit = o }
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              if kind == .installment { FinamiBrandTile(name: o.name, icon: "creditcard.fill", tint: .indigo, side: 30, paymentStyle: true) }
              Text(o.name).bold()
              Spacer()
              Text(visibleMoney(o.remaining))
            }
            if !collapsed {
              if kind == .installment { FinamiInstallmentDesign(obligation: o) }
              else if !s.privateAmounts && !masked { ProgressView(value: o.target > 0 ? min(1, Double(o.paid) / Double(o.target)) : 0) }
              Text(
                "\(visibleMoney(o.paid)) із \(visibleMoney(o.target)) · \(o.due.formatted(date:.abbreviated,time:.omitted))"
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
        }.buttonStyle(.plain)
        if kind == .installment {
          Button { s.changeAppearance { $0.toggleDesignCard(o.id, subscription: false) } } label: {
            Image(systemName: collapsed ? "chevron.down" : "chevron.up").frame(minWidth: 44,minHeight: 44)
          }.buttonStyle(.borderless).accessibilityLabel(collapsed ? "Розгорнути розстрочку" : "Згорнути розстрочку").accessibilityIdentifier("qa.installment.collapse." + o.id)
        }
        }.swipeActions(edge: .trailing, allowsFullSwipe: false) {
          if kind == .installment { Button(role: .destructive) { remove = o } label: { Label("Видалити", systemImage: "trash") }.tint(.red) }
        }
      }
      if kind == .installment, let archived = s.db.removedInstallments, !archived.isEmpty {
        Section {
          DisclosureGroup("Архів розстрочок · \(archived.count)", isExpanded: $archiveExpanded) {
            ForEach(archived) { o in
              HStack { VStack(alignment: .leading) { Text(o.name); Text(visibleMoney(o.remaining)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Відновити") { s.change { d in finamiRestoreInstallment(o.id, into: &d) } }.buttonStyle(.borderless) }
            }
            Text("Відновлення повертає графік. Нагадування та прив’язку до партнерської групи налаштуй повторно.").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }.confirmationDialog("Прибрати розстрочку з активного плану?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
      Button("Видалити в архів", role: .destructive) { if let o = remove { moveToArchive(o) }; remove = nil }
      Button("Скасувати", role: .cancel) { remove = nil }
    } message: { Text("Банківські операції та історія сплати залишаться. Майбутні платежі й нагадування буде прибрано. Розстрочку можна відновити з архіву.") }
    .navigationTitle(kind.title).toolbar {
      Button {
        edit = Obligation(kind: kind)
      } label: {
        Image(systemName: "plus")
      }
    }.sheet(item: $edit) { ObligationEditor(original: $0) }
      .sheet(item: $paymentDetails) { FinamiPaymentDetails(payment: $0).environment(\.finamiMask, masked) }
  }
}
struct ObligationEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var o: Obligation
  @State var target: String
  @State var paid: String
  @State var monthly: String
  @State var remainingText: String
  @State var payment = ""
  @State var log = false
  @State var account = cash
  @State var confirm = false
  @State private var undoRecord: String?
  private let original: Obligation
  init(original: Obligation) {
    self.original = original
    _o = State(initialValue: original)
    _target = State(initialValue: amountText(original.target))
    _paid = State(initialValue: amountText(original.paid))
    _monthly = State(initialValue: amountText(original.monthly))
    _remainingText = State(initialValue: amountText(original.remaining))
  }
  var baseTarget: Int64? { cents(target) }
  var basePaid: Int64? { o.kind == .installment ? cents(remainingText).flatMap { r in baseTarget.map { $0 - r } } : cents(paid) }
  private var scheduleEditable: Bool {
    guard o.confirmedSchedule != nil else { return true }
    return baseTarget == o.target && basePaid == o.paid && cents(monthly) == o.monthly && o.confirmedScheduleValid && payment.isEmpty
  }
  var valid: Bool {
    !o.name.trimmingCharacters(in: .whitespaces).isEmpty && (baseTarget ?? 0) > 0
      && (o.kind != .installment || (cents(remainingText) ?? -1) >= 0)
      && (basePaid ?? -1) >= 0 && (basePaid ?? 0) <= (baseTarget ?? 0)
      && (cents(monthly) ?? -1) >= 0
      && scheduleEditable
      && (payment.isEmpty
        || ((cents(payment) ?? 0) > 0
          && (cents(payment) ?? 0) <= (baseTarget ?? 0) - (basePaid ?? 0)))
  }
  var body: some View {
    NavigationStack {
      Form {
      if let rows = o.confirmedSchedule {
        Section("Підтверджений залишок графіка") {
          ForEach(rows) { row in LabeledContent(row.date.formatted(date: .abbreviated, time: .omitted), value: s.visibleMoney(row.amount)) }
          Text("Для зміни фінансових параметрів спочатку вимкни графік або імпортуй оновлений договір. Історія списань не змінюється.").font(.caption)
          Button("Вимкнути підтверджений графік", role: .destructive) { o.confirmedSchedule = nil }
        }
      }
      if let rows = o.importedSchedule, !rows.isEmpty {
        Section("Графік з банківського скриншота") {
          ForEach(rows) { row in LabeledContent(row.date.formatted(date: .abbreviated, time: .omitted), value: s.visibleMoney(row.amount)) }
          Text("Довідкові дані імпорту; можуть застаріти після зміни договору.").font(.caption)
          Button("Видалити довідковий графік", role: .destructive) { o.importedSchedule = nil }
        }
      }

        Section("Параметри") {
          FinamiField("Назва", text: $o.name)
          if o.kind == .installment {
            TextField("Останні 4 цифри договору (необов’язково)",text:Binding(get:{o.creditContractSuffix ?? ""},set:{o.creditContractSuffix=String($0.filter{$0.isASCII && $0.isNumber}.prefix(4))})).keyboardType(.numberPad)
            FinamiField("Загальний кредит, ₴", text: $target, keyboard: .decimalPad)
            FinamiField("Поточний залишок розстрочки, ₴", text: $remainingText, keyboard: .decimalPad)
            Text("Введи залишок боргу, не суму вже сплачених платежів.").font(.caption)
          } else {
            FinamiField("Загальна сума, ₴", text: $target, keyboard: .decimalPad)
            FinamiField("Вже сплачено / накопичено", text: $paid, keyboard: .decimalPad)
          }
          FinamiField("Регулярний платіж, ₴", text: $monthly, keyboard: .decimalPad)
          DatePicker("Наступна дата / термін", selection: $o.due, displayedComponents: [.date, .hourAndMinute])
          if let imageID = o.scanImageID { NavigationLink("Вкладений скриншот") { FinamiScanAttachment(imageID: imageID) } }
          if s.db.obligations.contains(where: { $0.id == o.id }) {
            NavigationLink("Нагадування") { ReminderEditor(original: PersonalReminder(title: o.name, date: o.due, linkedID: o.id)) }
          }
        }
        if !(s.db.paidRecords ?? []).filter({$0.paymentID == o.id}).isEmpty {
          Section("Історія оплат") { ForEach((s.db.paidRecords ?? []).filter{$0.paymentID==o.id}.sorted{$0.paidDate>$1.paidDate}) { record in VStack(alignment:.leading) { LabeledContent(record.paidDate.formatted(date:.abbreviated,time:.omitted) + " · " + (record.accountID.map{s.accountName($0)} ?? "Без списання"),value:s.visibleMoney(record.amount,record.currency)); if s.canUndoObligationPayment(record.id) { Button("Скасувати зв’язок оплати",role:.destructive) { undoRecord=record.id }.font(.caption) } } } }
        }
        if o.kind == .installment, s.db.obligations.contains(where: { $0.id == o.id }) {
          Section("Оплата") { Text("Для часткової або дострокової оплати відкрий розстрочку та натисни «Сплатив з картки / рахунку».").font(.caption) }
        } else { Section("Додати платіж або накопичення") {
          FinamiField("Сума", text: $payment, keyboard: .decimalPad)
          if o.kind != .goal {
            Toggle("Також записати операцію", isOn: $log)
            if log {
              Picker("Рахунок", selection: $account) {
                ForEach(s.db.accounts.filter{$0.code == "UAH"}) { Text($0.name).tag($0.id) }
              }
            }
          }
          Text(
            "Для цілей прогрес не змінює залишків рахунків. Для боргів і розстрочок облік платежу в операціях — за вибором."
          ).font(.caption)
        }
        }
        if s.db.obligations.contains(where: { $0.id == o.id }) {
          Button("Видалити", role: .destructive) { confirm = true }
        }
      }.navigationTitle(o.kind.title).navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            guard valid, let t = baseTarget, let p = basePaid, let m = cents(monthly) else {
              return
            }
            if let live = s.db.obligations.first(where: { $0.id == o.id }),
               live.paid != original.paid || live.target != original.target || live.monthly != original.monthly || live.due != original.due || live.confirmedSchedule != original.confirmedSchedule || live.currentDuePaid != original.currentDuePaid {
              s.error = "Договір змінився. Відкрий його знову."; return
            }
            let extra = cents(payment) ?? 0
            if o.target != t || o.paid != p || o.monthly != m || extra > 0 || s.db.obligations.first(where:{$0.id==o.id})?.due != o.due { o.currentDuePaid = nil }
            o.target = t
            o.paid = p + extra
            o.monthly = m
            if extra > 0 && (o.kind == .installment || o.kind == .recurring) {
              o.due = shift(o.due, 1)
            }
            if s.change({ d in
              if let i = d.obligations.firstIndex(where: { $0.id == o.id }) {
                d.obligations[i] = o
              } else {
                d.obligations.append(o)
              }
              if extra > 0 && log && o.kind != .goal && d.accounts.contains(where:{$0.id==account && $0.code=="UAH"}) {
                d.operations.append(
                  Operation(
                    kind: o.kind == .owed ? .movementIn : o.kind == .recurring ? .expense : .creditRepayment, amount: extra, category: "Інше",
                    note: o.name, account: account))
              }
            }) {
              dismiss()
            }
          }.disabled(!valid)
        }
      }.confirmationDialog("Скасувати лише зв’язок? Банківська операція залишиться в обліку.",isPresented:Binding(get:{undoRecord != nil},set:{if !$0 {undoRecord=nil}})) { Button("Відновити графік",role:.destructive) { if let id=undoRecord, s.undoObligationPayment(id) { dismiss() };undoRecord=nil } }
      .confirmationDialog("Видалити запис?", isPresented: $confirm) {
        Button("Видалити", role: .destructive) {
          let linked=(s.db.reminders ?? []).filter{$0.linkedID==o.id}
        if s.change({d in
          if o.kind == .installment { finamiRemoveInstallment(o.id, from: &d) }
          else { d.obligations.removeAll{$0.id==o.id};d.reminders?.removeAll{$0.linkedID==o.id} }
        }) {linked.forEach{ReminderScheduler.cancel($0)};dismiss()}
        }
      }
    }
  }
}
