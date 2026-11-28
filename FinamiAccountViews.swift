import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct Accounts: View {
  @EnvironmentObject var s: Store
  @State private var edit: Account?
  @State private var configure = false
  @State private var reorder = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var prefs: AppearancePreferences { s.db.preferences ?? .init() }
  var mode: String { prefs.accountsMode ?? "own" }
  func update(_ action:(inout AppearancePreferences)->Void) { s.changeAppearance { p in action(&p) } }
  var shown:[Account] { s.db.accounts.filter { (prefs.accountsShowHidden == true || $0.hiddenInAccounts != true) && (mode == "all" || (mode == "credit" ? $0.isCredit : (!$0.isCredit || s.ownFunds($0)>0))) } }
  var body: some View {
    ScrollView { LazyVStack(spacing: prefs.finamiSpacing) {
      FinamiAccountsBalance()
      Button { reorder = true } label: { Label("Змінити порядок рахунків", systemImage: "arrow.up.arrow.down").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.plain).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
      Picker("Розділ",selection:Binding(get:{mode},set:{v in update{$0.accountsMode=v}})){Text("Власні").tag("own");Text("Кредитні").tag("credit");Text("Усі").tag("all")}.pickerStyle(.segmented)
      if mode != "own" { FinamiCreditSummary(showLimit:prefs.accountsShowLimit ?? true,showUsed:prefs.accountsShowUsed ?? true,showAvailable:prefs.accountsShowAvailable ?? true).environment(\.finamiMask, prefs.accountsHideCredit == true) }
      Picker("Вигляд рахунків",selection:Binding(get:{prefs.finamiLayout},set:{v in update{$0.designLayout=v;$0.modernAccountGrid=v == "grid"}})) { Text("Сітка").tag("grid");Text("Список").tag("list");Text("Картки").tag("cards") }.pickerStyle(.segmented).accessibilityIdentifier("qa.account.layout")
      if shown.isEmpty { FinamiEmptyCard(title: "Немає рахунків", detail: "Додай рахунок або зміни режим відображення.", icon: "wallet.pass") }
      if prefs.finamiLayout != "cards" {
        FinamiCompactAccountsGrid(accounts:finamiOrderedAccounts(shown),mode:mode,date:Date(),onAccountsScreen:true)
      } else {
      ForEach(finamiOrderedAccounts(shown)) { a in
        VStack(alignment: .leading, spacing: 5) {
          FinamiHomeAccountCard(accountID: a.id, date: Date(), fallbackTint: .teal, mode: mode, onAccountsScreen: true)
          if a.hiddenInAccounts == true { Label("Прихований рахунок", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
          if a.excludedFromTotals == true { Text("Не враховується в загальних сумах").font(.caption).foregroundStyle(.secondary) }
          if s.nativeBalance(a) < 0 && !a.isCredit { Text("Чистий залишок: " + (a.hideAmounts == true || prefs.accountsHideOwn == true ? "••••" : s.visibleMoney(s.nativeBalance(a), a.code))).font(.caption).foregroundStyle(.secondary) }
        }
      }
      }
      Button {edit=Account(name:"",accountType:"debit")} label:{Label("Додати рахунок",systemImage:"plus.circle.fill").frame(maxWidth:.infinity).padding(8)}.buttonStyle(.borderedProminent)
      NavigationLink { FinamiScanView(initialMode: .balance) } label: { Label("Звірити зі скриншота", systemImage: "doc.viewfinder") }
      NavigationLink("Перевірити старі імпортовані операції") { CreditImportCorrection() }
    }.padding() }.background(finamiScreenBackground(s.db.preferences)).navigationTitle("Рахунки").toolbar {
      ToolbarItemGroup(placement:.navigationBarTrailing) {
        Button {configure=true} label:{Image(systemName:"slider.horizontal.3")}.accessibilityLabel("Налаштування рахунків")
        Button {edit=Account(name:"",accountType:"debit")} label:{Image(systemName:"plus.circle.fill")}.accessibilityLabel("Додати рахунок")
      }
    }.sheet(item:$edit){AccountEditor(a:$0)}.sheet(isPresented:$configure){NavigationStack{FinamiAccountSettings()}}.sheet(isPresented:$reorder){NavigationStack{FinamiOrderEditor(target: .accounts)}}
  }
}
struct FinamiAccountSettings:View {
  @EnvironmentObject var s:Store
  @Environment(\.dismiss) var dismiss
  func binding<T>(_ key:WritableKeyPath<AppearancePreferences,T?>,_ fallback:T)->Binding<T>{Binding(get:{(s.db.preferences ?? .init())[keyPath:key] ?? fallback},set:{v in s.changeAppearance { p in p[keyPath:key]=v }})}
  var body:some View {Form {
    Section("Відображення") {Picker("Картки",selection:binding(\.accountsLayout,"split")){Text("Дві половини").tag("split");Text("Один спільний блок").tag("full")};Toggle("Показати приховані рахунки",isOn:binding(\.accountsShowHidden,false));Toggle("Приховати власний баланс",isOn:binding(\.accountsHideOwn,false));Toggle("Приховати кредитний баланс",isOn:binding(\.accountsHideCredit,false));Toggle("Приховати всі суми",isOn:binding(\.hideAmounts,false))}
    Section("Кредитні показники") {Toggle("Загальний ліміт",isOn:binding(\.accountsShowLimit,true));Toggle("Використано",isOn:binding(\.accountsShowUsed,true));Toggle("Доступно",isOn:binding(\.accountsShowAvailable,true))}
    Section("Спільне оформлення рахунків") { NavigationLink("Змінити порядок рахунків") { FinamiOrderEditor(target: .accounts, closeButton: false) }; NavigationLink("Вигляд, показники та порядок") { FinamiHomeAccountsSettings() } }
    Section("Рахунки") {ForEach(s.db.accounts){a in Toggle(a.name,isOn:Binding(get:{s.db.accounts.first(where:{$0.id==a.id})?.hiddenInAccounts != true},set:{v in s.change{d in if let i=d.accounts.firstIndex(where:{$0.id==a.id}){d.accounts[i].hiddenInAccounts = !v}}}))}}
  }.navigationTitle("Налаштування рахунків").toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){dismiss()}}} }
}
struct CreditAccountRow: View {
  @EnvironmentObject var s: Store
  let a: Account
  var mode = "all"
  func display(_ n:Int64)->String { a.hideAmounts == true ? "••••" : s.visibleMoney(n,a.code) }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        IzanamiGlyph(icon: a.isCredit ? "creditcard.fill" : "wallet.pass.fill", color: .teal)
        VStack(alignment:.leading) { Text(a.name).font(.headline); Text(a.typeName + (a.lastFour.map{" · •••• " + $0} ?? "")).font(.caption).foregroundStyle(.secondary) }
        Spacer(minLength: 0)
        if a.hiddenInAccounts == true { Image(systemName: "eye.slash") }
      }
      if mode != "credit" { FinamiMetric(title: "Власні кошти", value: display(s.ownFunds(a)), tint: .primary) }
      if a.isCredit && mode != "own" {
        FinamiMetric(title: "Кредитний ліміт", value: display(a.limit), tint: .primary)
        FinamiMetric(title: "Використано", value: display(s.debt(a)), tint: .orange)
        FinamiMetric(title: "Доступний кредит", value: display(s.unusedCredit(a)), tint: .green)
      } else if s.nativeBalance(a) < 0 { FinamiMetric(title: "Чистий залишок", value: display(s.nativeBalance(a)), tint: .orange) }
      if a.excludedFromTotals == true { Text("Не враховується в загальних сумах").font(.caption).foregroundStyle(.secondary) }
    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).modifier(FinamiCardStyle(tint:.teal))
  }
}
struct AccountEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var a: Account
  @State var opening: String
  @State private var limitText: String = ""
  @State private var masksText: String = ""
  @State private var actualText: String = ""
  @State private var correctBalance = false
  @State private var actualMode = "net"
  @State private var ownText = "0"
  @State private var usedText = "0"
  var validLimit: Bool { !a.isCredit || (bankMinor(limitText).map{$0>=0} ?? false) }
  var newOpening: Int64? {
    guard correctBalance else {
      if a.isCredit && !s.db.accounts.contains(where:{$0.id==a.id}) { return enteredCardNet }
      return bankMinor(opening)
    }
    let net: Int64
    if a.isCredit && actualMode == "components" { guard let n=enteredCardNet else{return nil}; net=n }
    else { guard let actual=bankMinor(actualText), actualMode != "available" || actual>=0 else{return nil}; net=actualMode == "available" && a.isCredit ? actual-(bankMinor(limitText) ?? 0) : actual }
    var history: Int64 = 0
    if var unanchored = s.db.accounts.first(where: { $0.id == a.id }) {
      unanchored.reconciliationDate = nil
      unanchored.reconciliationNet = nil
      history = s.nativeBalance(unanchored) - unanchored.opening
    }
    let (result, overflow) = net.subtractingReportingOverflow(history)
    return !overflow && result >= -1_000_000_000_000 && result <= 1_000_000_000_000 ? result : nil
  }
  var enteredCardNet: Int64? {
    guard let own=bankMinor(ownText), let used=bankMinor(usedText) else {return nil}
    return CardPosition.netFrom(own:own,used:used)
  }
  var existingAccount: Bool {s.db.accounts.contains(where:{$0.id==a.id})}
  @ViewBuilder var componentFields: some View {
    FinamiField("Власні кошти, \(a.code)", text: $ownText, keyboard: .decimalPad)
    FinamiField("Використано кредиту, \(a.code)", text: $usedText, keyboard: .decimalPad)
    Text("Для одного чистого балансу введи власні кошти або використаний кредит; друге поле залиш нульовим. Для окремих кредитних договорів потрібен окремий рахунок.").font(.caption)
  }
  init(a: Account) {
    _a = State(initialValue: a)
    _opening = State(initialValue: amountText(a.opening))
    _limitText = State(initialValue:amountText(a.limit))
    _masksText = State(initialValue:(a.additionalCardMasks ?? []).joined(separator:", "))
  }
  var body: some View {
    NavigationStack {
      Form {
        TextField("Назва", text: $a.name)
        Picker("Тип рахунку",selection:Binding(get:{a.accountType ?? (a.id == cash ? "cash" : "other")},set:{a.accountType=$0;if $0 != "credit" {actualMode="net"}})) {
          Text("Готівка").tag("cash");Text("Дебетова картка").tag("debit");Text("Кредитна картка").tag("credit");Text("Інший рахунок").tag("other")
        }
        TextField("Банк (необов’язково)",text:Binding(get:{a.bankName ?? ""},set:{a.bankName=$0}))
        TextField("IBAN рахунку (необов’язково)",text:Binding(get:{a.statementIBAN ?? ""},set:{a.statementIBAN=$0.uppercased()})).textInputAutocapitalization(.characters).autocorrectionDisabled()
        TextField("Додаткові маски карток через кому",text:$masksText)
        TextField("Останні 4 цифри (необов’язково)",text:Binding(get:{a.lastFour ?? ""},set:{a.lastFour=String($0.filter{$0.isASCII && $0.isNumber}.prefix(4))})).keyboardType(.numberPad)
        if a.isCredit {FinamiField("Кредитний ліміт, \(a.code)", text: $limitText, keyboard: .decimalPad)}
        Picker("Валюта рахунку",selection:Binding(get:{a.code},set:{a.currency=$0})){Text("UAH").tag("UAH");Text("USD").tag("USD")}.disabled(s.db.operations.contains{$0.account==a.id || $0.destination==a.id})
        Section("Видимість") {
          Toggle("Приховати суми рахунку", isOn: Binding(get:{a.hideAmounts ?? false},set:{a.hideAmounts=$0}))
          Toggle("Приховати в рахунках", isOn: Binding(get:{a.hiddenInAccounts ?? false},set:{a.hiddenInAccounts=$0}))
          Toggle("Приховати на огляді", isOn: Binding(get:{a.hiddenInOverview ?? false},set:{a.hiddenInOverview=$0}))
          Toggle("Не враховувати в загальних сумах", isOn: Binding(get:{a.excludedFromTotals ?? false},set:{a.excludedFromTotals=$0}))
          Text("Видимість не видаляє операції та не змінює історію.").font(.caption)
        }
        if let date=a.reconciliationDate {Text((a.reconciliationEstimated == true ? "Оціночний контрольний баланс на ":"Контрольний баланс на ")+date.formatted(date:.abbreviated,time:.shortened)+". Зміна початкової суми скине прив’язку; нова звірка встановить контрольну дату.").font(.caption)}
        Toggle("Звірити з поточним балансом банку",isOn:$correctBalance)
        if correctBalance {
          if a.isCredit {Picker("Яку суму показує банк",selection:$actualMode){Text("Чистий баланс (+ власні / − борг)").tag("net");Text("Доступно разом з кредитом").tag("available");Text("Власні кошти та використаний кредит").tag("components")}}
          if a.isCredit && actualMode == "components" {componentFields} else {FinamiField("Поточна сума, \(a.code)", text: $actualText, keyboard: .numbersAndPunctuation)}
          Text("Звірка встановить контрольний баланс на поточну дату. Історія збережеться; старі імпорти не змінять контрольну точку. Якщо банк показує доступні кошти з холдами, використовуй чистий баланс або борг. Це не дохід.").font(.caption)
        } else if a.isCredit && !existingAccount {
          componentFields
        } else {
          FinamiField("Початковий чистий баланс, \(a.code)", text: $opening, keyboard: .numbersAndPunctuation)
        }
        if a.code == "USD" && s.currentRate == nil {Text("Спочатку вкажи поточний курс у Ще → Валюти.").foregroundStyle(.orange)}
        Text("Якщо вже винен банку, введи від’ємний чистий баланс. Невикористаний ліміт не є початковим балансом.").font(.caption)
      }.navigationTitle("Рахунок").onAppear {
        if let old=s.db.accounts.first(where:{$0.id==a.id}) {let n=s.nativeBalance(old);actualText=amountText(n);ownText=amountText(max(0,n));usedText=amountText(max(0,-n))}
        else if a.bankName == nil && a.accountType == nil {a.accountType="debit"}
      }.toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            guard let n = newOpening, validLimit else { return }
            if correctBalance {
              let net:Int64?
              if a.isCredit && actualMode == "components" { net=enteredCardNet }
              else if a.isCredit && actualMode == "available" { net=bankMinor(actualText).flatMap { finamiEstimatedNetFromAvailable($0,limit:bankMinor(limitText) ?? 0) } }
              else { net=bankMinor(actualText) }
              let now=Date()
              guard let actual=net,let adjusted=finamiOpeningForAnchor(account:a,operations:s.db.operations,net:actual,at:now) else { s.error="Уточни чистий баланс або використаний кредит. Нуль доступного не визначає борг.";return }
              a.opening=adjusted;a.reconciliationDate=now;a.reconciliationNet=actual;a.reconciliationEstimated=(actualMode == "available" && a.isCredit)
            } else {
              if a.opening != n {a.reconciliationDate=nil;a.reconciliationNet=nil;a.reconciliationEstimated=nil}
              a.opening=n
            }
            a.statementIBAN = bankNormalizedIBAN(a.statementIBAN ?? "")
            a.additionalCardMasks = Array(Set(masksText.split(separator:",").map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}.filter{$0.count==4 && $0.allSatisfy{$0.isASCII && $0.isNumber}})).sorted()
            a.creditLimit = a.isCredit ? bankMinor(limitText) : nil
            if s.change({ d in
              if let i = d.accounts.firstIndex(where: { $0.id == a.id }) {
                d.accounts[i] = a
              } else {
                d.accounts.append(a)
              }
            }) {
              dismiss()
            }
          }.disabled(
            a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!(a.statementIBAN ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && bankNormalizedIBAN(a.statementIBAN ?? "") == nil) || newOpening == nil || !validLimit || (a.code == "USD" && s.currentRate == nil))
        }
      }
    }
  }
}
