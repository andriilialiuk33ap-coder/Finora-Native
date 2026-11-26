import SwiftUI

struct OperationRow: View {
  @EnvironmentObject var s: Store
  @Environment(\.finamiMask) private var masked
  var o: Operation
  var body: some View {
    HStack {
      FinamiIconTile(icon: finamiOperationIcon(o), tint: o.kind == .income ? .green : o.kind == .expense ? .orange : .blue, side: 42)
      VStack(alignment: .leading) {
        Text(o.note.isEmpty ? (o.kind == .transfer ? "Переказ" : o.category) : o.note).font(
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
  init(original: Operation) {
    _o = State(initialValue: original)
    let input = original.entryCurrency == "USD" ? (original.originalAmount ?? original.sourceMinor ?? original.amount) : original.amount
    _amount = State(initialValue: input == 0 ? "" : amountText(input))
    _entryCurrency = State(initialValue: original.entryCurrency ?? "UAH")
    _rate = State(initialValue: original.exchangeRate ?? "")
  }
  var categories: [String] { let list = o.kind == .income ? s.db.incomeCategories : s.db.expenseCategories; let hidden = o.kind == .income ? (s.db.hiddenIncomeCategories ?? []) : (s.db.hiddenExpenseCategories ?? []); let available = list.filter { !hidden.contains($0) || $0 == o.category }; return Array(Set(available + ["Без категорії",o.category])).sorted() }
  var allowedKinds: [Kind] {
    if o.sourceBank != nil && o.kind != .transfer {return Kind.allCases.filter{$0 != .transfer && $0.incoming == o.kind.incoming}}
    return Kind.allCases
  }
  var sourceCode:String { s.db.accounts.first(where:{$0.id==o.account})?.code ?? "UAH" }
  var destinationCode:String { s.db.accounts.first(where:{$0.id==o.destination})?.code ?? "UAH" }
  var requiresRate:Bool { entryCurrency == "USD" || (o.kind == .transfer && destinationCode == "USD") }
  var usedRate:Decimal? {fxRate(rate)}
  var converted:Int64? {
    guard let n=bankMinor(amount), n>0 else{return nil}
    if entryCurrency == "USD" {guard let r=usedRate else{return nil};return fxMinor(n,rate:r)}
    return n
  }
  var received:Int64? {
    guard let uah=converted else{return nil}
    if destinationCode == "USD" {if sourceCode == "USD" {return bankMinor(amount)};guard let r=usedRate else{return nil};return fxMinor(uah,rate:r,divide:true)}
    return uah
  }
  var valid: Bool {
    (converted ?? 0)>0 && s.db.accounts.contains { $0.id == o.account } && (!requiresRate || usedRate != nil)
      && (sourceCode != "USD" || entryCurrency == "USD")
      && (o.kind != .transfer || (o.account != o.destination && s.db.accounts.contains { $0.id == o.destination } && (received ?? 0)>0 && entryCurrency == sourceCode))
  }
  var body: some View {
    NavigationStack {
      Form {
        Picker("Тип", selection: $o.kind) { ForEach(allowedKinds) { Text($0.title).tag($0) } }
          .pickerStyle(.menu)
        if o.kind.needsReview { Text("Не входить у доходи чи витрати до уточнення. Баланс враховує рух коштів.").font(.caption) }
        FinamiField("Сума, \(entryCurrency)", text: $amount, keyboard: .decimalPad)
        if o.kind != .transfer && sourceCode == "UAH" && o.sourceBank == nil {
          Picker("Валюта введення",selection:$entryCurrency){Text("Гривня").tag("UAH");Text("Долар").tag("USD")}
        }
        if requiresRate { FinamiField("Курс UAH за 1 USD", text: $rate, keyboard: .decimalPad); if let n=converted { LabeledContent("Сума у гривнях",value:money(n)) } }
        DatePicker("Дата і час", selection: $o.date, displayedComponents: [.date,.hourAndMinute])
        Picker("Рахунок", selection: $o.account) {
          ForEach(s.db.accounts.filter{o.sourceBank == nil || $0.code == "UAH"}) { Text($0.name).tag($0.id) }
        }
        if o.kind == .transfer {
          Picker("Куди", selection: $o.destination) {
            Text("Вибрати").tag("")
            ForEach(s.db.accounts) { Text($0.name).tag($0.id) }
          }
          if let n=received, !o.destination.isEmpty { LabeledContent("Зарахувати",value:currencyMoney(n,destinationCode)) }
        } else if o.kind.isReportCategory {
          Picker("Категорія", selection: $o.category) {
            ForEach(categories, id: \.self) { Text($0).tag($0) }
          }
        }
        TextField("Магазин / примітка / теги", text: $o.note)
        if let bank = o.sourceBank { LabeledContent("Джерело", value: bank) }
        if let capture = o.captureSource { LabeledContent("Джерело запису", value: capture) }
        if let imageID = o.scanImageID { NavigationLink("Вкладений скриншот") { FinamiScanAttachment(imageID: imageID) } }
        if let n = o.originalAmount, let c = o.originalCurrency { LabeledContent("Оригінальна сума", value: currencyMoney(n,c)) }
        if let fee = o.bankFee, fee > 0 { LabeledContent("Комісія у виписці", value: money(fee)) }
        if o.kind == .expense || o.kind == .income {
          Button("Визначити категорію") { o.category = suggestedCategory(o.note, kind: o.kind, database: s.db) }
          Toggle("Запам’ятати категорію для цього продавця", isOn: $learnRule)
        }
        if s.db.operations.contains(where: { $0.id == o.id }) {
          Button("Видалити операцію", role: .destructive) { confirm = true }
        }
      }.navigationTitle("Операція").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            guard let n=converted, let entered=bankMinor(amount), valid else {return}
            o.amount=n
            if o.sourceBank != nil {o.classificationReviewed=true}
            if !o.kind.isReportCategory {o.category="Без категорії"}
            o.sourceMinor=sourceCode == "USD" ? entered : n
            o.destinationMinor=o.kind == .transfer ? received : nil
            o.entryCurrency=entryCurrency
            o.exchangeRate=requiresRate ? rate : nil
            if o.sourceBank == nil {o.originalAmount=entered;o.originalCurrency=entryCurrency}
            if s.change({ d in
              d.operations.removeAll { $0.id == o.id }
              d.operations.append(o)
              if learnRule && (o.kind == .expense || o.kind == .income) && !o.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var rules = d.merchantRules ?? [:]; rules[ruleKey(o.note, kind: o.kind)] = o.category; d.merchantRules = rules
              }
            }) {
              dismiss()
            }
          }.disabled(!valid)
        }
      }.onAppear {if sourceCode == "USD" {entryCurrency="USD"};if rate.isEmpty {rate=s.db.currencyPreferences?.usdRate ?? ""}}
      .onChange(of:o.account) { _ in entryCurrency=sourceCode }
      .onChange(of: o.kind) { _ in
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
