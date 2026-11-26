import SwiftUI

struct OperationRow: View {
  @EnvironmentObject var s: Store
  @Environment(\.finamiMask) private var masked
  var o: Operation
  var body: some View {
    HStack {
      FinamiIconTile(icon: finamiOperationIcon(o), tint: o.kind == .income ? .green : o.kind == .expense ? .orange : .blue, side: 42)
      VStack(alignment: .leading) {
        Text(o.note.isEmpty ? (o.kind == .transfer ? "Переказ" : o.category) : finamiMerchantDisplay(o.note)).font(
          .subheadline.bold())
        Text("\(o.kind.title) · \(s.accountName(o.account)) · \(o.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "uk_UA"))))")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment:.trailing) {
        Text((s.privateAmounts || masked) ? "••••" : (o.kind == .transfer ? "" : o.kind.incoming ? "+" : "−") + money(o.amount)).font(.subheadline.bold()).foregroundStyle(o.kind == .income ? Color.green : Color.primary)
        if let n=o.originalAmount, let code=o.originalCurrency, code != "UAH" { Text(masked ? "••••" : s.visibleMoney(n,code)).font(.caption).foregroundStyle(.secondary) }
      }
    }
  }
}
struct Operations: View {
  @EnvironmentObject var s: Store
  @State private var search = ""
  @State private var edit: Operation?
  @State private var operationSettings = false
  var filter: String { s.db.preferences?.operationsFilter ?? "all" }
  var sort: OperationSort { OperationSort(rawValue:s.db.preferences?.operationsSort ?? "") ?? .newest }
  var filterBinding:Binding<String>{Binding(get:{filter},set:{v in s.changeAppearance { p in p.operationsFilter=v }})}
  var sortBinding:Binding<OperationSort>{Binding(get:{sort},set:{v in s.changeAppearance { p in p.operationsSort=v.rawValue }})}
  @State private var voice = false
  @State private var scan = false
  @State private var accountFilter = "all"
  @State private var categoryFilter = "all"
  @State private var pageSize = 150
  var filtered: [Operation] {
    s.queryHistory(.init(kind:filter,account:accountFilter,category:categoryFilter,search:search,sort:sort,hideAmounts:s.privateAmounts))
  }
  var chronological: Bool { sort == .newest || sort == .oldest }

