import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

let finoraAccent = Color(red: 0.85, green: 0.12, blue: 0.25)
func money(_ n: Int64) -> String { currencyMoney(n, "UAH") }
func cents(_ s: String) -> Int64? { bankMinor(s) }
func amountText(_ n: Int64) -> String { finamiMinorText(n) }
func sameMonth(_ a: Date, _ b: Date) -> Bool {
  Calendar.current.isDate(a, equalTo: b, toGranularity: .month)
}
func shift(_ date: Date, _ n: Int) -> Date {
  Calendar.current.date(byAdding: .month, value: n, to: date) ?? date
}
func monthName(_ d: Date) -> String {
  d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA")))
}
@main @MainActor struct FinoraApp: App {
  @UIApplicationDelegateAdaptor(FinamiNotificationDelegate.self) private var notifications
  @StateObject private var store = Store()
  @State private var shortcutsRegistered = false
  var body: some Scene {
    WindowGroup {
      Group {
        if store.loading { VStack(spacing:16) { Image(systemName:"wallet.pass.fill").font(.system(size:48)).foregroundStyle(finoraAccent); Text("Finami").font(.largeTitle.bold()); ProgressView("Завантаження фінансів…") }.frame(maxWidth:.infinity,maxHeight:.infinity).task { await store.loadDatabase() } }
        else { IzanamiShell().environmentObject(store).task {
          // Do not perform shortcut registration on the first-frame path.
          guard !shortcutsRegistered else { return }
          do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
          guard !shortcutsRegistered else { return }
          shortcutsRegistered = true
          FinamiShortcuts.updateAppShortcutParameters()
        } }
      }.onOpenURL { url in
          guard url.scheme == "finami-widget", let host = url.host, ["balance","payments","quick","planning"].contains(host) else { return }
          store.widgetRoute = host
      }
    }
    .backgroundTask(.appRefresh(FinamiCaptureBackground.identifier)) {
      await FinamiCaptureBackground.process(store: store)
    }
  }
}
struct Root: View {
  var navigationAccent: Color = .purple
  @State private var keyboardVisible = false
  @EnvironmentObject var store: Store
  @Environment(\.scenePhase) var phase
  @AppStorage("lockEnabled") var lockEnabled = false
  @AppStorage("finami.hideAppSwitcher") private var hideAppSwitcher = true
  @State private var unlocked = false
  @State private var authError = ""
  @AppStorage("finami.widgets.shareAmounts") private var widgetShare = false
  @State private var tab = 0
  @State private var tabResets = Array(repeating: 0, count: 5)
  @State private var widgetAdd = false
  @State private var widgetCalendar = false
  @State private var widgetPlanning = false
  private func routeWidget() {
    guard !lockEnabled || unlocked, let action = store.widgetRoute else { return }
    store.widgetRoute = nil
    if action == "balance" { tab = 2 }
    if action == "quick" { tab = 0; widgetAdd = true }
    if action == "payments" { tab = 0; widgetCalendar = true }
    if action == "planning" { tab = 0; widgetPlanning = true }
  }
  private func updateWidgets() { FinamiWidgetBridge.update(store:store,enabled:widgetShare,locked:lockEnabled) }
  var body: some View {
    Group {
      if lockEnabled && !unlocked {
        VStack(spacing: 18) {
          Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(finoraAccent)
          Text("Finami").font(.largeTitle.bold())
          Text(authError).foregroundStyle(.secondary)
          Button("Розблокувати", action: unlock).buttonStyle(.borderedProminent)
        }.onAppear(perform: unlock)
      } else {
        VStack(spacing: 0) {
        TabView(selection: $tab) {
          NavigationStack { if store.db.preferences?.simpleHome == true { FinamiSimpleHome() } else { CustomDashboard() } }.toolbar(.hidden, for: .tabBar).tabItem { Label(store.db.preferences?.homeTitle ?? "Головна", systemImage: "house.fill") }.id("tab-0-\(tabResets[0])").tag(0)
          NavigationStack { Operations().toolbar { NavigationLink { FinamiGlobalSearch() } label: { Image(systemName:"magnifyingglass") }.accessibilityLabel("Пошук Finami") } }.toolbar(.hidden, for: .tabBar).tabItem {
            Label("Операції", systemImage: "arrow.left.arrow.right")
          }.id("tab-1-\(tabResets[1])").tag(1)
          NavigationStack { Accounts().toolbar { NavigationLink { FinamiGlobalSearch() } label: { Image(systemName:"magnifyingglass") }.accessibilityLabel("Пошук Finami") } }.toolbar(.hidden, for: .tabBar).tabItem {
            Label("Рахунки", systemImage: "wallet.pass.fill")
          }.id("tab-2-\(tabResets[2])").tag(2)
          NavigationStack { if store.privateAmounts { FinamiPrivacyNotice() } else { Reports().toolbar { NavigationLink { FinamiGlobalSearch() } label: { Image(systemName:"magnifyingglass") }.accessibilityLabel("Пошук Finami") } } }.toolbar(.hidden, for: .tabBar).tabItem { Label("Звіти", systemImage: "chart.bar.xaxis") }.id("tab-3-\(tabResets[3])").tag(3)
          NavigationStack { More() }.toolbar(.hidden, for: .tabBar).tabItem { Label("Ще", systemImage: "ellipsis.circle") }.id("tab-4-\(tabResets[4])").tag(4)
        }.toolbar(.hidden, for: .tabBar)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          // Reserve layout space rather than overlaying a nested bottom inset.
          if !keyboardVisible {
            FinamiFusionCrystal(selection: $tab, homeTitle: store.db.preferences?.homeTitle ?? "Головна", accent: navigationAccent, lowEffects: store.db.preferences?.designLowEffects == true, onReselect: { index in tabResets[index] += 1 })
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .task(id: phase) {
          guard phase == .active else {return}
          do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
          while !Task.isCancelled {
            await store.refreshCapturesInBackground()
            do {try await Task.sleep(nanoseconds: store.capturePending.isEmpty ? 6_000_000_000 : 12_000_000_000)} catch {break}
          }
        }
      }
    }.overlay {
      if phase != .active && (hideAppSwitcher || lockEnabled) {
        ZStack { Color(uiColor:.systemBackground).ignoresSafeArea(); VStack(spacing:12){Image(systemName:"lock.shield.fill").font(.largeTitle);Text("Finami").font(.title.bold())} }.accessibilityHidden(true)
      }
    }.onAppear { updateWidgets(); routeWidget() }
      .onChange(of: store.databaseVersion) { _ in updateWidgets() }
      .onChange(of: widgetShare) { _ in updateWidgets() }
      .onChange(of: lockEnabled) { _ in updateWidgets() }
      .onChange(of: unlocked) { _ in routeWidget() }
      .onChange(of: store.widgetRoute) { _ in routeWidget() }
      .sheet(isPresented: $widgetAdd) { OpEditor(original: Operation(category: "Без категорії", account: store.db.accounts.first?.id ?? cash)).environmentObject(store) }
      .sheet(isPresented: $widgetCalendar) { NavigationStack { CalendarView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Готово") { widgetCalendar = false } } } }.environmentObject(store) }
      .sheet(isPresented: $widgetPlanning) { NavigationStack { FinamiPlanningView().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Готово") { widgetPlanning=false } } } }.environmentObject(store) }
      .onChange(of: phase) { p in if p == .background && lockEnabled { unlocked = false; widgetAdd = false; widgetCalendar = false; widgetPlanning = false }; if p == .background { FinamiCaptureBackground.schedule() }; if p == .active { updateWidgets() } }.alert(
      "Finami",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
  }
  func unlock() {
    let context = LAContext()
    var e: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) else {
      authError = "Налаштуй код-пароль iPhone."
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Відкрити особисті фінанси")
    { ok, err in
      DispatchQueue.main.async {
        unlocked = ok
        authError = ok ? "" : (err?.localizedDescription ?? "Спробуй ще раз")
      }
    }
  }
}
