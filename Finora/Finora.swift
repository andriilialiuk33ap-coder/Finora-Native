// Finora 3.0.1 - SwiftUI build fix
import Charts
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

let expenseDefaults = [
  "🛒 Продукти", "🍽️ Ресторани", "☕ Кава", "🚗 Транспорт", "⛽ Паливо", "🚕 Таксі", "🏠 Дім",
  "🧾 Комунальні", "🔑 Оренда", "🛠️ Ремонт", "👕 Одяг", "💇 Краса", "💊 Здоров’я", "🏋️ Спорт", "🎬 Розваги",
  "📺 Підписки", "💻 Техніка", "📱 Зв’язок", "✈️ Подорожі", "📚 Освіта", "🐾 Тварини", "👶 Діти",
  "🎁 Подарунки", "💳 Розстрочка", "🛡️ Страхування", "🏦 Комісії", "📦 Доставка", "❤️ Благодійність",
  "Інше",
]
let incomeDefaults = [
  "💼 Зарплата", "💻 Підробіток", "🏢 Бізнес", "🎁 Подарунок", "↩️ Повернення", "💵 Кешбек", "📈 Відсотки",
  "Інше",
]
let cash = "cash"
let finoraAccent = Color(red: 0.04, green: 0.48, blue: 0.36)
func money(_ n: Int64) -> String {
  (Double(n) / 100).formatted(.currency(code: "UAH").locale(Locale(identifier: "uk_UA")))
}
func cents(_ s: String) -> Int64? {
  let t = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
  guard let v = Double(t), v.isFinite, abs(v) <= 1e10 else { return nil }
  return Int64((v * 100).rounded())
}
func amountText(_ n: Int64) -> String { String(format: "%.2f", Double(n) / 100) }
func sameMonth(_ a: Date, _ b: Date) -> Bool {
  Calendar.current.isDate(a, equalTo: b, toGranularity: .month)
}
func shift(_ date: Date, _ n: Int) -> Date {
  Calendar.current.date(byAdding: .month, value: n, to: date) ?? date
}
func monthName(_ d: Date) -> String {
  d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "uk_UA")))
}
enum Kind: String, Codable, CaseIterable, Identifiable {
  case expense, income, transfer
  var id: String { rawValue }
  var title: String {
    switch self {
    case .expense: return "Витрата"
    case .income: return "Дохід"
    case .transfer: return "Переказ"
    }
  }
}
struct Account: Codable, Identifiable {
  var id = UUID().uuidString
  var name: String
  var opening: Int64 = 0
}
struct Operation: Codable, Identifiable {
  var id = UUID().uuidString
  var kind: Kind = .expense
  var amount: Int64 = 0
  var date = Date()
  var category = "Інше"
  var note = ""
  var account = cash
  var destination = ""
}
enum ObligationKind: String, Codable, CaseIterable, Identifiable {
  case installment, owe, owed, recurring, goal
  var id: String { rawValue }
  var title: String {
    switch self {
    case .installment: return "Розстрочка"
    case .owe: return "Я винен"
    case .owed: return "Мені винні"
    case .recurring: return "Регулярний платіж"
    case .goal: return "Ціль"
    }
  }
}
struct Obligation: Codable, Identifiable {
  var id = UUID().uuidString
  var kind: ObligationKind = .goal
  var name = ""
  var target: Int64 = 0
  var paid: Int64 = 0
  var monthly: Int64 = 0
  var due = Date()
  var remaining: Int64 { max(0, target - paid) }
}
struct Database: Codable {
  var accounts = [Account(id: cash, name: "Готівка")]
  var operations: [Operation] = []
  var obligations: [Obligation] = []
  var expenseCategories = expenseDefaults
  var incomeCategories = incomeDefaults
  var budget: Int64 = 0
  var limits: [String: Int64] = [:]
}
struct Legacy: Decodable {
  struct Entry: Decodable {
    var amt: Double
    var ts: Double
    var cat: String?
    var note: String?
  }
  var items: [Entry]
  var incomes: [Entry]
  var budget: Double?
}
struct DataFile: FileDocument {
  static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
@MainActor final class Store: ObservableObject {
  @Published private(set) var db = Database()
  @Published var error: String? = nil
  private var ready = true
  private let url = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Finora.json")
  init() {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: url.path) {
        db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: url))
      }
    } catch {
      ready = false
      self.error =
        "База не читається. Запис заблоковано, щоб не втратити дані. \(error.localizedDescription)"
    }
  }
  @discardableResult func change(_ update: (inout Database) -> Void) -> Bool {
    guard ready else {
      error = "Запис заблоковано. Віднови базу з копії."
      return false
    }
    var copy = db
    update(&copy)
    return write(copy)
  }
  private func write(_ copy: Database) -> Bool {
    do {
      let data = try JSONEncoder().encode(copy)
      try data.write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      db = copy
      ready = true
      return true
    } catch {
      self.error = "Не вдалося зберегти: \(error.localizedDescription)"
      return false
    }
  }
  func totals(_ operations: [Operation], _ kind: Kind) -> Int64 {
    operations.filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
  }
  func month(_ date: Date) -> [Operation] { db.operations.filter { sameMonth($0.date, date) } }
  func balance(_ a: Account) -> Int64 {
    db.operations.reduce(a.opening) { n, o in
      switch o.kind {
      case .income: return n + (o.account == a.id ? o.amount : 0)
      case .expense: return n - (o.account == a.id ? o.amount : 0)
      case .transfer:
        return n - (o.account == a.id ? o.amount : 0) + (o.destination == a.id ? o.amount : 0)
      }
    }
  }
  func accountName(_ id: String) -> String { db.accounts.first { $0.id == id }?.name ?? "Рахунок" }
  func restore(_ data: Data) {
    do {
      let decoded = try JSONDecoder().decode(Database.self, from: data)
      guard !decoded.accounts.isEmpty,
        Set(decoded.accounts.map(\.id)).count == decoded.accounts.count,
        decoded.operations.allSatisfy({ o in
          o.amount > 0 && o.amount <= 1_000_000_000_000
            && decoded.accounts.contains(where: { a in a.id == o.account })
            && (o.kind != .transfer
              || (o.account != o.destination
                && decoded.accounts.contains(where: { a in a.id == o.destination })))
        })
      else { throw CocoaError(.fileReadCorruptFile) }
      _ = write(decoded)
    } catch { self.error = "Не вдалося відновити JSON: \(error.localizedDescription)" }
  }
  func importLegacy(_ data: Data) {
    do {
      let old = try JSONDecoder().decode(Legacy.self, from: data)
      var incoming: [Operation] = []
      for (kind, rows) in [(Kind.expense, old.items), (.income, old.incomes)] {
        for row in rows {
          guard row.amt.isFinite, row.amt > 0, row.amt <= 1e10, row.ts.isFinite, abs(row.ts) < 1e14
          else { throw CocoaError(.fileReadCorruptFile) }
          incoming.append(
            Operation(
              kind: kind, amount: Int64((row.amt * 100).rounded()),
              date: Date(timeIntervalSince1970: row.ts / 1000), category: row.cat ?? "Інше",
              note: row.note ?? "", account: db.accounts.first?.id ?? cash))
        }
      }
      var count = 0
      if change({ d in
        for o in incoming {
          guard
            !d.operations.contains(where: {
              $0.kind == o.kind && $0.amount == o.amount
                && abs($0.date.timeIntervalSince(o.date)) < 1 && $0.note == o.note
                && $0.category == o.category
            })
          else { continue }
          d.operations.append(o)
          count += 1
          if o.kind == .income {
            if !d.incomeCategories.contains(o.category) { d.incomeCategories.append(o.category) }
          } else if !d.expenseCategories.contains(o.category) {
            d.expenseCategories.append(o.category)
          }
        }
        if d.budget == 0, let b = old.budget, b.isFinite, b > 0, b <= 1e10 {
          d.budget = Int64((b * 100).rounded())
        }
      }) {
        error =
          "Імпортовано операцій: \(count). Дублікати пропущено. Борги, цілі та розстрочки перенеси вручну."
      }
    } catch { self.error = "Не вдалося прочитати стару базу: \(error.localizedDescription)" }
  }
  func backup() -> DataFile { DataFile(data: (try? JSONEncoder().encode(db)) ?? Data()) }
  func csv() -> DataFile {
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    let f = ISO8601DateFormatter()
    let rows = db.operations.map { o in
      [
        f.string(from: o.date), o.kind.title, amountText(o.amount), q(o.category),
        q(accountName(o.account)), q(o.destination.isEmpty ? "" : accountName(o.destination)),
        q(o.note),
      ].joined(separator: ";")
    }
    return DataFile(
      data: Data(
        ("\u{FEFF}Дата;Тип;Сума;Категорія;Рахунок;Куди;Примітка\n" + rows.joined(separator: "\n"))
          .utf8))
  }
}
@main @MainActor struct FinoraApp: App {
  @StateObject private var store = Store()
  var body: some Scene { WindowGroup { Root().environmentObject(store).tint(finoraAccent) } }
}
struct Root: View {
  @EnvironmentObject var store: Store
  @Environment(\.scenePhase) var phase
  @AppStorage("lockEnabled") var lockEnabled = false
  @State private var unlocked = false
  @State private var authError = ""
  var body: some View {
    Group {
      if lockEnabled && !unlocked {
        VStack(spacing: 18) {
          Image(systemName: "lock.shield.fill").font(.system(size: 64)).foregroundStyle(finoraAccent)
          Text("Finora").font(.largeTitle.bold())
          Text(authError).foregroundStyle(.secondary)
          Button("Розблокувати", action: unlock).buttonStyle(.borderedProminent)
        }.onAppear(perform: unlock)
      } else {
        TabView {
          NavigationStack { Home() }.tabItem { Label("Огляд", systemImage: "house.fill") }
          NavigationStack { Operations() }.tabItem {
            Label("Операції", systemImage: "arrow.left.arrow.right")
          }
          NavigationStack { Accounts() }.tabItem {
            Label("Рахунки", systemImage: "wallet.pass.fill")
          }
          NavigationStack { Reports() }.tabItem { Label("Звіти", systemImage: "chart.bar.xaxis") }
          NavigationStack { More() }.tabItem { Label("Ще", systemImage: "ellipsis.circle") }
        }
      }
    }.onChange(of: phase) { p in if p == .background && lockEnabled { unlocked = false } }.alert(
      "Finora",
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
  var body: some View {
    HStack {
      Button {
        date = shift(date, -1)
      } label: {
        Image(systemName: "chevron.left")
      }
      Spacer()
      Text(monthName(date).capitalized).font(.headline)
      Spacer()
      Button {
        date = shift(date, 1)
      } label: {
        Image(systemName: "chevron.right")
      }
    }.padding(.vertical, 6)
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
            ProgressView(value: min(1, Double(exp) / Double(s.db.budget))).tint(
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
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Finora").sheet(
      isPresented: $add
    ) { OpEditor(original: Operation(account: s.db.accounts.first?.id ?? cash)) }
  }
}
struct Breakdown: View {
  var ops: [Operation]
  var body: some View {
    let groups = Dictionary(grouping: ops.filter { $0.kind == .expense }, by: { $0.category })
      .mapValues { $0.reduce(Int64(0)) { $0 + $1.amount } }.sorted { $0.value > $1.value }
    let total = groups.reduce(Int64(0)) { $0 + $1.value }
    if total == 0 {
      Text("Немає витрат за період").foregroundStyle(.secondary)
    } else {
      ForEach(Array(groups.prefix(10).map(\.key)), id: \.self) { key in
        let value = groups.first(where: { $0.key == key })?.value ?? 0
        HStack {
          Text(key)
          Spacer()
          Text(money(value)).bold()
        }.font(.subheadline)
        ProgressView(value: Double(value) / Double(total)).tint(finoraAccent)
      }
    }
  }
}
struct OperationRow: View {
  @EnvironmentObject var s: Store
  var o: Operation
  var body: some View {
    HStack {
      Image(
        systemName: o.kind == .income
          ? "arrow.down.left.circle.fill"
          : o.kind == .transfer
            ? "arrow.left.arrow.right.circle.fill" : "arrow.up.right.circle.fill"
      ).font(.title2).foregroundStyle(
        o.kind == .income ? Color.green : o.kind == .transfer ? Color.blue : Color.orange)
      VStack(alignment: .leading) {
        Text(o.note.isEmpty ? (o.kind == .transfer ? "Переказ" : o.category) : o.note).font(
          .subheadline.bold())
        Text("\(s.accountName(o.account)) · \(o.date.formatted(date:.abbreviated,time:.omitted))")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text((o.kind == .income ? "+" : o.kind == .expense ? "−" : "") + money(o.amount)).font(
        .subheadline.bold()
      ).foregroundStyle(o.kind == .income ? Color.green : Color.primary)
    }
  }
}
struct Operations: View {
  @EnvironmentObject var s: Store
  @State private var search = ""
  @State private var edit: Operation?
  @State private var filter = "all"
  var body: some View {
    List {
      Picker("Тип", selection: $filter) {
        Text("Усі").tag("all")
        ForEach(Kind.allCases) { Text($0.title).tag($0.rawValue) }
      }.pickerStyle(.segmented)
      ForEach(
        s.db.operations.filter { o in
          (filter == "all" || o.kind.rawValue == filter)
            && (search.isEmpty
              || (o.note + " " + o.category + " " + amountText(o.amount) + " "
                + s.accountName(o.account)).localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
      ) { o in
        Button {
          edit = o
        } label: {
          OperationRow(o: o)
        }.buttonStyle(.plain)
      }
    }.searchable(text: $search, prompt: "Магазин, категорія, сума").navigationTitle("Операції")
      .toolbar {
        Button {
          edit = Operation(account: s.db.accounts.first?.id ?? cash)
        } label: {
          Image(systemName: "plus")
        }
      }.sheet(item: $edit) { OpEditor(original: $0) }
  }
}
struct OpEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var o: Operation
  @State var amount: String
  @State private var confirm = false
  init(original: Operation) {
    _o = State(initialValue: original)
    _amount = State(initialValue: original.amount == 0 ? "" : amountText(original.amount))
  }
  var categories: [String] { o.kind == .income ? s.db.incomeCategories : s.db.expenseCategories }
  var valid: Bool {
    (cents(amount) ?? 0) > 0 && s.db.accounts.contains { $0.id == o.account }
      && (o.kind != .transfer
        || (o.account != o.destination && s.db.accounts.contains { $0.id == o.destination }))
  }
  var body: some View {
    NavigationStack {
      Form {
        Picker("Тип", selection: $o.kind) { ForEach(Kind.allCases) { Text($0.title).tag($0) } }
          .pickerStyle(.segmented)
        TextField("Сума, ₴", text: $amount).keyboardType(.decimalPad)
        DatePicker("Дата", selection: $o.date, displayedComponents: .date)
        Picker("Рахунок", selection: $o.account) {
          ForEach(s.db.accounts) { Text($0.name).tag($0.id) }
        }
        if o.kind == .transfer {
          Picker("Куди", selection: $o.destination) {
            Text("Вибрати").tag("")
            ForEach(s.db.accounts) { Text($0.name).tag($0.id) }
          }
        } else {
          Picker("Категорія", selection: $o.category) {
            ForEach(categories, id: \.self) { Text($0).tag($0) }
          }
        }
        TextField("Магазин / примітка / теги", text: $o.note)
        if s.db.operations.contains(where: { $0.id == o.id }) {
          Button("Видалити операцію", role: .destructive) { confirm = true }
        }
      }.navigationTitle("Операція").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            guard let n = cents(amount), valid else { return }
            o.amount = n
            if s.change({ d in
              d.operations.removeAll { $0.id == o.id }
              d.operations.append(o)
            }) {
              dismiss()
            }
          }.disabled(!valid)
        }
      }.onChange(of: o.kind) { _ in
        if !categories.contains(o.category) { o.category = categories.first ?? "Інше" }
      }.confirmationDialog("Видалити запис?", isPresented: $confirm, titleVisibility: .visible) {
        Button("Видалити", role: .destructive) {
          if s.change({ $0.operations.removeAll { $0.id == o.id } }) { dismiss() }
        }
      }
    }
  }
}
struct Accounts: View {
  @EnvironmentObject var s: Store
  @State private var edit: Account?
  var body: some View {
    List {
      Section("Загальний залишок") {
        Text(money(s.db.accounts.reduce(0) { $0 + s.balance($1) })).font(.largeTitle.bold())
          .foregroundStyle(finoraAccent)
      }
      Section("Рахунки в гривнях") {
        ForEach(s.db.accounts) { a in
          Button {
            edit = a
          } label: {
            HStack {
              Image(systemName: "creditcard.fill").foregroundStyle(finoraAccent)
              Text(a.name)
              Spacer()
              Text(money(s.balance(a))).bold()
            }
          }.buttonStyle(.plain)
        }
      }
      Text(
        "Перекази додаються в меню «Операції». Початковий баланс можна змінювати в налаштуваннях рахунку."
      ).font(.caption).foregroundStyle(.secondary)
    }.navigationTitle("Рахунки").toolbar {
      Button {
        edit = Account(name: "")
      } label: {
        Image(systemName: "plus")
      }
    }.sheet(item: $edit) { AccountEditor(a: $0) }
  }
}
struct AccountEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var a: Account
  @State var opening: String
  init(a: Account) {
    _a = State(initialValue: a)
    _opening = State(initialValue: amountText(a.opening))
  }
  var body: some View {
    NavigationStack {
      Form {
        TextField("Назва", text: $a.name)
        TextField("Початковий баланс, ₴", text: $opening).keyboardType(.numbersAndPunctuation)
        Text("Для кредитного рахунку можна вказати від’ємну суму.").font(.caption)
      }.navigationTitle("Рахунок").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            guard let n = cents(opening) else { return }
            a.opening = n
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
            a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cents(opening) == nil)
        }
      }
    }
  }
}
// Keep chart data and chart rendering separate to simplify SwiftUI type checking.
struct CashFlowPoint: Identifiable {
  let month: Date
  let series: String
  let amount: Double
  var id: String { "\(month.timeIntervalSinceReferenceDate)-\(series)" }
}
struct AnnualCashFlowChart: View {
  let points: [CashFlowPoint]
  var body: some View {
    Chart(points) { point in
      BarMark(
        x: .value("Місяць", point.month, unit: .month),
        y: .value("UAH", point.amount)
      )
      .foregroundStyle(by: .value("Тип", point.series))
      .position(by: .value("Тип", point.series))
    }
    .chartForegroundStyleScale(domain: ["Доходи", "Витрати"], range: [finoraAccent, Color.orange])
    .frame(height: 220)
  }
}
struct Reports: View {
  @EnvironmentObject var s: Store
  @State private var year = Calendar.current.component(.year, from: Date())
  var months: [Date] {
    (1...12).compactMap {
      Calendar.current.date(from: DateComponents(year: year, month: $0, day: 1))
    }
  }
  private var chartPoints: [CashFlowPoint] {
    var points: [CashFlowPoint] = []
    for month in months {
      let operations = s.month(month)
      let income = Double(s.totals(operations, .income)) / 100.0
      let expense = Double(s.totals(operations, .expense)) / 100.0
      points.append(CashFlowPoint(month: month, series: "Доходи", amount: income))
      points.append(CashFlowPoint(month: month, series: "Витрати", amount: expense))
    }
    return points
  }
  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        HStack {
          Button {
            year -= 1
          } label: {
            Image(systemName: "chevron.left")
          }
          Spacer()
          Text(String(year)).font(.title2.bold())
          Spacer()
          Button {
            year += 1
          } label: {
            Image(systemName: "chevron.right")
          }
        }
        let ops = s.db.operations.filter {
          Calendar.current.component(.year, from: $0.date) == year
        }
        let inc = s.totals(ops, .income)
        let exp = s.totals(ops, .expense)
        Panel {
          Text("Грошовий потік за рік").font(.headline)
          Text(money(inc - exp)).font(.title.bold())
          Text("Доходи: \(money(inc))").foregroundStyle(.green)
          Text("Витрати: \(money(exp))")
        }
        Panel {
          Text("Доходи та витрати").font(.headline)
          AnnualCashFlowChart(points: chartPoints)
        }
        Panel {
          Text("За місяцями").font(.headline)
          ForEach(months, id: \.self) { d in
            HStack {
              Text(d.formatted(.dateTime.month(.wide).locale(Locale(identifier: "uk_UA")))).font(
                .subheadline)
              Spacer()
              VStack(alignment: .trailing) {
                Text("+" + money(s.totals(s.month(d), .income))).foregroundStyle(.green)
                Text("−" + money(s.totals(s.month(d), .expense))).foregroundStyle(.secondary)
              }.font(.caption)
            }
            Divider()
          }
        }
        Panel {
          Text("Структура витрат").font(.headline)
          Breakdown(ops: ops)
        }
      }.padding()
    }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Звіти")
  }
}
struct More: View {
  @EnvironmentObject var s: Store
  var body: some View {
    List {
      Section("Планування") {
        NavigationLink {
          Budgets()
        } label: {
          Label("Бюджети", systemImage: "chart.pie")
        }
        ForEach(ObligationKind.allCases) { k in
          NavigationLink {
            Obligations(kind: k)
          } label: {
            Label(
              k.title,
              systemImage: k == .goal
                ? "target" : k == .recurring ? "repeat" : "calendar.badge.clock")
          }
        }
        NavigationLink {
          CalendarView()
        } label: {
          Label("Календар платежів", systemImage: "calendar")
        }
        NavigationLink {
          Insights()
        } label: {
          Label("Фінансовий помічник", systemImage: "sparkles")
        }
      }
      Section("Керування") {
        NavigationLink {
          Categories()
        } label: {
          Label("Категорії", systemImage: "tag")
        }
        NavigationLink {
          Settings()
        } label: {
          Label("Захист та резервні копії", systemImage: "lock.shield")
        }
      }
      Section {
        Text("Finora Native · 3.0\nБез реклами, серверів та платних API.").font(.footnote)
          .foregroundStyle(.secondary)
      }
    }.navigationTitle("Ще")
  }
}
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
            Text(money(s.db.budget))
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
              name: c, used: s.totals(s.month(Date()).filter { $0.category == c }, .expense),
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
  var name: String
  var used: Int64
  var limit: Int64
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(name)
        Spacer()
        Text(money(used)).font(.subheadline.bold())
      }
      if limit > 0 {
        ProgressView(value: min(1, Double(used) / Double(limit))).tint(used > limit ? .red : finoraAccent)
        Text("Ліміт: \(money(limit))").font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Без ліміту").font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 4)
  }
}
struct Obligations: View {
  @EnvironmentObject var s: Store
  var kind: ObligationKind
  @State private var edit: Obligation?
  var body: some View {
    List {
      Section("Загальний залишок") {
        Text(money(s.db.obligations.filter { $0.kind == kind }.reduce(0) { $0 + $1.remaining }))
          .font(.title.bold())
      }
      ForEach(s.db.obligations.filter { $0.kind == kind }) { o in
        Button {
          edit = o
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(o.name).bold()
              Spacer()
              Text(money(o.remaining))
            }
            ProgressView(value: o.target > 0 ? min(1, Double(o.paid) / Double(o.target)) : 0)
            Text(
              "\(money(o.paid)) із \(money(o.target)) · \(o.due.formatted(date:.abbreviated,time:.omitted))"
            ).font(.caption).foregroundStyle(.secondary)
          }
        }.buttonStyle(.plain)
      }
    }.navigationTitle(kind.title).toolbar {
      Button {
        edit = Obligation(kind: kind)
      } label: {
        Image(systemName: "plus")
      }
    }.sheet(item: $edit) { ObligationEditor(original: $0) }
  }
}
struct ObligationEditor: View {
  @EnvironmentObject var s: Store
  @Environment(\.dismiss) var dismiss
  @State var o: Obligation
  @State var target: String
  @State var paid: String
  @State var monthly: String
  @State var payment = ""
  @State var log = false
  @State var account = cash
  @State var confirm = false
  init(original: Obligation) {
    _o = State(initialValue: original)
    _target = State(initialValue: amountText(original.target))
    _paid = State(initialValue: amountText(original.paid))
    _monthly = State(initialValue: amountText(original.monthly))
  }
  var valid: Bool {
    !o.name.trimmingCharacters(in: .whitespaces).isEmpty && (cents(target) ?? 0) > 0
      && (cents(paid) ?? -1) >= 0 && (cents(paid) ?? 0) <= (cents(target) ?? 0)
      && (cents(monthly) ?? -1) >= 0
      && (payment.isEmpty
        || ((cents(payment) ?? 0) > 0
          && (cents(payment) ?? 0) <= (cents(target) ?? 0) - (cents(paid) ?? 0)))
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Параметри") {
          TextField("Назва / особа", text: $o.name)
          TextField("Загальна сума, ₴", text: $target).keyboardType(.decimalPad)
          TextField("Вже сплачено / накопичено", text: $paid).keyboardType(.decimalPad)
          TextField("Регулярний платіж, ₴", text: $monthly).keyboardType(.decimalPad)
          DatePicker("Наступна дата / термін", selection: $o.due, displayedComponents: .date)
        }
        Section("Додати платіж або накопичення") {
          TextField("Сума", text: $payment).keyboardType(.decimalPad)
          if o.kind != .goal {
            Toggle("Також записати операцію", isOn: $log)
            if log {
              Picker("Рахунок", selection: $account) {
                ForEach(s.db.accounts) { Text($0.name).tag($0.id) }
              }
            }
          }
          Text(
            "Для цілей прогрес не змінює залишків рахунків. Для боргів і розстрочок облік платежу в операціях — за вибором."
          ).font(.caption)
        }
        if s.db.obligations.contains(where: { $0.id == o.id }) {
          Button("Видалити", role: .destructive) { confirm = true }
        }
      }.navigationTitle(o.kind.title).navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Зберегти") {
            guard valid, let t = cents(target), let p = cents(paid), let m = cents(monthly) else {
              return
            }
            let extra = cents(payment) ?? 0
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
              if extra > 0 && log && o.kind != .goal {
                d.operations.append(
                  Operation(
                    kind: o.kind == .owed ? .income : .expense, amount: extra, category: "Інше",
                    note: o.name, account: account))
              }
            }) {
              dismiss()
            }
          }.disabled(!valid)
        }
      }.confirmationDialog("Видалити запис?", isPresented: $confirm) {
        Button("Видалити", role: .destructive) {
          if s.change({ $0.obligations.removeAll { $0.id == o.id } }) { dismiss() }
        }
      }
    }
  }
}
struct CalendarView: View {
  @EnvironmentObject var s: Store
  var body: some View {
    List {
      ForEach(
        s.db.obligations.filter { $0.remaining > 0 && $0.kind != .goal }.sorted { $0.due < $1.due }
      ) { o in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(o.name).bold()
            Spacer()
            Text(o.due.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(
              o.due < Date() ? Color.red : Color.secondary)
          }
          Text("\(o.kind.title) · \(money(o.monthly>0 ? min(o.monthly,o.remaining):o.remaining))")
            .font(.caption)
          Button("Нагадати за день") { notify(o) }.buttonStyle(.bordered)
        }
      }
    }.navigationTitle("Календар")
  }
  func notify(_ o: Obligation) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
      guard ok else {
        DispatchQueue.main.async { s.error = "Дозволь сповіщення в налаштуваннях iPhone." }
        return
      }
      let c = UNMutableNotificationContent()
      c.title = "Finora: платіж"
      c.body = o.name
      c.sound = .default
      let due = max(60, o.due.timeIntervalSinceNow - 86400)
      center.add(
        UNNotificationRequest(
          identifier: o.id, content: c,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: due, repeats: false))
      ) { e in
        DispatchQueue.main.async { s.error = e?.localizedDescription ?? "Нагадування встановлено." }
      }
    }
  }
}
struct Categories: View {
  @EnvironmentObject var s: Store
  @State private var income = false
  @State private var adding = false
  @State private var name = ""
  var cats: [String] { income ? s.db.incomeCategories : s.db.expenseCategories }
  var body: some View {
    List {
      Picker("Тип", selection: $income) {
        Text("Витрати").tag(false)
        Text("Доходи").tag(true)
      }.pickerStyle(.segmented)
      ForEach(cats, id: \.self) { c in
        Text(c).swipeActions {
          if c != "Інше" {
            Button(role: .destructive) {
              s.change { d in
                if income {
                  d.incomeCategories.removeAll { $0 == c }
                } else {
                  d.expenseCategories.removeAll { $0 == c }
                  d.limits.removeValue(forKey: c)
                }
                for i in d.operations.indices
                where d.operations[i].category == c
                  && d.operations[i].kind == (income ? .income : .expense)
                { d.operations[i].category = "Інше" }
              }
            } label: {
              Label("Видалити", systemImage: "trash")
            }
          }
        }
      }
    }.navigationTitle("Категорії").toolbar {
      Button {
        adding = true
        name = ""
      } label: {
        Image(systemName: "plus")
      }
    }.alert("Нова категорія", isPresented: $adding) {
      TextField("Іконка та назва", text: $name)
      Button("Скасувати", role: .cancel) {}
      Button("Додати") {
        let c = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !cats.contains(c) else { return }
        s.change { d in
          if income { d.incomeCategories.append(c) } else { d.expenseCategories.append(c) }
        }
      }
    }
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
          Text(money(forecast)).font(.title.bold())
          Text("Оцінка за поточним середнім темпом, не гарантія.").font(.caption)
        }
        Panel {
          Text("Грошовий потік").font(.headline)
          Text(money(inc - exp)).font(.title.bold())
          if inc > 0 {
            Text(
              "Частка невитраченого доходу: \((Double(inc-exp)/Double(inc)*100).formatted(.number.precision(.fractionLength(1))))%"
            )
          }
          Text("Витрати минулого місяця: \(money(previous))")
          if s.db.budget > 0 {
            Text(
              forecast > s.db.budget
                ? "За поточного темпу бюджет може бути перевищено." : "Прогноз у межах бюджету.")
          }
        }
        Panel {
          Text("Найбільші витрати").font(.headline)
          Breakdown(ops: ops)
        }
      }.padding()
    }.navigationTitle("Помічник")
  }
}
struct Settings: View {
  @EnvironmentObject var s: Store
  @AppStorage("lockEnabled") var lock = false
  @State private var exporting = false
  @State private var importing = false
  @State private var legacy = false
  @State private var doc: DataFile?
  @State private var format: UTType = .json
  @State private var fileName = "Finora-backup"
  @State private var confirm = false
  @State private var pending: Data?
  var body: some View {
    List {
      Section("Безпека") {
        Toggle("Face ID / код-пароль", isOn: $lock)
        Text(
          "Дані зберігаються у локальному сховищі застосунку. Видалення програми видалить і базу, тому роби резервні копії."
        ).font(.caption)
      }
      Section("Резервні копії") {
        Button("Експорт JSON") {
          format = .json
          fileName = "Finora-backup"
          doc = s.backup()
          exporting = true
        }
        Button("Експорт CSV для Excel") {
          format = .commaSeparatedText
          fileName = "Finora-operations"
          doc = s.csv()
          exporting = true
        }
        Button("Відновити нову базу JSON") {
          legacy = false
          importing = true
        }
        Button("Імпорт операцій Scriptable / PWA") {
          legacy = true
          importing = true
        }
        Text(
          "Старий імпорт переносить доходи, витрати, категорії та загальний бюджет. Рахунки, перекази, борги й цілі зі старих копій не переносяться автоматично."
        ).font(.caption)
      }
    }.navigationTitle("Налаштування").fileExporter(
      isPresented: $exporting, document: doc, contentType: format, defaultFilename: fileName
    ) { if case .failure(let e) = $0 { s.error = e.localizedDescription } }.fileImporter(
      isPresented: $importing, allowedContentTypes: [.json]
    ) { result in
      do {
        let u = try result.get()
        let allowed = u.startAccessingSecurityScopedResource()
        defer { if allowed { u.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: u)
        if legacy {
          s.importLegacy(data)
        } else {
          pending = data
          confirm = true
        }
      } catch { s.error = error.localizedDescription }
    }.confirmationDialog(
      "Замінити поточну базу? Спершу зроби резервну копію.", isPresented: $confirm,
      titleVisibility: .visible
    ) {
      Button("Відновити", role: .destructive) {
        if let data = pending { s.restore(data) }
        pending = nil
      }
      Button("Скасувати", role: .cancel) { pending = nil }
    }
  }
}
