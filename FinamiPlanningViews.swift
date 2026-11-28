import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct CalendarView: View {
  @EnvironmentObject var s: Store
  @Environment(\.finamiMask) private var maskAmounts
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 16) {
        FinamiCalendarGrid(masked: maskAmounts).padding(14).modifier(FinamiCardStyle(tint: .teal))
        FinamiMonthPayments()
    }.padding() }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Календар платежів")
  }
}
struct Categories: View {
  @EnvironmentObject var s: Store
  @State private var income = false
  @State private var adding = false
  @State private var editing: String? = nil
  @State private var name = ""
  @State private var parent = ""
  @State private var deleting: String? = nil
  @State private var replacement = "Інше"
  var cats: [String] { income ? s.db.incomeCategories : s.db.expenseCategories }
  var hidden: [String] { income ? s.db.hiddenIncomeCategories ?? [] : s.db.hiddenExpenseCategories ?? [] }
  var body: some View {
    List {
      Picker("Тип", selection: $income) { Text("Витрати").tag(false); Text("Доходи").tag(true) }.pickerStyle(.segmented)
      NavigationLink("Категорії зарахувань") { FinamiReceiptCategoriesView() }
      if !income { Button("Додати стандартні категорії") { s.change { d in for c in expenseDefaults where !d.expenseCategories.contains(c) { d.expenseCategories.append(c) } } } }
      ForEach(cats, id: \.self) { c in
        HStack {
          VStack(alignment:.leading) { Text(c).font(.body.weight(.medium)); if !income, let p=s.db.categoryParents?[c] { Text("Група: " + p).font(.caption).foregroundStyle(.secondary) } }
          Spacer()
          if c != "Інше" && c != "Без категорії" {
            Button { toggle(c) } label: { Image(systemName:hidden.contains(c) ? "eye.slash" : "eye") }.buttonStyle(.borderless).accessibilityLabel(hidden.contains(c) ? "Показати" : "Приховати")
            Menu { Button("Редагувати") { editing=c;name=c;parent=s.db.categoryParents?[c] ?? "";adding=true }; Button("Видалити",role:.destructive) { replacement="Інше";deleting=c } } label: { Image(systemName:"ellipsis.circle") }
          }
        }
      }.onMove { from,to in s.change { d in if income { d.incomeCategories.move(fromOffsets:from,toOffset:to) } else { d.expenseCategories.move(fromOffsets:from,toOffset:to) } } }
    }.navigationTitle("Категорії").toolbar { EditButton(); Button { editing=nil;name="";parent="";adding=true } label:{Image(systemName:"plus.circle.fill")}.accessibilityLabel("Додати категорію").accessibilityIdentifier("qa.category.add") }
      .sheet(isPresented:$adding) { NavigationStack { Form { TextField("Іконка та назва",text:$name); NavigationLink { FinamiCategoryIconPicker(name:$name) } label: { Label("Обрати іконку",systemImage:"face.smiling") }.accessibilityIdentifier("qa.category.icons"); if !income { TextField("Група (необов’язково)",text:$parent) }; Button("Зберегти") { save() }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (cats.contains(name.trimmingCharacters(in:.whitespacesAndNewlines)) && editing != name.trimmingCharacters(in:.whitespacesAndNewlines))) }.navigationTitle(editing == nil ? "Нова категорія" : "Редагування").toolbar { Button("Скасувати") { adding=false } } } }
      .confirmationDialog("Перенести операції перед видаленням",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) { ForEach(cats.filter{$0 != deleting},id:\.self) { c in Button("Перенести в «"+c+"»") { if let old=deleting { replace(old,with:c,remove:true) };deleting=nil } }; Button("Скасувати",role:.cancel){deleting=nil} } message:{Text("Операції не видаляються. Бюджет і правила категорії буде перенесено.")}
  }
  func toggle(_ c:String) { s.change { d in var list=income ? d.hiddenIncomeCategories ?? [] : d.hiddenExpenseCategories ?? []; if list.contains(c) { list.removeAll{$0==c} } else { list.append(c) }; if income {d.hiddenIncomeCategories=list} else {d.hiddenExpenseCategories=list} } }
  func save() {
    let c = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidate = s.db
    guard FinamiCategoryCore.edit(&candidate, income: income, old: editing, new: c, parent: income ? nil : parent) else { s.error = "Перевір назву категорії та бюджет."; return }
    if s.change({ $0 = candidate }) { adding = false }
  }
  func replace(_ old: String, with new: String, remove: Bool) {
    var candidate = s.db
    guard FinamiCategoryCore.edit(&candidate, income: income, old: old, new: new, merge: remove) else { s.error = "Не вдалося перенести категорію. Перевір назву та бюджет."; return }
    s.change { $0 = candidate }
  }
}
struct Insights: View {
  @EnvironmentObject var s: Store
  var body: some View {
    let ops = s.month(Date())
    let inc = s.totals(ops, .income)
    let exp = s.totals(ops, .expense)
    let previous = s.totals(s.month(shift(Date(), -1)), .expense)
    let elapsed = Calendar.current.component(.day, from: Date())
    let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    let forecast = Int64(Double(exp) / Double(max(1, elapsed)) * Double(days))
    ScrollView {
      VStack(spacing: 14) {
        Panel {
          Label("Локальний аналіз", systemImage: "sparkles").font(.headline)
          Text("Розрахунки виконуються на телефоні, без ШІ API.").foregroundStyle(.secondary)
        }
        Panel {
          Text("Прогноз витрат місяця").font(.headline)
          Text(s.visibleMoney(forecast)).font(.title.bold())
          Text("Оцінка за поточним середнім темпом, не гарантія.").font(.caption)
        }
        Panel {
          Text("Грошовий потік").font(.headline)
          Text(s.visibleMoney(inc - exp)).font(.title.bold())
          if inc > 0 && !s.privateAmounts {
            Text(
              "Частка невитраченого доходу: \((Double(inc-exp)/Double(inc)*100).formatted(.number.precision(.fractionLength(1))))%"
            )
          }
          Text("Витрати минулого місяця: \(s.visibleMoney(previous))")
          if s.db.budget > 0 {
            Text(
              forecast > s.db.budget
                ? "За поточного темпу бюджет може бути перевищено." : "Прогноз у межах бюджету.")
          }
        }
        Panel {
          Label("Платежі та ризики", systemImage: "calendar.badge.exclamationmark").font(.headline)
          let overdue = s.upcomingPayments.filter(\.overdue)
          let planned = s.scheduledThisMonth(currency: "UAH")
          let overdueUAH = overdue.filter { $0.currency == "UAH" }.reduce(Int64(0)) { $0 + $1.amount }
          let reserve = max(0, s.db.forecast?.reserve ?? 0)
          if !s.privateAmounts {
            LabeledContent("До кінця місяця · UAH", value: s.visibleMoney(planned))
            LabeledContent("Прострочено · UAH", value: s.visibleMoney(overdueUAH))
            let ownUAH = s.includedAccounts.filter { $0.code == "UAH" }.reduce(Int64(0)) { $0 + s.ownFunds($1) }
            let free = ownUAH - planned - overdueUAH - reserve
            LabeledContent("Вільні власні кошти · UAH", value: s.visibleMoney(max(0,free)))
            if free < 0 { Label("Можлива нестача коштів на заплановані оплати",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
            if s.scheduledThisMonth(currency: "USD") > 0 { Text("Доларові зобов’язання рахуються окремо.").font(.caption).foregroundStyle(.secondary) }
          }
          if !overdue.isEmpty { Text("Прострочені платежі: \(overdue.count)").foregroundStyle(.orange) }
          NavigationLink("Відкрити календар") { CalendarView() }
          Text("Прогноз, а не фактичне списання. Не включає незаплановані витрати та очікувану зарплату.").font(.caption).foregroundStyle(.secondary)
        }
        Panel {
          Label("Розумні підказки",systemImage:"sparkles").font(.headline)
          let suggestions = s.recurringSuggestions
          if !suggestions.isEmpty { Text("Можливі нові підписки: \(suggestions.count)") }
          let increases = s.recurringPriceChanges
          if !increases.isEmpty { Label("Можливе зростання тарифів: \(increases.count)",systemImage:"exclamationmark.circle").foregroundStyle(.orange) }
          ForEach(Array(increases.prefix(3))) { candidate in
            HStack { Text(candidate.merchant).lineLimit(2); Spacer(); Text(s.db.accounts.first(where:{$0.id == candidate.account})?.hideAmounts == true ? "••••" : s.visibleMoney(candidate.amount,candidate.currency)).font(.subheadline.bold()) }
          }
          if !increases.isEmpty { NavigationLink("Перевірити тарифи підписок") { SubscriptionsView() } }
          let review = s.db.operations.filter { $0.requiresReview }.count + s.capturePending.count
          Text("Потребують уточнення: \(review)").font(.subheadline)
          NavigationLink("Виявлення підписок") { FinamiRecurringSuggestionsView() }
          NavigationLink("Звірити залишки") { FinamiReconciliation() }
          NavigationLink("Уточнити операції") { FinamiImportHub() }
        }
        Panel {
          Text("Найбільші витрати").font(.headline)
          Breakdown(ops: ops)
        }
      }.padding()
    }.navigationTitle("Помічник")
  }
}
