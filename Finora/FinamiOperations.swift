import SwiftUI
import UIKit

struct OperationRow: View {
  @EnvironmentObject var s: Store
  @Environment(\.finamiMask) private var masked
  var o: Operation
  private var amountsMasked:Bool { masked || s.operationAmountsMasked(o) }
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  private var style: String { s.db.preferences?.designStyle(for: "operations") ?? "classicPremium" }
  private var size: String { s.db.preferences?.designSize(for: "operations") ?? "M" }
  private var tint: Color { (o.kind == .income || o.kind == .receipt) ? .green : o.kind == .expense ? .orange : .blue }
  private var details: some View {
    VStack(alignment:.leading,spacing:3) {
      Text(o.note.isEmpty ? (o.kind == .transfer ? "Переказ" : o.category) : finamiMerchantDisplay(o.note)).font(.subheadline.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
      Text("\(o.displayKindTitle) · \(s.accountName(o.account)) · \(o.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "uk_UA"))))")
        .font(.caption).foregroundStyle(.secondary)
      if style != "compactLedger" && size != "S" { Text(o.sourceLabel).font(.caption2).foregroundStyle(.secondary) }
    }.frame(maxWidth:.infinity,alignment:.leading)
  }
  private var amounts: some View {
    VStack(alignment:.trailing,spacing:2) {
      Text(amountsMasked ? "••••" : (o.kind == .transfer ? "" : o.kind.incoming ? "+" : "−") + money(o.amount))
        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle((o.kind == .income || o.kind == .receipt) ? Color.green : Color.primary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.7)
      if let n=o.originalAmount, let code=o.originalCurrency, code != "UAH" { Text(amountsMasked ? "••••" : s.visibleMoney(n,code)).font(.caption).foregroundStyle(.secondary) }
    }
  }
  private var tileSize: CGFloat {
    if style == "compactLedger" || size == "S" { return 32 }
    if style == "merchantCards" || size == "L" { return 48 }
    return s.db.preferences?.modernCompactSpacing == true ? 36 : 42
  }
  private var standard: some View {
    HStack(alignment: .top, spacing: style == "compactLedger" ? 7 : 10) {
      FinamiBrandTile(name: o.note, icon: finamiOperationIcon(o), tint: tint, side: tileSize, merchantsOnly: true)
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) { details; amounts.frame(maxWidth: .infinity, alignment: .leading) }
      } else { details; amounts.layoutPriority(1) }
    }
  }
  @ViewBuilder var body: some View {
    Group {
      switch style {
      case "merchantCards":
        VStack(alignment: .leading, spacing: 8) {
          HStack { FinamiBrandTile(name: o.note, icon: finamiOperationIcon(o), tint: tint, side: tileSize, merchantsOnly: true); details }
          Divider()
          amounts.frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(10).background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
      case "dailyJournal":
        HStack(alignment: .top, spacing: 8) {
          VStack(spacing: 4) {
            Text(o.date.formatted(.dateTime.day())).font(.headline.monospacedDigit())
            Text(o.date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "uk_UA")))).font(.caption2)
          }.foregroundStyle(.secondary).frame(minWidth: 32)
          Rectangle().fill(tint.opacity(0.5)).frame(width: 2).accessibilityHidden(true)
          standard
        }.fixedSize(horizontal: false, vertical: true)
      default: standard
      }
    }.frame(minHeight: 44)
  }
}
struct Operations: View {
  @EnvironmentObject var s: Store
  @State private var search = ""
  @State private var settledSearch = ""
  @State private var edit: Operation?
  @State private var operationSettings = false
  @State private var batchCategories = false
  var filter: String { s.db.preferences?.operationsFilter ?? "all" }
  var sort: OperationSort { OperationSort(rawValue:s.db.preferences?.operationsSort ?? "") ?? .newest }
  var filterBinding:Binding<String>{Binding(get:{filter},set:{v in s.changeAppearance { p in p.operationsFilter=v }})}
  var sortBinding:Binding<OperationSort>{Binding(get:{sort},set:{v in s.changeAppearance { p in p.operationsSort=v.rawValue }})}
  @State private var voice = false
  @State private var scan = false
  @State private var accountFilter = "all"
  @State private var categoryFilter = "all"
  @State private var pageSize = 150
  @State private var usePeriod = false
  @State private var dateFrom = Calendar.current.date(byAdding:.month,value:-1,to:Date()) ?? Date()
  @State private var dateTo = Date()
  @State private var minimum = ""
  @State private var maximum = ""
  @State private var reviewOnly = false
  @State private var bankFilter = "all"
  var filtered: [Operation] {
    let from = usePeriod ? Calendar.current.startOfDay(for:min(dateFrom,dateTo)) : nil
    let end = usePeriod ? Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:max(dateFrom,dateTo))) : nil
    return s.queryHistory(.init(kind:filter,account:accountFilter,category:categoryFilter,search:settledSearch,sort:sort,hideAmounts:s.privateAmounts,from:from,until:end,minimum:bankMinor(minimum),maximum:bankMinor(maximum),reviewOnly:reviewOnly,sourceBank:bankFilter == "all" ? nil : bankFilter))
  }
  var chronological: Bool { sort == .newest || sort == .oldest }
  private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var searchPending: Bool { searchTerm != settledSearch }
  private var activeFilters: Int {
    [filter != "all", accountFilter != "all", categoryFilter != "all", usePeriod,
     !s.privateAmounts && (!minimum.isEmpty || !maximum.isEmpty), reviewOnly, bankFilter != "all"].filter { $0 }.count
  }
  private func resetFilters() {
    if filter != "all" || sort != .newest {
      s.changeAppearance { $0.operationsFilter = "all"; $0.operationsSort = OperationSort.newest.rawValue }
    }
    accountFilter = "all"; categoryFilter = "all"; search = ""; settledSearch = ""
    usePeriod = false; minimum = ""; maximum = ""; reviewOnly = false; bankFilter = "all"; pageSize = 150
  }

  func action(_ kind: Kind, _ title: String, _ icon: String, _ tint: Color) -> some View {
    Button { edit = Operation(kind: kind, account: s.db.accounts.first?.id ?? cash) } label: {
      VStack(spacing: 6) { FinamiIconTile(icon: icon, tint: tint, side: 40); Text(title).font(.caption.weight(.medium)) }.frame(maxWidth: .infinity).padding(.vertical, 6)
    }.buttonStyle(.plain)
  }
  func operationList(_ values: [Operation]) -> some View {
    let style = s.db.preferences?.designStyle(for: "operations")
    return LazyVStack(spacing: style == "merchantCards" ? 6 : 0) {
      ForEach(values) { o in
        Button { edit = o } label: { OperationRow(o: o).padding(.vertical, style == "compactLedger" ? 4 : s.db.preferences?.modernCompactSpacing == true ? 7 : 12).padding(.horizontal, 12).contentShape(Rectangle()) }.buttonStyle(.plain)
          .contextMenu {
            if let draft = FinamiRepeatDraft.make(o, accounts: s.db.accounts, masked: s.privateAmounts) {
              Button { edit = draft } label: { Label("Повторити операцію", systemImage: "doc.on.doc") }
            }
            Button { edit = o } label: { Label("Редагувати", systemImage: "pencil") }
          }
        if o.id != values.last?.id && style != "merchantCards" { Divider().padding(.leading, 62) }
      }
    }.modifier(FinamiCardStyle(tint:.teal))
  }
  private var incomingSection: some View {
    NavigationLink {
      FinamiReportReviewList(ids: [], account: nil, maskAmounts: s.privateAmounts, inboxOnly: true)
    } label: {
      HStack(spacing: 12) {
        FinamiIconTile(icon: "tray.and.arrow.down.fill", tint: .orange, side: 40)
        VStack(alignment: .leading, spacing: 4) {
          Text("Вхідні операції").font(.headline)
          Text(s.capturePending.isEmpty ? "Немає нових операцій" : "Потребують перевірки: \(s.capturePending.count)")
            .font(.caption).foregroundStyle(.secondary)
          if s.captureWarning != nil { Text("Є попередження черги").font(.caption).foregroundStyle(.orange) }
        }
        Spacer(minLength: 0)
        Text(String(s.capturePending.count)).font(.headline.monospacedDigit()).foregroundStyle(.orange)
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
      }.padding(12).frame(minHeight: 44).contentShape(Rectangle())
    }.buttonStyle(.plain).modifier(FinamiCardStyle(tint: .orange))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("qa.operations.inbox")
      .accessibilityValue(String(s.capturePending.count))
  }
  var body: some View {
    let values: [Operation] = searchPending ? [] : filtered
    let displayedValues = Array(values.prefix(pageSize))
    let grouped = Dictionary(grouping: displayedValues) { Calendar.current.startOfDay(for: $0.date) }
    let days = grouped.keys.sorted { sort == .oldest ? $0 < $1 : $0 > $1 }
    ScrollView {
      LazyVStack(alignment: .leading, spacing: (s.db.preferences ?? .init()).finamiSpacing) {
        VStack(alignment: .leading, spacing: 12) {
          FinamiSectionTitle(title: "Журнал операцій", subtitle: searchPending ? "Пошук…" : "\(values.count) записів за вибраними фільтрами", icon: "list.bullet.rectangle.portrait", tint: .teal)
          HStack { action(.expense,"Витрата","minus",.orange); action(.income,"Дохід","plus",.green); action(.transfer,"Переказ","arrow.left.arrow.right",.blue) }
          HStack {
            Button { voice = true } label: { Label("Голос", systemImage: "mic.fill").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.bordered)
            Button { scan = true } label: { Label("Скриншот", systemImage: "doc.viewfinder").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.bordered)
          }
        }.padding(16).modifier(FinamiCardStyle(tint: .teal))
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          TextField("Магазин, категорія, сума", text: $search).accessibilityIdentifier("qa.operations.search")
          if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Очистити пошук") }
        }.padding(12).modifier(FinamiCardStyle(tint: .teal))
        incomingSection
        HStack {
          Picker("Тип", selection: filterBinding) { Text("Усі типи").tag("all"); ForEach(Kind.allCases) { Text($0.title).tag($0.rawValue) }; Text("Зняття готівки").tag("cashWithdrawal") }.pickerStyle(.menu)
          Spacer(minLength: 0)
          Button { operationSettings = true } label: { Label(activeFilters == 0 ? "Фільтри" : "Фільтри (\(activeFilters))", systemImage: "line.3.horizontal.decrease.circle") }.buttonStyle(.bordered)
        }
        if activeFilters > 0 || !searchTerm.isEmpty {
          Button { resetFilters() } label: { Label("Очистити пошук і фільтри", systemImage: "xmark.circle") }
            .font(.subheadline).buttonStyle(.bordered).accessibilityIdentifier("qa.operations.clearFilters")
        }
        if searchPending { ProgressView("Пошук…").frame(maxWidth: .infinity).padding(.vertical, 24) }
        else if values.isEmpty { FinamiEmptyCard(title: "Немає операцій", detail: "Додай запис або зміни фільтри пошуку.", icon: "tray") }
        else if chronological {
          ForEach(days, id: \.self) { day in
            VStack(alignment: .leading, spacing: 8) {
              Text(day.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "uk_UA")))).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
              operationList(grouped[day] ?? [])
            }
          }
        } else { operationList(displayedValues) }
        if values.count > displayedValues.count {
          Button("Показати ще (\(values.count - displayedValues.count))") { pageSize += 150 }.frame(maxWidth: .infinity).buttonStyle(.bordered)
        }
      }.padding()
    }.background(finamiScreenBackground(s.db.preferences)).navigationTitle("Операції")
      .task(id: searchTerm) {
        let term = searchTerm
        if !term.isEmpty {
          do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
        }
        guard !Task.isCancelled, term == searchTerm else { return }
        settledSearch = term; pageSize = 150
      }
      .onChange(of: filter) { _ in pageSize = 150 }
      .onChange(of: sort) { _ in pageSize = 150 }
      .onChange(of: accountFilter) { _ in pageSize = 150 }
      .onChange(of: categoryFilter) { _ in pageSize = 150 }
      .onChange(of: usePeriod) { _ in pageSize = 150 }
      .onChange(of: dateFrom) { _ in pageSize = 150 }
      .onChange(of: dateTo) { _ in pageSize = 150 }
      .onChange(of: minimum) { _ in pageSize = 150 }
      .onChange(of: maximum) { _ in pageSize = 150 }
      .onChange(of: reviewOnly) { _ in pageSize = 150 }
      .onChange(of: bankFilter) { _ in pageSize = 150 }
      .toolbar {
        Button { batchCategories = true } label: { Image(systemName: "checklist") }.accessibilityLabel("Масове уточнення")
        Button { operationSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Налаштування операцій")
        Button { edit = Operation(account: s.db.accounts.first?.id ?? cash) } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Додати операцію")
      }.sheet(item: $edit) { OpEditor(original: $0) }
      .sheet(isPresented: $batchCategories) { FinamiBatchCategoriesView() }
      .sheet(isPresented: $voice) { FinamiVoice() }
      .sheet(isPresented: $scan) { NavigationStack { FinamiScanView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { scan = false } } } } }
      .sheet(isPresented: $operationSettings) {
        NavigationStack { Form {
          FinamiComponentStylePicker(component: "operations", title: "Стиль операцій")
          Picker("Тип", selection: filterBinding) { Text("Усі").tag("all"); ForEach(Kind.allCases) { Text($0.title).tag($0.rawValue) }; Text("Зняття готівки").tag("cashWithdrawal") }
          Picker("Рахунок", selection: $accountFilter) { Text("Усі").tag("all"); ForEach(s.db.accounts) { Text($0.name).tag($0.id) } }
          Picker("Категорія", selection: $categoryFilter) { Text("Усі").tag("all"); ForEach(Array(Set(s.db.operations.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) } }
          Toggle("Потребують уточнення",isOn:$reviewOnly)
          Picker("Банк джерела",selection:$bankFilter){Text("Усі").tag("all");ForEach(Array(Set(s.db.operations.compactMap(\.sourceBank))).sorted(),id:\.self){Text($0).tag($0)}}
          Toggle("Обмежити період",isOn:$usePeriod)
          if usePeriod { DatePicker("Від",selection:$dateFrom,displayedComponents:.date);DatePicker("До",selection:$dateTo,displayedComponents:.date) }
          if !s.privateAmounts { FinamiField("Сума від, ₴",text:$minimum,keyboard:.decimalPad);FinamiField("Сума до, ₴",text:$maximum,keyboard:.decimalPad) }
          Picker("Сортування", selection: sortBinding) { ForEach(OperationSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Button("Скинути фільтри") { resetFilters() }
        }.navigationTitle("Фільтри операцій").toolbar { Button("Готово") { pageSize=150;operationSettings = false } } }
      }
  }
}
struct OpEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var o: Operation
  private let bankIncoming: Bool?
  @State var amount: String
  @State private var confirm = false
  @State private var learnRule = true
  @State private var compensationSearch = ""
  @State private var selectedLearningCategory: String? = nil
  @State private var entryCurrency = "UAH"
  @State private var rate = ""
  @State private var exactReceived = ""
  @State private var linkedPaymentID = ""
  @State private var separatePayment = false
  @State private var tagsText = ""
  @State private var confirmSave = false
  @State private var extraExpanded = false
  @State private var initialConfigured = false
  @State private var calculator = false
  @State private var calculatorInput = ""
  @State private var calculatorMode = "+"
  private var repeatCandidate: Operation? { s.db.operations.filter { $0.kind != .receipt && $0.kind == o.kind && $0.account == o.account && $0.sourceBank == nil && $0.bankKey == nil && $0.groupedBankParts == nil && $0.kind != .transfer && $0.entryCurrency != "USD" && $0.amount > 0 }.max { $0.date < $1.date } }
  private var linkedRecord: FinamiPaidRecord? { s.paymentLookup.record(for: o.id) }
  private var financialLocked: Bool {linkedRecord != nil || o.groupedBankParts != nil}
  private var savedOperation: Bool { s.db.operations.contains { $0.id == o.id } }
  private var paymentChoices: [FinamiPayment] {
    let choices=s.upcomingPayments.filter { $0.currency == sourceCode && $0.amount > 0 }
    guard let suffix=o.creditContractSuffix,suffix.count==4 else{return choices}
    let ids=Set(s.db.obligations.filter{$0.creditContractSuffix==suffix}.map(\.id))
    return choices.filter{ids.contains($0.id)} + choices.filter{!ids.contains($0.id)}
  }
  private var selectedPayment: FinamiPayment? { paymentChoices.first { $0.id == linkedPaymentID } }
  private var nativeAmount: Int64? { sourceCode == "USD" ? bankMinor(amount) : converted }
  private var similarPayments: [Operation] {
    guard let payment = selectedPayment, !savedOperation else { return [] }
    return s.paymentLookup.matches(account: o.account, currency: payment.currency, amount: nativeAmount ?? payment.amount, date: o.date, used: false)
  }
  private var hasRecentSubscriptionPayment: Bool {
    guard let p=selectedPayment, p.subscription, let amount=nativeAmount else { return false }
    return !s.paymentLookup.recent(paymentID:p.id, currency:p.currency, amount:amount, date:o.date).isEmpty
  }
  private var paymentSelectionValid: Bool {
    linkedPaymentID.isEmpty || (editorChoice != .withdrawal && linkedRecord == nil && finamiPaymentDebitKind(o.kind) && selectedPayment.map { p in if let amount=nativeAmount { return amount > 0 && (p.kind == "Розстрочка" ? amount <= (p.remaining ?? 0) : amount == p.amount) };return false } == true && o.date <= Date() && ((similarPayments.isEmpty && !hasRecentSubscriptionPayment) || separatePayment))
  }
  init(original: Operation) {
    _o = State(initialValue: original)
    bankIncoming = (original.sourceBank != nil || original.captureSource != nil || original.scanFingerprint != nil) && original.kind != .transfer ? original.kind.incoming : nil
    _tagsText = State(initialValue: (original.tags ?? []).joined(separator:", "))
    let input = original.entryCurrency == "USD" ? (original.originalAmount ?? original.sourceMinor ?? original.amount) : original.amount
    _amount = State(initialValue: input == 0 ? "" : amountText(input))
    _entryCurrency = State(initialValue: original.entryCurrency ?? "UAH")
    _rate = State(initialValue: original.exchangeRate ?? "")
    _exactReceived = State(initialValue: original.entryCurrency == "USD" && original.kind == .transfer && original.destinationMinor != nil ? amountText(original.destinationMinor ?? 0) : ((original.kind == .income || original.kind == .receipt) && original.entryCurrency == "USD" && original.originalCurrency == "USD" ? amountText(original.amount):""))
  }
  var categories: [String] { if o.kind == .receipt { return Array(Set(s.db.availableReceiptCategories + [o.category])).sorted() }; let list = o.kind == .income ? s.db.incomeCategories : s.db.expenseCategories; let hidden = o.kind == .income ? (s.db.hiddenIncomeCategories ?? []) : (s.db.hiddenExpenseCategories ?? []); let available = list.filter { !hidden.contains($0) || $0 == o.category }; return Array(Set(available + ["Без категорії",o.category])).sorted() }
  private var editorChoice: FinamiOperationChoice { .current(o.kind, withdrawal: o.cashWithdrawal == true) }
  private var cashAccounts: [Account] { s.db.accounts.filter { ($0.id == cash || $0.accountType == "cash") && $0.id != o.account } }
  private var choiceBinding: Binding<FinamiOperationChoice> {
    Binding(get: { editorChoice }, set: { choice in
      guard choice != editorChoice else { return }
      let previous = o.kind
      let next = choice.ledgerKind(bankIncoming: bankIncoming, existing: previous)
      o.kind = next
      if next != previous {
        if previous == .receipt { o.refundOriginalID = nil; o.receiptExpenseCategory = nil }
        o.receiptTreatment = next == .receipt ? .pending : nil
      }
      o.cashWithdrawal = choice == .withdrawal ? true : nil
      if choice == .withdrawal && next == .transfer { o.destination = cashAccounts.first(where: { $0.code == sourceCode })?.id ?? cashAccounts.first?.id ?? "" }
      if next != .transfer { o.destination = "" }
      if next != previous {
        o.category = FinamiCategoryCore.categoryAfterTypeChange(o.category, from: previous, to: next, database: s.db, note: o.note)
        selectedLearningCategory = nil
      }
      if next == .transfer { entryCurrency = sourceCode }
      linkedPaymentID = ""; separatePayment = false
    })
  }
  private var allowedChoices: [FinamiOperationChoice] {
    let choices = FinamiOperationChoice.options(bankIncoming: bankIncoming, current: editorChoice)
    // Do not repurpose a matched two-bank transfer as a cash withdrawal.
    return choices.filter { $0 != .withdrawal || o.destinationBankKey == nil || editorChoice == .withdrawal }
  }
  var sourceCode:String { s.db.accounts.first(where:{$0.id==o.account})?.code ?? "UAH" }
  var destinationCode:String { s.db.accounts.first(where:{$0.id==o.destination})?.code ?? "UAH" }
  private var supportsExactUAH:Bool {o.sourceBank == nil && ((o.kind == .transfer && sourceCode == "USD" && destinationCode == "UAH") || ((o.kind == .income || o.kind == .receipt) && sourceCode == "UAH" && entryCurrency == "USD"))}
  private var exactMode:Bool {supportsExactUAH && !exactReceived.isEmpty}
  var requiresRate:Bool { entryCurrency == "USD" || (o.kind == .transfer && destinationCode == "USD") }
  var usedRate:Decimal? {if exactMode,let n=bankMinor(amount),n>0,let actual=bankMinor(exactReceived),actual>0{return Decimal(actual)/Decimal(n)};return fxRate(rate)}
  var converted:Int64? {
    guard let n=bankMinor(amount), n>0 else{return nil}
    if exactMode {guard let actual=bankMinor(exactReceived),actual>0 else{return nil};return actual}
    if entryCurrency == "USD" {guard let r=usedRate else{return nil};return fxMinor(n,rate:r)}
    return n
  }
  var received:Int64? {
    guard let uah=converted else{return nil}
    if destinationCode == "USD" {if sourceCode == "USD" {return bankMinor(amount)};guard let r=usedRate else{return nil};return fxMinor(uah,rate:r,divide:true)}
    return uah
  }
  private var compensationDraft: Operation {
    var draft = o; draft.amount = converted ?? 0; draft.sourceMinor = nativeAmount; draft.entryCurrency = entryCurrency
    return draft
  }
  private var compensationChoices: [Operation] {
    guard o.kind == .receipt, o.receiptTreatment == .reimbursement else { return [] }
    return finamiCompensationChoices(compensationDraft, operations: s.db.operations, accounts: s.db.accounts)
  }
  private var compensationValid: Bool {
    o.kind != .receipt || o.receiptTreatment != .reimbursement || compensationChoices.contains { $0.id == o.refundOriginalID }
  }
  private func setTreatment(_ treatment: FinamiReceiptTreatment) {
    o.receiptTreatment = treatment
    if treatment != .reimbursement { o.refundOriginalID = nil; o.receiptExpenseCategory = nil }
  }
  var valid: Bool {
    compensationValid && paymentSelectionValid && (converted ?? 0)>0 && s.db.accounts.contains { $0.id == o.account } && (!requiresRate || usedRate.map{fxRate(finamiFXRateText($0)) != nil} == true)
      && (sourceCode != "USD" || entryCurrency == "USD")
      && (editorChoice != .withdrawal || o.kind != .transfer || cashAccounts.contains { $0.id == o.destination })
      && (o.kind != .transfer || (o.account != o.destination && s.db.accounts.contains { $0.id == o.destination } && (received ?? 0)>0 && entryCurrency == sourceCode))
  }
  private var editorStyle: String { s.db.preferences?.designStyle(for: "editor") ?? "original" }
  private func rememberAccount() { if s.db.preferences?.designEditorLastAccountEnabled == true && o.sourceBank == nil { s.changeAppearance { $0.designEditorLastAccount = o.account } } }
  private func selectCategory(_ category: String) {
    o.category = category; selectedLearningCategory = category
    if o.kind == .receipt && o.receiptTreatment != .reimbursement { setTreatment(FinamiReceiptTreatment.suggestion(category)) }
  }
  private func saveOperation() {
            if o.groupedBankParts != nil { if s.change({d in if let i=d.operations.firstIndex(where:{$0.id==o.id}) {d.operations[i].note=o.note;d.operations[i].tags=o.tags}}) {dismiss()};return }
            guard let n=converted, let entered=bankMinor(amount), valid else {return}
            o.amount=n
            if o.sourceBank != nil {o.classificationReviewed=true}
            if !o.kind.isReportCategory {o.category="Без категорії"}
            if o.kind != .receipt { o.receiptTreatment = nil; o.receiptExpenseCategory = nil }
            o.sourceMinor=sourceCode == "USD" ? entered : n
            o.destinationMinor=o.kind == .transfer ? received : nil
            o.entryCurrency=entryCurrency
            o.exchangeRate=requiresRate ? (exactMode ? usedRate.map{finamiFXRateText($0)}:rate) : nil
            if o.sourceBank == nil {o.originalAmount=entered;o.originalCurrency=entryCurrency}
            if !linkedPaymentID.isEmpty {
              guard let payment = selectedPayment else { return }
              if s.confirmPayment(payment, mode: .newOperation, accountID: o.account, operationID: o.id, paidDate: o.date, kind: o.kind, allowSeparate: separatePayment, operationDraft: o, learnCategory: learnRule && selectedLearningCategory == o.category && o.category != "Без категорії", actualAmount: o.sourceMinor ?? o.amount) { rememberAccount(); dismiss() }
              return
            }
            if s.change({ d in
              d.operations.removeAll { $0.id == o.id }
              d.operations.append(o)
              if learnRule && selectedLearningCategory == o.category && o.category != "Без категорії" && (o.kind == .expense || o.kind == .income || o.kind == .receipt) && !o.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var rules = d.merchantRules ?? [:]; finamiRememberMerchant(o.note, kind: o.kind, category: o.category, rules: &rules); d.merchantRules = rules
              }
            }) {
              rememberAccount(); dismiss()
            }
  }
  @ViewBuilder private var editorHeaderFields: some View {
    if editorStyle != "original" {
      VStack(alignment: .leading, spacing: 8) {
        Text(o.displayKindTitle).font(.caption).foregroundStyle(.secondary)
        Text(s.privateAmounts ? "••••" : amount.isEmpty ? "0" : amount).font(editorStyle == "minimal" ? .title2.bold() : .largeTitle.bold()).monospacedDigit()
        if editorStyle == "bankingPro" { Label(s.accountName(o.account), systemImage: "wallet.pass") }
        if editorStyle == "smartEntry" { Label("Категорія: " + suggestedCategory(o.note, kind: o.kind, database: s.db), systemImage: "sparkles").font(.caption) }
      }.frame(maxWidth: .infinity, alignment: editorStyle == "minimal" ? .leading : .center).padding(8)
    }
    Picker("Тип", selection: choiceBinding) { ForEach(allowedChoices) { Text($0.title).tag($0) } }
      .pickerStyle(.menu).disabled(financialLocked)
    if editorChoice == .legacy { Text("Збережений тип: " + o.kind.title + ". Облік не зміниться, якщо залишити цей тип.").font(.caption).foregroundStyle(.secondary) }
    if editorChoice == .income { Text("Зарплата, кешбек та інші надходження — категорії одного типу «Дохід».").font(.caption).foregroundStyle(.secondary) }
    if editorChoice == .withdrawal && o.kind == .movementOut { Text("Банківське списання позначено як зняття готівки. Готівковий рахунок автоматично не поповнюється, щоб не дублювати рух коштів.").font(.caption).foregroundStyle(.secondary) }
    if editorChoice == .withdrawal && o.kind == .transfer && cashAccounts.isEmpty { Text("Спочатку додай готівковий рахунок.").font(.caption).foregroundStyle(.orange) }
    if o.kind.needsReview { Text("Не входить у доходи чи витрати до уточнення. Баланс враховує рух коштів.").font(.caption) }
  }
  @ViewBuilder private var editorAmountFields: some View {
    FinamiField("Сума, \(entryCurrency)", text: $amount, keyboard: .decimalPad).disabled(financialLocked)
    if !financialLocked && s.db.preferences?.designEditorKeyboard == true { FinamiDesignKeyboard(amount: $amount, haptics: s.db.preferences?.designEditorHaptics != false) }
    if !financialLocked && !savedOperation && editorStyle == "quickEntry" && sourceCode == "UAH", let recent = repeatCandidate {
      Button("Повторити останню ручну операцію") { amount = amountText(recent.amount); entryCurrency = "UAH"; if categories.contains(recent.category) { o.category = recent.category }; o.note = recent.note; tagsText = (recent.tags ?? []).joined(separator: ", "); linkedPaymentID = "" }.font(.caption)
    }
    if !financialLocked && editorStyle != "original" {
      Button("Калькулятор суми") { calculatorInput = ""; calculator = true }.font(.caption)
    }
  }
  @ViewBuilder private var editorAccountFields: some View {
    if editorStyle == "quickEntry" || editorStyle == "bankingPro" {
      ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(s.db.accounts.filter { o.sourceBank == nil || $0.code == "UAH" }) { account in
        Button { o.account = account.id } label: { Label(account.name, systemImage: o.account == account.id ? "checkmark.circle.fill" : "wallet.pass").font(.caption).padding(10).frame(minHeight: 44).background(Color.accentColor.opacity(o.account == account.id ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).disabled(financialLocked)
      } } }
    }
    if o.kind != .transfer && sourceCode == "UAH" && o.sourceBank == nil {
      Picker("Валюта введення",selection:$entryCurrency){Text("Гривня").tag("UAH");Text("Долар").tag("USD")}.disabled(financialLocked)
    }
    if requiresRate { FinamiField("Курс UAH за 1 USD", text: $rate, keyboard: .decimalPad).disabled(financialLocked); if let n=converted { LabeledContent("Сума у гривнях",value:money(n)) } }
    if supportsExactUAH && (o.kind == .income || o.kind == .receipt) {FinamiField("Фактично отримано UAH (необов’язково)",text:$exactReceived,keyboard:.decimalPad).disabled(financialLocked)}
    DatePicker("Дата і час", selection: $o.date, displayedComponents: [.date,.hourAndMinute]).disabled(financialLocked)
    Picker("Рахунок", selection: $o.account) {
      ForEach(s.db.accounts.filter{o.sourceBank == nil || $0.code == "UAH"}) { Text($0.name).tag($0.id) }
    }.disabled(financialLocked)
  }
  @ViewBuilder private var editorCategoryFields: some View {
    if o.kind == .transfer {
      Picker(editorChoice == .withdrawal ? "Готівковий рахунок" : "Куди", selection: $o.destination) {
        Text("Вибрати").tag("")
        ForEach(editorChoice == .withdrawal ? cashAccounts : s.db.accounts) { Text($0.name).tag($0.id) }
      }.disabled(financialLocked)
      if sourceCode == "USD" && destinationCode == "UAH" && o.sourceBank == nil {FinamiField("Фактично отримано UAH (необов’язково)",text:$exactReceived,keyboard:.decimalPad).disabled(financialLocked);if exactMode {Text("Сума зарахування має пріоритет над введеним курсом.").font(.caption)}}
      if let n=received, !o.destination.isEmpty { LabeledContent("Зарахувати",value:currencyMoney(n,destinationCode)) }
    } else if o.kind.isReportCategory {
      Picker("Категорія", selection: Binding(get: { o.category }, set: { selectCategory($0) })) {
        ForEach(categories, id: \.self) { Text($0).tag($0) }
      }
      if editorStyle != "original" && editorStyle != "minimal" {
        let favorites = (s.db.preferences?.designEditorFavorites ?? []).filter { categories.contains($0) }
        let recent = Array(Set(s.db.operations.suffix(150).filter { $0.kind == o.kind && categories.contains($0.category) }.map(\.category))).sorted()
        ScrollView(.horizontal, showsIndicators: false) { HStack {
          ForEach(Array((favorites + recent.filter { !favorites.contains($0) }).prefix(10)), id: \.self) { category in
            Button { selectCategory(category) } label: { Label(category, systemImage: favorites.contains(category) ? "star.fill" : "clock").font(.caption).padding(8).frame(minHeight:44).background(Color.accentColor.opacity(o.category == category ? 0.18 : 0.05),in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
          }
        } }
        Button(favorites.contains(o.category) ? "Прибрати з обраних" : "Додати категорію в обрані") { s.changeAppearance { p in var list = Set(p.designEditorFavorites ?? []); if list.contains(o.category) { list.remove(o.category) } else { list.insert(o.category) }; p.designEditorFavorites = list.sorted() } }.font(.caption)
      }
    }
  }
  private var visibleCompensations: [Operation] {
    let selectedID = o.refundOriginalID
    let query = compensationSearch
    let matches = compensationChoices.filter { operation in
      if operation.id == selectedID || query.isEmpty { return true }
      return operation.note.localizedCaseInsensitiveContains(query) || operation.category.localizedCaseInsensitiveContains(query)
    }
    return Array(matches.prefix(100))
  }
  private var receiptTreatmentBinding: Binding<FinamiReceiptTreatment> {
    Binding(get: { o.receiptTreatment ?? .pending }, set: { setTreatment($0) })
  }
  private var compensationSelection: Binding<String> {
    Binding(get: { o.refundOriginalID ?? "" }, set: { value in
      o.refundOriginalID = value.isEmpty ? nil : value
    })
  }
  private func compensationTitle(_ original: Operation) -> String {
    let dateText = original.date.formatted(date: .abbreviated, time: .omitted)
    let accountHidden = s.db.accounts.contains { account in
      account.id == original.account && account.hideAmounts == true
    }
    let amountText = accountHidden ? "••••" : s.visibleMoney(original.amount)
    return [dateText, original.category, amountText].joined(separator: " · ")
  }
  private var compensationPicker: some View {
    let visible = visibleCompensations
    return Picker("Початкова витрата", selection: compensationSelection) {
      Text("Обрати").tag("")
      ForEach(visible) { original in
        Text(compensationTitle(original)).tag(original.id)
      }
      if let id = o.refundOriginalID, !visible.contains(where: { $0.id == id }) {
        Text("Раніше вибрана витрата").tag(id)
      }
    }
  }
  @ViewBuilder private var editorReceiptFields: some View {
    if o.kind == .receipt {
      Section("Облік зарахування") {
        Picker("У звітах", selection: receiptTreatmentBinding) {
          ForEach(FinamiReceiptTreatment.allCases) { Text($0.title).tag($0) }
        }.disabled(financialLocked).accessibilityIdentifier("qa.receipt.treatment")
        if o.receiptTreatment == .reimbursement {
          TextField("Пошук початкової витрати", text: $compensationSearch)
          compensationPicker
          if !compensationValid { Text("Обери витрату UAH, яка ще не була компенсована повністю.").font(.caption).foregroundStyle(.orange) }
        }
        Text("Баланс рахунку збільшується завжди. Компенсація зменшує витрати початкової категорії. Позики не створюють договір автоматично.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  @ViewBuilder private var editorPaymentFields: some View {
    if let parts=o.groupedBankParts {
      Section("Звірені надходження") {Text("\(parts.count) банківських рядків. Для зміни суми або рахунку спочатку скасуй групову звірку.").font(.caption);ForEach(Array(parts.enumerated()),id:\.offset){_,part in LabeledContent(part.date.formatted(date:.abbreviated,time:.shortened),value:s.visibleMoney(part.amount))}}
    } else if let record = linkedRecord {
      Section("Пов’язаний платіж") {
        LabeledContent("Оплачено", value: s.db.obligations.first(where: { $0.id == record.paymentID })?.name ?? s.db.subscriptions?.first(where: { $0.id == record.paymentID })?.name ?? "Платіж з історії").accessibilityIdentifier("qa.operation.linked")
        LabeledContent("Дата оплати",value:record.paidDate.formatted(date:.abbreviated,time:.omitted))
        if o.kind == .expense, s.db.subscriptions?.contains(where:{$0.id == record.paymentID}) == true,
           o.category != "📺 Підписки", categories.contains("📺 Підписки") {
          Button("Встановити категорію «Підписки»") { o.category = "📺 Підписки"; selectedLearningCategory = nil }
            .accessibilityIdentifier("qa.operation.subscriptionCategory")
          Text("Збережи категорію без повторної оплати.").font(.caption).foregroundStyle(.secondary)
        }
        Text("Ця операція вже оновила графік. Фінансові поля та видалення захищені від випадкової зміни; примітку й категорію можна редагувати.").font(.caption)
      }
    } else if editorChoice != .withdrawal && finamiPaymentDebitKind(o.kind) {
      Section("Пов’язати з платежем") {
        Picker("Розстрочка, кредит або підписка", selection: $linkedPaymentID) {
          Text("Не пов’язувати").tag("")
          ForEach(paymentChoices) { p in Text(p.kind + " · " + p.name + " · " + s.visibleMoney(p.amount, p.currency)).tag(p.id) }
        }.accessibilityIdentifier("qa.operation.payment")
        if paymentChoices.isEmpty { Text("Немає активних платежів у валюті цього рахунку.").font(.caption) }
        if let payment = selectedPayment {
          Button("Підставити суму платежу") { amount = amountText(payment.amount); entryCurrency = sourceCode }.disabled(o.sourceBank != nil)
          if nativeAmount != payment.amount { Text(payment.kind == "Розстрочка" ? "Часткова або дострокова оплата: перевір графік банку." : "Сума має дорівнювати плановому платежу.").font(.caption).foregroundStyle(.orange) }
          if !similarPayments.isEmpty || hasRecentSubscriptionPayment { Toggle("Це окрема нова оплата", isOn: $separatePayment); Text("Є схожа або вже записана оплата. Підтвердь лише якщо це інший платіж.").font(.caption).foregroundStyle(.orange) }
          Text("Збереження оновить рахунок, залишок договору, наступну дату та нагадування одним записом.").font(.caption)
          if o.kind == .transfer { Text("Прив’язуй переказ лише якщо це фактична оплата договору, а не звичайне поповнення кредитної картки.").font(.caption).foregroundStyle(.orange) }
        }
      }
    }
  }
  @ViewBuilder private var editorMetadataFields: some View {
    TextField("Теги через кому", text:$tagsText).onChange(of:tagsText) { value in o.tags=finamiCleanTags(value) }
    if !(o.tags ?? []).isEmpty {Text((o.tags ?? []).map{"#"+$0}.joined(separator:"  ")).font(.caption).foregroundStyle(.secondary)}
    if let bank = o.sourceBank { LabeledContent("Джерело", value: bank) }
    if let suffix=o.creditContractSuffix {LabeledContent("Договір",value:"••"+suffix)}
    if o.bankPostingKnown == true {LabeledContent("Дата постінгу",value:o.bankPostingDate?.formatted(date:.abbreviated,time:.omitted) ?? "Невідомо — звірити з банком")}
    if let description = o.destinationBankNote { LabeledContent("Опис другої сторони",value:description) }
    LabeledContent("Джерело запису", value: o.sourceLabel)
  }
  @ViewBuilder private var editorAttachmentFields: some View {
    if let imageID = o.scanImageID { NavigationLink("Вкладений скриншот") { FinamiScanAttachment(imageID: imageID) } }
    if let n = o.originalAmount, let c = o.originalCurrency { LabeledContent("Оригінальна сума", value: currencyMoney(n,c)) }
    if let fee = o.bankFee, fee > 0 { LabeledContent("Комісія у виписці", value: money(fee)) }
    if o.kind == .expense || o.kind == .income || o.kind == .receipt {
      Button("Визначити категорію") { o.category = suggestedCategory(o.note, kind: o.kind, database: s.db) }
      Toggle("Запам’ятати категорію для цього продавця", isOn: $learnRule)
    }
  }
  @ViewBuilder private var editorExtraFields: some View {
    TextField("Магазин / примітка", text: $o.note)
    DisclosureGroup("Додаткові параметри", isExpanded: $extraExpanded) {
      editorMetadataFields
      editorAttachmentFields
    }
    if savedOperation && !financialLocked {
      Button("Видалити операцію", role: .destructive) { confirm = true }
    }
  }
  private var editorForm: some View {
    Form {
      editorHeaderFields
      editorAmountFields
      editorAccountFields
      editorCategoryFields
      editorReceiptFields
      editorPaymentFields
      editorExtraFields
    }
  }
  private var calculatorSheet: some View {
    NavigationStack {
      Form {
        LabeledContent("Початкова сума", value: amount)
        Picker("Дія", selection: $calculatorMode) { ForEach(["+","−","×","÷"],id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
        FinamiField("Друге число", text: $calculatorInput, keyboard: .decimalPad)
        Button("Застосувати") { if let result = FinamiDesignPolicy.calculate(amount, calculatorInput, operation: calculatorMode) { amount = result; calculator = false } }.disabled(FinamiDesignPolicy.calculate(amount, calculatorInput, operation: calculatorMode) == nil)
      }.navigationTitle("Калькулятор").toolbar { Button("Скасувати") { calculator = false } }
    }
  }
  private var titledEditor: some View {
    editorForm.navigationTitle("Операція").navigationBarTitleDisplayMode(.inline).toolbar {
    ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
    ToolbarItem(placement: .confirmationAction) {
      Button("Зберегти") { if s.db.preferences?.designEditorConfirm == true { confirmSave = true } else { saveOperation() } }.disabled(o.groupedBankParts == nil && !valid)
    }
    }
  }
  private var configuredEditor: some View {
    titledEditor.onAppear {
    if !initialConfigured {
      initialConfigured = true
      extraExpanded = editorStyle == "original"
      if !savedOperation && o.sourceBank == nil && o.amount == 0 && s.db.preferences?.designEditorLastAccountEnabled == true, let id = s.db.preferences?.designEditorLastAccount, s.db.accounts.contains(where: { $0.id == id }) { o.account = id }
    }
    if sourceCode == "USD" {entryCurrency="USD"};if rate.isEmpty {rate=s.db.currencyPreferences?.usdRate ?? ""}
    }
    .alert("Підтвердити збереження?", isPresented: $confirmSave) { Button("Зберегти") { saveOperation() }; Button("Скасувати", role: .cancel) {} }
    .sheet(isPresented: $calculator) { calculatorSheet }
  }
  var body: some View {
    NavigationStack {
      configuredEditor
      .onChange(of:o.account) { _ in entryCurrency=sourceCode; linkedPaymentID=""; separatePayment=false; if editorChoice == .withdrawal && o.kind == .transfer && !cashAccounts.contains(where: { $0.id == o.destination }) { o.destination = cashAccounts.first(where: { $0.code == sourceCode })?.id ?? cashAccounts.first?.id ?? "" } }
      .onChange(of:linkedPaymentID) { _ in separatePayment=false }
      .onChange(of:amount) { _ in separatePayment=false }
      .onChange(of:o.date) { _ in separatePayment=false }
      .onChange(of:o.note) { newNote in
        selectedLearningCategory = nil
        if o.kind.isReportCategory && o.category == "Без категорії" && !savedOperation {
          let suggestion = suggestedCategory(newNote,kind:o.kind,database:s.db)
          if categories.contains(suggestion) { o.category = suggestion }
        }
      }
      .onChange(of: o.kind) { _ in
        selectedLearningCategory = nil
        if !finamiPaymentDebitKind(o.kind) { linkedPaymentID="" }; separatePayment=false
        if o.kind == .transfer {entryCurrency=sourceCode}
        if !categories.contains(o.category) { o.category = categories.first ?? "Інше" }
      }.confirmationDialog("Видалити запис?", isPresented: $confirm, titleVisibility: .visible) {
        Button("Видалити", role: .destructive) {
          if s.change({ $0.operations.removeAll { $0.id == o.id } }) { dismiss() }
        }
      }
    }
  }
}