  func action(_ kind: Kind, _ title: String, _ icon: String, _ tint: Color) -> some View {
    Button { edit = Operation(kind: kind, account: s.db.accounts.first?.id ?? cash) } label: {
      VStack(spacing: 6) { FinamiIconTile(icon: icon, tint: tint, side: 40); Text(title).font(.caption.weight(.medium)) }.frame(maxWidth: .infinity).padding(.vertical, 6)
    }.buttonStyle(.plain)
  }
  func operationList(_ values: [Operation]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(values) { o in
        Button { edit = o } label: { OperationRow(o: o).padding(.vertical, 12).padding(.horizontal, 12).contentShape(Rectangle()) }.buttonStyle(.plain)
        if o.id != values.last?.id { Divider().padding(.leading, 62) }
      }
    }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }
  var body: some View {
    let values = filtered
    let displayedValues = Array(values.prefix(pageSize))
    let grouped = Dictionary(grouping: displayedValues) { Calendar.current.startOfDay(for: $0.date) }
    let days = grouped.keys.sorted { sort == .oldest ? $0 < $1 : $0 > $1 }
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 12) {
          FinamiSectionTitle(title: "Журнал операцій", subtitle: "\(values.count) записів за вибраними фільтрами", icon: "list.bullet.rectangle.portrait", tint: .teal)
          HStack { action(.expense,"Витрата","minus",.orange); action(.income,"Дохід","plus",.green); action(.transfer,"Переказ","arrow.left.arrow.right",.blue) }
          HStack {
            Button { voice = true } label: { Label("Голос", systemImage: "mic.fill").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.bordered)
            Button { scan = true } label: { Label("Скриншот", systemImage: "doc.viewfinder").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.bordered)
          }
        }.padding(16).modifier(FinamiCardStyle(tint: .teal))
        HStack {
          Picker("Тип", selection: filterBinding) { Text("Усі типи").tag("all"); ForEach(Kind.allCases) { Text($0.title).tag($0.rawValue) } }.pickerStyle(.menu)
          Spacer(minLength: 0)
          Button { operationSettings = true } label: { Label("Фільтри", systemImage: "line.3.horizontal.decrease.circle") }.buttonStyle(.bordered)
        }
        if values.isEmpty { FinamiEmptyCard(title: "Немає операцій", detail: "Додай запис або зміни фільтри пошуку.", icon: "tray") }
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
    }.background(Color(uiColor: .systemGroupedBackground)).searchable(text: $search, prompt: "Магазин, категорія, сума").navigationTitle("Операції")
      .onChange(of: search) { _ in pageSize = 150 }
      .onChange(of: filter) { _ in pageSize = 150 }
      .onChange(of: sort) { _ in pageSize = 150 }
      .onChange(of: accountFilter) { _ in pageSize = 150 }
      .onChange(of: categoryFilter) { _ in pageSize = 150 }
      .toolbar {
        Button { operationSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Налаштування операцій")
        Button { edit = Operation(account: s.db.accounts.first?.id ?? cash) } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Додати операцію")
      }.sheet(item: $edit) { OpEditor(original: $0) }
      .sheet(isPresented: $voice) { FinamiVoice() }
      .sheet(isPresented: $scan) { NavigationStack { FinamiScanView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { scan = false } } } } }
      .sheet(isPresented: $operationSettings) {
        NavigationStack { Form {
          Picker("Тип", selection: filterBinding) { Text("Усі").tag("all"); ForEach(Kind.allCases) { Text($0.title).tag($0.rawValue) } }
          Picker("Рахунок", selection: $accountFilter) { Text("Усі").tag("all"); ForEach(s.db.accounts) { Text($0.name).tag($0.id) } }
          Picker("Категорія", selection: $categoryFilter) { Text("Усі").tag("all"); ForEach(Array(Set(s.db.operations.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) } }
          Picker("Сортування", selection: sortBinding) { ForEach(OperationSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          Button("Скинути фільтри") { filterBinding.wrappedValue = "all"; sortBinding.wrappedValue = .newest; accountFilter = "all"; categoryFilter = "all"; search = "" }
        }.navigationTitle("Фільтри операцій").toolbar { Button("Готово") { operationSettings = false } } }
      }
  }
}
struct OpEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var o: Operation
  @State var amount: String
  @State private var confirm = false
  @State private var learnRule = false
  @State private var entryCurrency = "UAH"
  @State private var rate = ""
  @State private var exactReceived = ""
  @State private var linkedPaymentID = ""
  @State private var separatePayment = false
  private var linkedRecord: FinamiPaidRecord? { (s.db.paidRecords ?? []).first { $0.operationID == o.id } }
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
    return finamiEligiblePaymentOperations(s.db.operations, records: s.db.paidRecords ?? [], account: o.account, currency: payment.currency, amount: nativeAmount ?? payment.amount, date: o.date)
  }
  private var paymentSelectionValid: Bool {
    linkedPaymentID.isEmpty || (linkedRecord == nil && finamiPaymentDebitKind(o.kind) && selectedPayment.map { p in if let amount=nativeAmount { return amount > 0 && (p.kind == "Розстрочка" ? amount <= (p.remaining ?? 0) : amount == p.amount) };return false } == true && o.date <= Date() && (similarPayments.isEmpty || separatePayment))
  }
  init(original: Operation) {
    _o = State(initialValue: original)
    let input = original.entryCurrency == "USD" ? (original.originalAmount ?? original.sourceMinor ?? original.amount) : original.amount
    _amount = State(initialValue: input == 0 ? "" : amountText(input))
    _entryCurrency = State(initialValue: original.entryCurrency ?? "UAH")
    _rate = State(initialValue: original.exchangeRate ?? "")
    _exactReceived = State(initialValue: original.entryCurrency == "USD" && original.kind == .transfer && original.destinationMinor != nil ? amountText(original.destinationMinor ?? 0) : (original.kind == .income && original.entryCurrency == "USD" && original.originalCurrency == "USD" ? amountText(original.amount):""))
  }
  var categories: [String] { let list = o.kind == .income ? s.db.incomeCategories : s.db.expenseCategories; let hidden = o.kind == .income ? (s.db.hiddenIncomeCategories ?? []) : (s.db.hiddenExpenseCategories ?? []); let available = list.filter { !hidden.contains($0) || $0 == o.category }; return Array(Set(available + ["Без категорії",o.category])).sorted() }
  var allowedKinds: [Kind] {
    if o.sourceBank != nil && o.kind != .transfer {return Kind.allCases.filter{$0 != .transfer && $0.incoming == o.kind.incoming}}
    return Kind.allCases
  }
  var sourceCode:String { s.db.accounts.first(where:{$0.id==o.account})?.code ?? "UAH" }
  var destinationCode:String { s.db.accounts.first(where:{$0.id==o.destination})?.code ?? "UAH" }
  private var supportsExactUAH:Bool {o.sourceBank == nil && ((o.kind == .transfer && sourceCode == "USD" && destinationCode == "UAH") || (o.kind == .income && sourceCode == "UAH" && entryCurrency == "USD"))}
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
  var valid: Bool {
    paymentSelectionValid && (converted ?? 0)>0 && s.db.accounts.contains { $0.id == o.account } && (!requiresRate || usedRate.map{fxRate(finamiFXRateText($0)) != nil} == true)
      && (sourceCode != "USD" || entryCurrency == "USD")
      && (o.kind != .transfer || (o.account != o.destination && s.db.accounts.contains { $0.id == o.destination } && (received ?? 0)>0 && entryCurrency == sourceCode))
  }
  var body: some View {
    NavigationStack {
      Form {
        Picker("Тип", selection: $o.kind) { ForEach(allowedKinds) { Text($0.title).tag($0) } }
          .pickerStyle(.menu).disabled(financialLocked)
        if o.kind.needsReview { Text("Не входить у доходи чи витрати до уточнення. Баланс враховує рух коштів.").font(.caption) }
        FinamiField("Сума, \(entryCurrency)", text: $amount, keyboard: .decimalPad).disabled(financialLocked)
        if o.kind != .transfer && sourceCode == "UAH" && o.sourceBank == nil {
          Picker("Валюта введення",selection:$entryCurrency){Text("Гривня").tag("UAH");Text("Долар").tag("USD")}.disabled(financialLocked)
        }
        if requiresRate { FinamiField("Курс UAH за 1 USD", text: $rate, keyboard: .decimalPad).disabled(financialLocked); if let n=converted { LabeledContent("Сума у гривнях",value:money(n)) } }
        if supportsExactUAH && o.kind == .income {FinamiField("Фактично отримано UAH (необов’язково)",text:$exactReceived,keyboard:.decimalPad).disabled(financialLocked)}
        DatePicker("Дата і час", selection: $o.date, displayedComponents: [.date,.hourAndMinute]).disabled(financialLocked)
        Picker("Рахунок", selection: $o.account) {
          ForEach(s.db.accounts.filter{o.sourceBank == nil || $0.code == "UAH"}) { Text($0.name).tag($0.id) }
        }.disabled(financialLocked)
        if o.kind == .transfer {
          Picker("Куди", selection: $o.destination) {
            Text("Вибрати").tag("")
            ForEach(s.db.accounts) { Text($0.name).tag($0.id) }
          }.disabled(financialLocked)
          if sourceCode == "USD" && destinationCode == "UAH" && o.sourceBank == nil {FinamiField("Фактично отримано UAH (необов’язково)",text:$exactReceived,keyboard:.decimalPad).disabled(financialLocked);if exactMode {Text("Сума зарахування має пріоритет над введеним курсом.").font(.caption)}}
          if let n=received, !o.destination.isEmpty { LabeledContent("Зарахувати",value:currencyMoney(n,destinationCode)) }
        } else if o.kind.isReportCategory {
          Picker("Категорія", selection: $o.category) {
            ForEach(categories, id: \.self) { Text($0).tag($0) }
          }
        }
        if let parts=o.groupedBankParts {
          Section("Звірені надходження") {Text("\(parts.count) банківських рядків. Для зміни суми або рахунку спочатку скасуй групову звірку.").font(.caption);ForEach(Array(parts.enumerated()),id:\.offset){_,part in LabeledContent(part.date.formatted(date:.abbreviated,time:.shortened),value:s.visibleMoney(part.amount))}}
        } else if let record = linkedRecord {
          Section("Пов’язаний платіж") {
            LabeledContent("Оплачено", value: s.db.obligations.first(where: { $0.id == record.paymentID })?.name ?? s.db.subscriptions?.first(where: { $0.id == record.paymentID })?.name ?? "Платіж з історії").accessibilityIdentifier("qa.operation.linked")
            Text("Ця операція вже оновила графік. Фінансові поля та видалення захищені від випадкової зміни; примітку й категорію можна редагувати.").font(.caption)
          }
        } else if finamiPaymentDebitKind(o.kind) {
          Section("Пов’язати з платежем") {
            Picker("Розстрочка, кредит або підписка", selection: $linkedPaymentID) {
              Text("Не пов’язувати").tag("")
              ForEach(paymentChoices) { p in Text(p.kind + " · " + p.name + " · " + s.visibleMoney(p.amount, p.currency)).tag(p.id) }
            }.accessibilityIdentifier("qa.operation.payment")
            if paymentChoices.isEmpty { Text("Немає активних платежів у валюті цього рахунку.").font(.caption) }
            if let payment = selectedPayment {
              Button("Підставити суму платежу") { amount = amountText(payment.amount); entryCurrency = sourceCode }.disabled(o.sourceBank != nil)
              if nativeAmount != payment.amount { Text(payment.kind == "Розстрочка" ? "Часткова або дострокова оплата: перевір графік банку." : "Сума має дорівнювати плановому платежу.").font(.caption).foregroundStyle(.orange) }
              if !similarPayments.isEmpty { Toggle("Це окрема нова оплата", isOn: $separatePayment); Text("Є схожа операція. Якщо оплату вже записано, відкрий її та прив’яжи платіж там.").font(.caption).foregroundStyle(.orange) }
              Text("Збереження оновить рахунок, залишок договору, наступну дату та нагадування одним записом.").font(.caption)
              if o.kind == .transfer { Text("Прив’язуй переказ лише якщо це фактична оплата договору, а не звичайне поповнення кредитної картки.").font(.caption).foregroundStyle(.orange) }
            }
          }
        }
        TextField("Магазин / примітка / теги", text: $o.note)
        if let bank = o.sourceBank { LabeledContent("Джерело", value: bank) }
        if let suffix=o.creditContractSuffix {LabeledContent("Договір",value:"••"+suffix)}
        if o.bankPostingKnown == true {LabeledContent("Дата постінгу",value:o.bankPostingDate?.formatted(date:.abbreviated,time:.omitted) ?? "Невідомо — звірити з банком")}
        if let description = o.destinationBankNote { LabeledContent("Опис другої сторони",value:description) }
        if let capture = o.captureSource { LabeledContent("Джерело запису", value: capture) }
        if let imageID = o.scanImageID { NavigationLink("Вкладений скриншот") { FinamiScanAttachment(imageID: imageID) } }
        if let n = o.originalAmount, let c = o.originalCurrency { LabeledContent("Оригінальна сума", value: currencyMoney(n,c)) }
        if let fee = o.bankFee, fee > 0 { LabeledContent("Комісія у виписці", value: money(fee)) }
        if o.kind == .expense || o.kind == .income {
          Button("Визначити категорію") { o.category = suggestedCategory(o.note, kind: o.kind, database: s.db) }
          Toggle("Запам’ятати категорію для цього продавця", isOn: $learnRule)
        }
        if savedOperation && !financialLocked {
          Button("Видалити операцію", role: .destructive) { confirm = true }
        }
      }.navigationTitle("Операція").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            if o.groupedBankParts != nil { if s.change({d in if let i=d.operations.firstIndex(where:{$0.id==o.id}) {d.operations[i].note=o.note}}) {dismiss()};return }
            guard let n=converted, let entered=bankMinor(amount), valid else {return}
            o.amount=n
            if o.sourceBank != nil {o.classificationReviewed=true}
            if !o.kind.isReportCategory {o.category="Без категорії"}
            o.sourceMinor=sourceCode == "USD" ? entered : n
            o.destinationMinor=o.kind == .transfer ? received : nil
            o.entryCurrency=entryCurrency
            o.exchangeRate=requiresRate ? (exactMode ? usedRate.map{finamiFXRateText($0)}:rate) : nil
            if o.sourceBank == nil {o.originalAmount=entered;o.originalCurrency=entryCurrency}
            if !linkedPaymentID.isEmpty {
              guard let payment = selectedPayment else { return }
              if s.confirmPayment(payment, mode: .newOperation, accountID: o.account, operationID: o.id, paidDate: o.date, kind: o.kind, allowSeparate: separatePayment, operationDraft: o, learnCategory: learnRule, actualAmount: o.sourceMinor ?? o.amount) { dismiss() }
              return
            }
            if s.change({ d in
              d.operations.removeAll { $0.id == o.id }
              d.operations.append(o)
              if learnRule && (o.kind == .expense || o.kind == .income) && !o.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var rules = d.merchantRules ?? [:]; rules[ruleKey(o.note, kind: o.kind)] = o.category; d.merchantRules = rules
              }
            }) {
              dismiss()
            }
          }.disabled(o.groupedBankParts == nil && !valid)
        }
      }.onAppear {if sourceCode == "USD" {entryCurrency="USD"};if rate.isEmpty {rate=s.db.currencyPreferences?.usdRate ?? ""}}
      .onChange(of:o.account) { _ in entryCurrency=sourceCode; linkedPaymentID=""; separatePayment=false }
      .onChange(of:linkedPaymentID) { _ in separatePayment=false }
      .onChange(of:amount) { _ in separatePayment=false }
      .onChange(of:o.date) { _ in separatePayment=false }
      .onChange(of:o.note) { newNote in
        if o.kind.isReportCategory && o.category == "Без категорії" && !savedOperation {
          let suggestion = suggestedCategory(newNote,kind:o.kind,database:s.db)
          if categories.contains(suggestion) { o.category = suggestion }
        }
      }
      .onChange(of: o.kind) { _ in
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
