import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct Panel<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content }.frame(
      maxWidth: .infinity, alignment: .leading
    ).padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
  }
}
struct MonthControl: View {
  @Binding var date: Date
  var dashboardStyle = false
  var body: some View {
    HStack(spacing: 10) {
      monthButton(-1, icon:"chevron.left", label:"Попередній місяць")
      if dashboardStyle {
        Label(monthName(date).capitalized,systemImage:"calendar")
          .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
          .frame(maxWidth:.infinity,minHeight:44).padding(.horizontal,4)
          .background(Color.primary.opacity(0.055),in:RoundedRectangle(cornerRadius:14))
      } else {
        Spacer()
        Text(monthName(date).capitalized).font(.headline)
        Spacer()
      }
      monthButton(1, icon:"chevron.right", label:"Наступний місяць")
    }.padding(.vertical, 2)
  }
  private func monthButton(_ offset:Int,icon:String,label:String)->some View {
    Button { date = shift(date,offset) } label: {
      Image(systemName:icon).frame(width:44,height:44)
        .background(dashboardStyle ? Color.primary.opacity(0.055) : Color.clear,in:RoundedRectangle(cornerRadius:14))
    }.accessibilityLabel(label)
  }
}
struct Home: View {
  @EnvironmentObject var s: Store
  @State private var date = Date()
  @State private var add = false
  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        MonthControl(date: $date)
        let ops = s.month(date)
        let inc = s.totals(ops, .income)
        let exp = s.totals(ops, .expense)
        VStack(alignment: .leading, spacing: 16) {
          Text("Загальний залишок").font(.subheadline)
          Text(money(s.db.accounts.reduce(0) { $0 + s.balance($1) })).font(
            .system(size: 33, weight: .bold, design: .rounded)
          ).minimumScaleFactor(0.5)
          HStack {
            VStack(alignment: .leading) {
              Text("↓ Доходи").font(.caption)
              Text(money(inc)).bold()
            }
            Spacer()
            VStack(alignment: .trailing) {
              Text("↑ Витрати").font(.caption)
              Text(money(exp)).bold()
            }
          }
          Text("Грошовий потік: \(money(inc-exp))").font(.caption)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
          .background(
            LinearGradient(
              colors: [finoraAccent, Color(red: 0.03, green: 0.29, blue: 0.25)], startPoint: .topLeading,
              endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        Button {
          add = true
        } label: {
          Label("Додати операцію", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent)
        if s.db.budget > 0 {
          Panel {
            Text("Бюджет місяця").font(.headline)
            ProgressView(value: max(0, min(1, Double(exp) / Double(s.db.budget)))).tint(
              exp > s.db.budget ? .red : finoraAccent)
            Text("\(money(exp)) / \(money(s.db.budget))").font(.subheadline)
            Text(exp > s.db.budget ? "Ліміт перевищено" : "Залишок \(money(s.db.budget-exp))")
              .foregroundStyle(.secondary)
          }
        }
        Panel {
          Text("Категорії витрат").font(.headline)
          Breakdown(ops: ops)
        }
        Panel {
          Text("Останні операції").font(.headline)
          ForEach(ops.sorted { $0.date > $1.date }.prefix(5)) { o in OperationRow(o: o) }
          if ops.isEmpty { Text("Додай першу операцію").foregroundStyle(.secondary) }
        }
      }.padding()
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Finami").sheet(
      isPresented: $add
    ) { OpEditor(original: Operation(account: s.db.accounts.first?.id ?? cash)) }
  }
}
struct Breakdown: View {
  @EnvironmentObject var store: Store
  var ops: [Operation]
  var body: some View {
    let groups = Dictionary(grouping: ops.filter { $0.expenseValue != 0 }, by: { $0.expenseGroup })
      .mapValues { $0.reduce(Int64(0)) { $0 + $1.expenseValue } }.filter { $0.value > 0 }.sorted { $0.value > $1.value }
    let total = groups.reduce(Int64(0)) { $0 + $1.value }
    if total == 0 {
      Text("Немає витрат за період").foregroundStyle(.secondary)
    } else {
      ForEach(Array(groups.prefix(10).map(\.key)), id: \.self) { key in
        let value = groups.first(where: { $0.key == key })?.value ?? 0
        HStack {
          Text(key)
          Spacer()
          Text(store.visibleMoney(value)).bold()
        }.font(.subheadline)
        if !store.privateAmounts && store.db.preferences?.noCharts == false { ProgressView(value: Double(value) / Double(total)).tint(finoraAccent) }
      }
    }
  }
}
