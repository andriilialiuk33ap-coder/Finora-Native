import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct Budgets: View {
  @EnvironmentObject var s: Store
  @State private var cat = ""
  @State private var amount = ""
  @State private var editing = false
  var body: some View {
    List {
      Section("Загальний бюджет") {
        Button {
          cat = ""
          amount = amountText(s.db.budget)
          editing = true
        } label: {
          HStack {
            Text("Місячний ліміт")
            Spacer()
            Text(s.visibleMoney(s.db.budget))
          }
        }
        BudgetRow(
          name: "Усі витрати", used: s.totals(s.month(Date()), .expense), limit: s.db.budget)
      }
      Section("Категорії") {
        ForEach(s.db.expenseCategories, id: \.self) { c in
          Button {
            cat = c
            amount = amountText(s.db.limits[c] ?? 0)
            editing = true
          } label: {
            BudgetRow(
              name: c, used: s.totals(s.month(Date()).filter { $0.expenseGroup == c }, .expense),
              limit: s.db.limits[c] ?? 0)
          }.buttonStyle(.plain)
        }
      }
    }.navigationTitle("Бюджети").alert(cat.isEmpty ? "Місячний ліміт" : cat, isPresented: $editing)
    {
      TextField("Сума, ₴ (0 = без ліміту)", text: $amount).keyboardType(.decimalPad)
      Button("Скасувати", role: .cancel) {}
      Button("Зберегти") {
        guard let v = cents(amount), v >= 0 else {
          s.error = "Некоректна сума"
          return
        }
        s.change { d in if cat.isEmpty { d.budget = v } else { d.limits[cat] = v } }
      }
    }
  }
}
struct BudgetRow: View {
  @EnvironmentObject var s: Store
  var name: String
  var used: Int64
  var limit: Int64
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(name)
        Spacer()
        Text(s.visibleMoney(used)).font(.subheadline.bold())
      }
      if limit > 0 {
        if !s.privateAmounts { ProgressView(value: max(0,min(1, Double(used) / Double(limit)))).tint(used > limit ? .red : finoraAccent) }
        Text("Ліміт: \(s.visibleMoney(limit))").font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Без ліміту").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 4)
  }
}
