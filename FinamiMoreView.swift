import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct More: View {
  @EnvironmentObject var s: Store
  @State private var menuSettings=false
  func obligationIcon(_ kind: ObligationKind) -> String {
    switch kind { case .installment: return "creditcard.fill"; case .owe: return "arrow.up.right"; case .owed: return "arrow.down.left"; case .recurring: return "repeat"; case .goal: return "target" }
  }
  func obligationColor(_ kind: ObligationKind) -> Color {
    switch kind { case .installment: return .blue; case .owe: return .orange; case .owed: return .green; case .recurring: return .purple; case .goal: return .teal }
  }
  var body: some View {
    // This is a small, fixed menu; keep navigation links mounted when returning from a destination.
    ScrollView { VStack(alignment: .leading, spacing: (s.db.preferences ?? .init()).finamiSpacing) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Finami").font(.title.bold())
        Text("Особисті фінанси.").font(.subheadline).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(18).modifier(FinamiCardStyle(tint: .teal))
      NavigationLink { FinamiGlobalSearch() } label: { FinamiMenuLabel(title:"Пошук Finami",icon:"magnifyingglass",color:.teal) }.buttonStyle(.plain).accessibilityIdentifier("qa.search.open")
      VStack(spacing: 8) {
        HStack(alignment:.top,spacing:8) {
          NavigationLink { Categories() } label: { FinamiQuickMenuTile(title:"Категорії", icon:"tag.fill") }.accessibilityIdentifier("qa.quick.categories")
          NavigationLink { AppearanceView() } label: { FinamiQuickMenuTile(title:"Finami Design", icon:"paintpalette.fill") }.accessibilityIdentifier("qa.quick.design")
        }
        HStack(alignment:.top,spacing:8) {
          NavigationLink { CalendarView() } label: { FinamiQuickMenuTile(title:"Платежі", icon:"calendar") }
          NavigationLink { FinamiBalanceView(initialMode:"anchor") } label: { FinamiQuickMenuTile(title:"Звірити баланс", icon:"checkmark.circle") }.accessibilityIdentifier("qa.quick.reconcile")
        }
      }.buttonStyle(.plain)
      FinamiMenuGroup("Finami Next") {
        NavigationLink { FinamiAuditView() } label: { FinamiMenuLabel(title:"Якість фінансових даних",icon:"checkmark.shield.fill",color:.teal) }.accessibilityIdentifier("qa.quality.open")
        NavigationLink { FinamiNextReviewView() } label: { FinamiMenuLabel(title:"Центр перевірки операцій",icon:"checkmark.shield",color:.orange) }.accessibilityIdentifier("qa.next.review")
        NavigationLink { FinamiNextInsightsView() } label: { FinamiMenuLabel(title:"Фінансові підсумки",icon:"chart.bar.xaxis",color:.teal) }.accessibilityIdentifier("qa.next.insights")
        NavigationLink { FinamiExchangeDiaryView() } label: { FinamiMenuLabel(title:"Журнал USDT",icon:"arrow.left.arrow.right",color:.green) }.accessibilityIdentifier("qa.next.usdt")
        }
      FinamiMenuGroup("Планування") {
        NavigationLink { FinamiBrandSettings() } label: { FinamiMenuLabel(title: "Brand Icons", icon: "photo.on.rectangle", color: .purple) }
        NavigationLink { FinamiPlanningView() } label: { FinamiMenuLabel(title: "Розумне планування", icon: "chart.line.uptrend.xyaxis", color: .teal) }.accessibilityIdentifier("qa.planning.open")
        NavigationLink { FinamiCreditCenter() } label: { FinamiMenuLabel(title: "Кредитний центр", icon: "creditcard.fill", color: .orange) }
        NavigationLink { FinamiEnvelopesView() } label: { FinamiMenuLabel(title: "Віртуальні конверти", icon: "envelope.fill", color: .green) }
        NavigationLink { SubscriptionsView() } label: { FinamiMenuLabel(title: "Підписки", icon: "repeat", color: .purple) }
        NavigationLink { FinamiRecurringSuggestionsView() } label: { FinamiMenuLabel(title: "Виявлення підписок", icon: "sparkles", color: .purple) }.accessibilityIdentifier("qa.recurring.open")
        NavigationLink { ReminderList() } label: { FinamiMenuLabel(title: "Нагадування", icon: "bell.badge.fill", color: .red) }
        NavigationLink { CurrencySettings() } label: { FinamiMenuLabel(title: "Валюти та курси", icon: "dollarsign.circle.fill", color: .green) }
        NavigationLink { CurrencyCalculator() } label: { FinamiMenuLabel(title: "Конвертер валют", icon: "dollarsign.arrow.circlepath", color: .cyan) }
        NavigationLink {
          Budgets()
        } label: {
          FinamiMenuLabel(title: "Бюджети", icon: "chart.pie.fill", color: .indigo)
        }
        ForEach(ObligationKind.allCases) { k in
          NavigationLink {
            Obligations(kind: k)
          } label: {
            FinamiMenuLabel(title: k.title, icon: obligationIcon(k), color: obligationColor(k))
          }
        }
        NavigationLink {
          CalendarView()
        } label: {
          FinamiMenuLabel(title: "Календар платежів", icon: "calendar", color: .cyan)
        }.accessibilityIdentifier("qa.calendar.open")
        NavigationLink {
          Insights()
        } label: {
          FinamiMenuLabel(title: "Фінансовий помічник", icon: "sparkles", color: .purple)
        }
      }
      FinamiMenuGroup("Банки") {
        NavigationLink { FinamiImportHub() } label: { FinamiMenuLabel(title: "Імпорт, експорт та перевірка", icon: "tray.full.fill", color: .indigo) }.accessibilityIdentifier("qa.smart.hub")
        NavigationLink { FinamiReconciliation() } label: { FinamiMenuLabel(title: "Розумна звірка рахунків", icon: "checkmark.circle.trianglebadge.exclamationmark", color: .cyan) }
        NavigationLink { AutomationCenter() } label: { FinamiMenuLabel(title: "Автоматизація · Apple Pay / SMS", icon: "bolt.fill", color: .orange) }
      }
      FinamiMenuGroup("Система") {
        NavigationLink { FinamiWidgetsSettings() } label: { FinamiMenuLabel(title: "Віджети iPhone", icon: "square.grid.2x2", color: .teal) }
        NavigationLink { FinamiDiagnostics() } label: { FinamiMenuLabel(title: "Діагностика Finami", icon: "checkmark.shield.fill", color: .green) }.accessibilityIdentifier("qa.smart.diagnostics")
        NavigationLink { FinamiHelp() } label: { FinamiMenuLabel(title: "Допомога та інструкції", icon: "book.fill", color: .blue) }
        NavigationLink { DashboardSettings() } label: { FinamiMenuLabel(title: "Блоки огляду", icon: "square.grid.2x2.fill", color: .orange) }
        NavigationLink {
          Settings()
        } label: {
          FinamiMenuLabel(title: "Захист та резервні копії", icon: "lock.shield.fill", color: .green)
        }
      }
      VStack(alignment: .leading) {
        Text("Finami · " + FinamiBuildInfo.version + " · " + FinamiBuildInfo.edition + "\nБез реклами, серверів та платних API.").font(.footnote)
          .foregroundStyle(.secondary)
      }
    }.padding() }.accessibilityIdentifier("qa.more.scroll").background(finamiScreenBackground(s.db.preferences)).navigationTitle("Ще").toolbar{Button{menuSettings=true} label:{Image(systemName:"slider.horizontal.3")}.accessibilityLabel("Налаштування меню")}.sheet(isPresented:$menuSettings){NavigationStack{Form{Toggle("Компактні ілюстрації",isOn:Binding(get:{s.db.preferences?.menuCompact ?? false},set:{v in s.changeAppearance { p in p.menuCompact=v }}));NavigationLink("Студія дизайну"){AppearanceView()};NavigationLink("Блоки головної"){DashboardSettings()};NavigationLink("Рахунки"){FinamiAccountSettings()}}.navigationTitle("Налаштування меню").toolbar{Button("Готово"){menuSettings=false}}}}
  }
}
