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
  "🏪 Побут", "🅿️ Паркування", "🚆 Поїздки", "🦷 Стоматологія", "🧴 Гігієна", "🎮 Ігри", "🍕 Доставка їжі", "📦 Маркетплейси", "🧰 Робочі витрати", "🪴 Сад", "🧾 Податки", "🏥 Лікування", "Без категорії", "Інше",
]
let incomeDefaults = [
  "💼 Зарплата", "💻 Підробіток", "🏢 Бізнес", "🎁 Подарунок", "↩️ Повернення", "💵 Кешбек", "📈 Відсотки",
  "Без категорії", "Інше",
]
let cash = "cash"
let finoraAccent = Color(red: 0.85, green: 0.12, blue: 0.25)
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
  case expense, income, transfer, creditDraw, creditRepayment, creditRepaymentIncoming, movementIn, movementOut, refund, unclassifiedCredit, unclassifiedDebit
  var id: String { rawValue }
  var incoming: Bool { [.income,.creditDraw,.creditRepaymentIncoming,.movementIn,.refund,.unclassifiedCredit].contains(self) }
  var needsReview: Bool { self == .unclassifiedCredit || self == .unclassifiedDebit }
  var isReportCategory: Bool { self == .income || self == .expense || self == .refund }
  var title: String {
    switch self {
    case .expense: return "Витрата"
    case .income: return "Дохід"
    case .transfer: return "Переказ між рахунками"
    case .creditDraw: return "Отримання кредиту"
    case .creditRepayment: return "Погашення кредиту"
    case .creditRepaymentIncoming: return "Поповнення кредитної картки"
    case .movementIn: return "Переказ / поповнення +"
    case .movementOut: return "Переказ / зняття −"
    case .refund: return "Повернення покупки"
    case .unclassifiedCredit: return "Зарахування: уточнити"
    case .unclassifiedDebit: return "Списання: уточнити"
    }
  }
}
// Optional appearance data is intentionally independent of ledger balances.
struct AccountCardOptions: Codable {
  var style: String? = nil
  var right: String? = nil
  var fields: [String]? = nil
  var photo: Data? = nil
  var pinned: Bool? = nil
  var order: Int? = nil
  var accent: String? = nil
}
struct Account: Codable, Identifiable {
  var id = UUID().uuidString
  var name: String
  var opening: Int64 = 0
  var currency: String? = nil
  var accountType: String? = nil
  var bankName: String? = nil
  var lastFour: String? = nil
  var creditLimit: Int64? = nil
  var hiddenInAccounts: Bool? = nil
  var hiddenInOverview: Bool? = nil
  var excludedFromTotals: Bool? = nil
  var hideAmounts: Bool? = nil
  var cardOptions: AccountCardOptions? = nil
  var code: String { currency ?? "UAH" }
  var isCredit: Bool { accountType == "credit" }
  var limit: Int64 { isCredit ? max(0,creditLimit ?? 0) : 0 }
  var typeName: String { isCredit ? "Кредитна картка" : accountType == "debit" ? "Дебетова картка" : id == cash || accountType == "cash" ? "Готівка" : "Інший рахунок" }
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
  var bankKey: String? = nil
  var sourceBank: String? = nil
  var originalAmount: Int64? = nil
  var originalCurrency: String? = nil
  var bankFee: Int64? = nil
  var sourceMinor: Int64? = nil
  var destinationMinor: Int64? = nil
  var entryCurrency: String? = nil
  var exchangeRate: String? = nil
  var importBatch: String? = nil
  var bankMCC: Int? = nil
  var bankType: String? = nil
  var classificationReviewed: Bool? = nil
  var captureSource: String? = nil
  var scanFingerprint: String? = nil
  var scanImageID: String? = nil
  var signedNative: Int64 { kind.incoming ? (sourceMinor ?? amount) : -(sourceMinor ?? amount) }
  // Only count an embedded fee separately when it is demonstrably part of a non-expense debit.
  var neutralFee: Int64 {
    guard !kind.incoming, kind != .expense, kind != .transfer, sourceBank == "А-БАНК", originalCurrency == "UAH", let originalAmount, let bankFee, bankFee > 0, originalAmount == amount - bankFee else {return 0}
    return bankFee
  }
  var expenseValue: Int64 { kind == .expense ? amount : kind == .refund ? -amount : neutralFee }
  var expenseGroup: String { kind == .expense || kind == .refund ? category : "🏦 Комісії" }
}
// Native currency amounts, matching the existing ledger convention. Transfers
// appear in activity but never inflate income or spending.
struct AccountActivity {
  let accountID: String
  let history: [Operation]
  let income: Int64
  let spending: Int64
  let count: Int
  init(account: Account, operations: [Operation], month: Date, calendar: Calendar = .current) {
    accountID = account.id
    history = operations.filter { $0.account == account.id || ($0.kind == .transfer && $0.destination == account.id) }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    let period = history.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    count = period.count
    income = period.filter { $0.account == account.id && $0.kind == .income }.reduce(0) { $0 + ($1.sourceMinor ?? $1.amount) }
    spending = period.filter { $0.account == account.id }.reduce(0) { total, o in
      if o.kind == .expense { return total + (o.sourceMinor ?? o.amount) }
      if o.kind == .refund { return total - (o.sourceMinor ?? o.amount) }
      return total + (account.code == "UAH" ? o.neutralFee : 0)
    }
  }
  func signed(_ o: Operation) -> Int64 {
    if o.kind == .transfer && o.destination == accountID { return o.destinationMinor ?? o.amount }
    return o.signedNative
  }
}
func finamiOrderedAccounts(_ accounts: [Account]) -> [Account] {
  accounts.enumerated().sorted { lhs, rhs in
    let l = lhs.element.cardOptions, r = rhs.element.cardOptions
    let lp = l?.pinned == true, rp = r?.pinned == true
    if lp != rp { return lp }
    let lo = l?.order ?? Int.max, ro = r?.order ?? Int.max
    if lo != ro { return lo < ro }
    return lhs.offset < rhs.offset
  }.map(\.element)
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
  var scanFingerprint: String? = nil
  var scanImageID: String? = nil
  var scanSourceIDs: [String]? = nil
  var importedSchedule: [FinamiScheduleRow]? = nil
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
  var dashboard: [DashboardItem]? = nil
  var preferences: AppearancePreferences? = nil
  var subscriptions: [SubscriptionRecord]? = nil
  var reminders: [PersonalReminder]? = nil
  var forecast: ForecastPreferences? = nil
  var merchantRules: [String: String]? = nil
  var currencyPreferences: CurrencyPreferences? = nil
  var capturePreferences: CapturePreferences? = nil
  var captureHandled: [String]? = nil
  var balanceObservations: [String: FinamiBalanceObservation]? = nil
  var captureMessageFingerprints: [String]? = nil
  var hiddenExpenseCategories: [String]? = nil
  var hiddenIncomeCategories: [String]? = nil
  var categoryParents: [String: String]? = nil
  var paymentPhotos: [String: Data]? = nil
  var scanImages: [String: Data]? = nil
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
  @Published var capturePending: [CapturedPayment] = []
  @Published var captureWarning: String? = nil
  private var ready = true
  private let url: URL = {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    #if DEBUG && targetEnvironment(simulator)
    if ProcessInfo.processInfo.arguments.contains("--finami-qa") {
      return folder.appendingPathComponent("FinamiUITestData", isDirectory: true).appendingPathComponent("Finora.json")
    }
    #endif
    return folder.appendingPathComponent("Finora.json")
  }()
  init() {
    do {
      #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--finami-qa"), ProcessInfo.processInfo.arguments.contains("--finami-qa-reset"), FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      #endif
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: url.path) {
        db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: url))
      }
      #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--finami-qa"),
         ProcessInfo.processInfo.arguments.contains("--finami-qa-reports-fixture"),
         !FileManager.default.fileExists(atPath: url.path) {
        db.accounts.append(Account(id: "qa-pumb", name: "QA Pumb"))
        db.accounts.append(Account(id: "qa-otp", name: "QA OTP"))
        db.operations = [Operation(kind: .expense, amount: 30000, account: "qa-pumb"),
                         Operation(kind: .income, amount: 100000, account: "qa-pumb"),
                         Operation(kind: .expense, amount: 10000, account: "qa-otp"),
                         Operation(kind: .income, amount: 20000, account: "qa-otp")]
        var p = AppearancePreferences()
        p.reportsShowComparison = false; p.reportsShowCategories = false; p.reportsShowChart = false
        db.preferences = p
      }
      #endif
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
    if let images = copy.scanImages {
      let references = Set(copy.operations.compactMap(\.scanImageID) + copy.obligations.compactMap(\.scanImageID))
      copy.scanImages = images.filter { references.contains($0.key) }
    }
    var newlyCaptured = 0
    if copy.capturePreferences?.notifySaved == true {
      let oldIDs = Set(db.operations.map(\.id))
      newlyCaptured = copy.operations.filter { $0.captureSource != nil && !oldIDs.contains($0.id) }.count
    }
    let saved = write(copy)
    if saved && newlyCaptured > 0 && copy.capturePreferences?.notifySaved == true {
      FinamiSavedNotification.post(count: newlyCaptured)
    }
    return saved
  }
  private func write(_ copy: Database) -> Bool {
    do {
      let data = try JSONEncoder().encode(copy)
      // Keep previous local snapshots before replacing the live database.
      if FileManager.default.fileExists(atPath: url.path) && ready {
        let folder = url.deletingLastPathComponent().appendingPathComponent("IzanamiSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snapshot = folder.appendingPathComponent(UUID().uuidString + ".json")
        let previous = try Data(contentsOf: url)
        try previous.write(to: snapshot, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let files = snapshotURLs()
        for old in files.dropFirst(12) { try? FileManager.default.removeItem(at: old) }
      }
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
    if kind == .expense {return operations.reduce(0) { $0 + $1.expenseValue }}
    return operations.filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
  }
  func month(_ date: Date) -> [Operation] { db.operations.filter { sameMonth($0.date, date) } }
  var currentRate: Decimal? { fxRate(db.currencyPreferences?.usdRate ?? "") }
  func nativeBalance(_ a: Account) -> Int64 {
    db.operations.reduce(a.opening) { n, o in
      if o.kind == .transfer {
        return n - (o.account == a.id ? (o.sourceMinor ?? o.amount) : 0) + (o.destination == a.id ? (o.destinationMinor ?? o.amount) : 0)
      }
      return n + (o.account == a.id ? o.signedNative : 0)
    }
  }
  func ownFunds(_ a: Account) -> Int64 { CardPosition(net:nativeBalance(a),limit:a.limit).own }
  func debt(_ a: Account) -> Int64 { CardPosition(net:nativeBalance(a),limit:a.limit).used }
  func available(_ a: Account) -> Int64 { CardPosition(net:nativeBalance(a),limit:a.limit).available }
  func uah(_ n: Int64, account a: Account) -> Int64 { a.code == "USD" ? currentRate.flatMap{fxMinor(n,rate:$0)} ?? 0 : n }
  var includedAccounts: [Account] { db.accounts.filter { $0.excludedFromTotals != true } }
  var totalCreditLimit: Int64 { includedAccounts.filter(\.isCredit).reduce(0) { $0 + uah($1.limit, account: $1) } }
  var totalCreditUsed: Int64 { includedAccounts.filter(\.isCredit).reduce(0) { $0 + uah(debt($1), account: $1) } }
  var totalOwnFunds: Int64 { includedAccounts.reduce(0){$0+uah(ownFunds($1),account:$1)} }
  var totalAvailableCredit: Int64 { includedAccounts.filter(\.isCredit).reduce(0){$0+uah(max(0,$1.limit-debt($1)),account:$1)} }
  var totalAccountDebt: Int64 { includedAccounts.reduce(0){$0+uah(debt($1),account:$1)} }
  func balance(_ a: Account) -> Int64 {
    let n=nativeBalance(a)
    guard a.code == "USD" else{return n}
    guard let rate=currentRate else{return 0}
    return fxMinor(n,rate:rate) ?? 0
  }
  var privateAmounts: Bool { db.preferences?.hideAmounts == true }
  func visibleMoney(_ n: Int64, _ code: String = "UAH") -> String { privateAmounts ? "••••" : currencyMoney(n,code) }
  func displayed(_ n:Int64)->String {
    if privateAmounts { return "••••" }
    let mode=db.currencyPreferences?.display ?? "dual"
    guard let rate=currentRate, let usd=fxMinor(n,rate:rate,divide:true) else{return money(n)}
    if mode == "USD" {return "≈ "+currencyMoney(usd,"USD")}
    if mode == "dual" {return money(n)+" · ≈ "+currencyMoney(usd,"USD")}
    return money(n)
  }
  func accountName(_ id: String) -> String { db.accounts.first { $0.id == id }?.name ?? "Рахунок" }
  func restore(_ data: Data) {
    do {
      let decoded = try JSONDecoder().decode(Database.self, from: data)
      guard !decoded.accounts.isEmpty,
        Set(decoded.accounts.map(\.id)).count == decoded.accounts.count,
        decoded.accounts.allSatisfy({ ["UAH","USD"].contains($0.code) && $0.opening >= -1_000_000_000_000 && $0.opening <= 1_000_000_000_000 && ($0.creditLimit ?? 0) >= 0 && ($0.creditLimit ?? 0) <= 1_000_000_000_000 }),
        (!decoded.accounts.contains(where:{$0.code=="USD"}) || fxRate(decoded.currencyPreferences?.usdRate ?? "") != nil),
        Set(decoded.operations.map(\.id)).count == decoded.operations.count,
        decoded.obligations.allSatisfy({ o in (o.importedSchedule ?? []).allSatisfy { $0.amount > 0 && $0.amount <= 1_000_000_000_000 } }),
        (decoded.balanceObservations ?? [:]).values.allSatisfy({ $0.available >= 0 && $0.available <= 1_000_000_000_000 && ["UAH","USD"].contains($0.currency) }),
        decoded.operations.allSatisfy({ o in
          o.amount > 0 && o.amount <= 1_000_000_000_000
            && (o.sourceMinor.map { $0 > 0 && $0 <= 1_000_000_000_000 } ?? true)
            && (o.destinationMinor.map { $0 > 0 && $0 <= 1_000_000_000_000 } ?? true)
            && (decoded.accounts.first(where:{$0.id==o.account})?.code != "USD" || (o.sourceMinor != nil && fxRate(o.exchangeRate ?? "") != nil))
            && (o.kind != .transfer || decoded.accounts.first(where:{$0.id==o.destination})?.code != "USD" || o.destinationMinor != nil)
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
              note: row.note ?? "", account: db.accounts.first(where:{$0.code=="UAH"})?.id ?? cash))
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
  func snapshotURLs() -> [URL] {
    let folder = url.deletingLastPathComponent().appendingPathComponent("IzanamiSnapshots", isDirectory: true)
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
    return files.filter { $0.pathExtension == "json" }.sorted {
      (($0.resourceValuesDate) ?? .distantPast) > (($1.resourceValuesDate) ?? .distantPast)
    }
  }
  var storageHealthy: Bool { ready }
  func backup() -> DataFile { DataFile(data: (try? JSONEncoder().encode(db)) ?? Data()) }
  func csv() -> DataFile {
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    let f = ISO8601DateFormatter()
    let rows = db.operations.map { o in
      [
        f.string(from: o.date), o.kind.title, amountText(o.amount), q(o.category),
        q(accountName(o.account)), q(o.destination.isEmpty ? "" : accountName(o.destination)),
        q(o.note), q(o.entryCurrency ?? "UAH"), q(o.originalCurrency ?? "UAH"), amountText(o.originalAmount ?? o.amount), q(o.exchangeRate ?? ""), amountText(o.bankFee ?? 0), q(o.sourceBank ?? ""),
      ].joined(separator: ";")
    }
    return DataFile(
      data: Data(
        ("\u{FEFF}Дата;Тип;Сума UAH;Категорія;Рахунок;Куди;Примітка;Валюта введення;Оригінальна валюта;Оригінальна сума;Курс;Комісія UAH;Банк\n" + rows.joined(separator: "\n"))
          .utf8))
  }
}
@main @MainActor struct FinoraApp: App {
  @UIApplicationDelegateAdaptor(FinamiNotificationDelegate.self) private var notifications
  @StateObject private var store = Store()
  init() { FinamiShortcuts.updateAppShortcutParameters() }
  var body: some Scene { WindowGroup { IzanamiShell().environmentObject(store) } }
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
          Text("Finami").font(.largeTitle.bold())
          Text(authError).foregroundStyle(.secondary)
          Button("Розблокувати", action: unlock).buttonStyle(.borderedProminent)
        }.onAppear(perform: unlock)
      } else {
        TabView {
          NavigationStack { CustomDashboard() }.tabItem { Label(store.db.preferences?.homeTitle ?? "Головна", systemImage: "house.fill") }
          NavigationStack { Operations() }.tabItem {
            Label("Операції", systemImage: "arrow.left.arrow.right")
          }
          NavigationStack { Accounts() }.tabItem {
            Label("Рахунки", systemImage: "wallet.pass.fill")
          }
          NavigationStack { if store.privateAmounts { FinamiPrivacyNotice() } else { Reports() } }.tabItem { Label("Звіти", systemImage: "chart.bar.xaxis") }
          NavigationStack { More() }.tabItem { Label("Ще", systemImage: "ellipsis.circle") }
        }.task(id: phase) {
          guard phase == .active else {return}
          while !Task.isCancelled {
            store.refreshCaptures()
            do {try await Task.sleep(nanoseconds: 3_000_000_000)} catch {break}
          }
        }
      }
    }.onChange(of: phase) { p in if p == .background && lockEnabled { unlocked = false } }.alert(
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
  var filterBinding:Binding<String>{Binding(get:{filter},set:{v in s.change{d in var p=d.preferences ?? .init();p.operationsFilter=v;d.preferences=p}})}
  var sortBinding:Binding<OperationSort>{Binding(get:{sort},set:{v in s.change{d in var p=d.preferences ?? .init();p.operationsSort=v.rawValue;d.preferences=p}})}
  @State private var voice = false
  @State private var scan = false
  @State private var accountFilter = "all"
  @State private var categoryFilter = "all"
  var filtered: [Operation] {
    s.db.operations.filter { o in
      (filter == "all" || o.kind.rawValue == filter) &&
      (accountFilter == "all" || o.account == accountFilter || (o.kind == .transfer && o.destination == accountFilter)) &&
      (categoryFilter == "all" || o.category == categoryFilter) &&
      (search.isEmpty || (o.note + " " + o.category + " " + (s.privateAmounts ? "" : amountText(o.amount)) + " " + s.accountName(o.account)).localizedCaseInsensitiveContains(search))
    }.sorted { sort.orders($0, $1) }
  }
  var chronological: Bool { sort == .newest || sort == .oldest }

  func action(_ kind: Kind, _ title: String, _ icon: String, _ tint: Color) -> some View {
    Button { edit = Operation(kind: kind, account: s.db.accounts.first?.id ?? cash) } label: {
      VStack(spacing: 6) { FinamiIconTile(icon: icon, tint: tint, side: 40); Text(title).font(.caption.weight(.medium)) }.frame(maxWidth: .infinity).padding(.vertical, 6)
    }.buttonStyle(.plain)
  }
  func operationList(_ values: [Operation]) -> some View {
    VStack(spacing: 0) {
      ForEach(values) { o in
        Button { edit = o } label: { OperationRow(o: o).padding(.vertical, 12).padding(.horizontal, 12).contentShape(Rectangle()) }.buttonStyle(.plain)
        if o.id != values.last?.id { Divider().padding(.leading, 62) }
      }
    }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
  }
  var body: some View {
    let values = filtered
    let grouped = Dictionary(grouping: values) { Calendar.current.startOfDay(for: $0.date) }
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
        } else { operationList(values) }
      }.padding()
    }.background(Color(uiColor: .systemGroupedBackground)).searchable(text: $search, prompt: "Магазин, категорія, сума").navigationTitle("Операції")
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
struct Accounts: View {
  @EnvironmentObject var s: Store
  @State private var edit: Account?
  @State private var configure = false
  @State private var reorder = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var prefs: AppearancePreferences { s.db.preferences ?? .init() }
  var mode: String { prefs.accountsMode ?? "own" }
  func update(_ action:(inout AppearancePreferences)->Void) { s.change { d in var p=d.preferences ?? .init();action(&p);d.preferences=p } }
  var shown:[Account] { s.db.accounts.filter { (prefs.accountsShowHidden == true || $0.hiddenInAccounts != true) && (mode == "all" || (mode == "credit" ? $0.isCredit : (!$0.isCredit || s.ownFunds($0)>0))) } }
  var body: some View {
    ScrollView { VStack(spacing: 14) {
      FinamiAccountsBalance()
      Button { reorder = true } label: { Label("Змінити порядок рахунків", systemImage: "arrow.up.arrow.down").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.plain).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
      Picker("Розділ",selection:Binding(get:{mode},set:{v in update{$0.accountsMode=v}})){Text("Власні").tag("own");Text("Кредитні").tag("credit");Text("Усі").tag("all")}.pickerStyle(.segmented)
      if mode != "own" { FinamiCreditSummary(showLimit:prefs.accountsShowLimit ?? true,showUsed:prefs.accountsShowUsed ?? true,showAvailable:prefs.accountsShowAvailable ?? true).environment(\.finamiMask, prefs.accountsHideCredit == true) }
      if shown.isEmpty { FinamiEmptyCard(title: "Немає рахунків", detail: "Додай рахунок або зміни режим відображення.", icon: "wallet.pass") }
      ForEach(finamiOrderedAccounts(shown)) { a in
        VStack(alignment: .leading, spacing: 5) {
          FinamiHomeAccountCard(accountID: a.id, date: Date(), fallbackTint: .teal, mode: mode, onAccountsScreen: true)
          if a.hiddenInAccounts == true { Label("Прихований рахунок", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
          if a.excludedFromTotals == true { Text("Не враховується в загальних сумах").font(.caption).foregroundStyle(.secondary) }
          if s.nativeBalance(a) < 0 && !a.isCredit { Text("Чистий залишок: " + (a.hideAmounts == true ? "••••" : s.visibleMoney(s.nativeBalance(a), a.code))).font(.caption).foregroundStyle(.secondary) }
        }
      }
      Button {edit=Account(name:"",accountType:"debit")} label:{Label("Додати рахунок",systemImage:"plus.circle.fill").frame(maxWidth:.infinity).padding(8)}.buttonStyle(.borderedProminent)
      NavigationLink { FinamiScanView(initialMode: .balance) } label: { Label("Звірити зі скриншота", systemImage: "doc.viewfinder") }
      NavigationLink("Перевірити старі імпортовані операції") { CreditImportCorrection() }
    }.padding() }.background(Color(uiColor:.systemGroupedBackground)).navigationTitle("Рахунки").toolbar {
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
  func binding<T>(_ key:WritableKeyPath<AppearancePreferences,T?>,_ fallback:T)->Binding<T>{Binding(get:{(s.db.preferences ?? .init())[keyPath:key] ?? fallback},set:{v in s.change{d in var p=d.preferences ?? .init();p[keyPath:key]=v;d.preferences=p}})}
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
        FinamiMetric(title: "Доступний кредит", value: display(max(0,a.limit-s.debt(a))), tint: .green)
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
    let old=s.db.accounts.first{$0.id==a.id}
    let history=old.map{s.nativeBalance($0)-$0.opening} ?? 0
    let result=net-history
    return abs(result)<=1_000_000_000_000 ? result : nil
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
  }
  var body: some View {
    NavigationStack {
      Form {
        TextField("Назва", text: $a.name)
        Picker("Тип рахунку",selection:Binding(get:{a.accountType ?? (a.id == cash ? "cash" : "other")},set:{a.accountType=$0;if $0 != "credit" {actualMode="net"}})) {
          Text("Готівка").tag("cash");Text("Дебетова картка").tag("debit");Text("Кредитна картка").tag("credit");Text("Інший рахунок").tag("other")
        }
        TextField("Банк (необов’язково)",text:Binding(get:{a.bankName ?? ""},set:{a.bankName=$0}))
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
        Toggle("Звірити з поточним балансом банку",isOn:$correctBalance)
        if correctBalance {
          if a.isCredit {Picker("Яку суму показує банк",selection:$actualMode){Text("Чистий баланс (+ власні / − борг)").tag("net");Text("Доступно разом з кредитом").tag("available");Text("Власні кошти та використаний кредит").tag("components")}}
          if a.isCredit && actualMode == "components" {componentFields} else {FinamiField("Поточна сума, \(a.code)", text: $actualText, keyboard: .numbersAndPunctuation)}
          Text("Початковий залишок буде скориговано з урахуванням усієї записаної історії. Це не створює дохід. Не застосовуй до неповної історії без звірки.").font(.caption)
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
            a.opening = n
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
            a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newOpening == nil || !validLimit || (a.code == "USD" && s.currentRate == nil))
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
    ScrollView { VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Finami").font(.system(size: 40, weight: .bold, design: .rounded))
        Text("Особисті фінанси.").font(.subheadline).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(18).modifier(FinamiCardStyle(tint: .teal))
      FinamiMenuGroup("Планування") {
        NavigationLink { SubscriptionsView() } label: { FinamiMenuLabel(title: "Підписки", icon: "repeat", color: .purple) }
        NavigationLink { ReminderList() } label: { FinamiMenuLabel(title: "Нагадування", icon: "bell.badge.fill", color: .red) }
        NavigationLink { CurrencySettings() } label: { FinamiMenuLabel(title: "Валюти та курси", icon: "dollarsign.circle.fill", color: .green) }
        NavigationLink { CurrencyCalculator() } label: { FinamiMenuLabel(title: "Конвертер валют", icon: "dollarsign.arrow.circlepath", color: .cyan) }
        NavigationLink { ForecastView() } label: { FinamiMenuLabel(title: "Фінансовий прогноз", icon: "chart.line.uptrend.xyaxis", color: .green) }
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
        }
        NavigationLink {
          Insights()
        } label: {
          FinamiMenuLabel(title: "Фінансовий помічник", icon: "sparkles", color: .purple)
        }
      }
      FinamiMenuGroup("Банки") {
        NavigationLink { FinamiImportHub() } label: { FinamiMenuLabel(title: "Центр імпорту та перевірки", icon: "tray.full.fill", color: .indigo) }.accessibilityIdentifier("qa.smart.hub")
        NavigationLink { FinamiScanView() } label: { FinamiMenuLabel(title: "Finami Scan · зі скриншота", icon: "doc.viewfinder", color: .purple) }
        NavigationLink { BankCenter() } label: { FinamiMenuLabel(title: "Банки та імпорт", icon: "building.columns.fill", color: .cyan) }
        NavigationLink { AutomationCenter() } label: { FinamiMenuLabel(title: "Автоматизація · Apple Pay / SMS (\(s.capturePending.count))", icon: "bolt.fill", color: .orange) }
      }
      FinamiMenuGroup("Персоналізація") {
        NavigationLink { FinamiDiagnostics() } label: { FinamiMenuLabel(title: "Діагностика Finami", icon: "checkmark.shield.fill", color: .green) }.accessibilityIdentifier("qa.smart.diagnostics")
        NavigationLink { FinamiHelp() } label: { FinamiMenuLabel(title: "Допомога та інструкції", icon: "book.fill", color: .blue) }
        NavigationLink { DashboardSettings() } label: { FinamiMenuLabel(title: "Блоки огляду", icon: "square.grid.2x2.fill", color: .orange) }
        NavigationLink { AppearanceView() } label: { FinamiMenuLabel(title: "Студія дизайну", icon: "paintpalette.fill", color: .pink) }
        NavigationLink {
          Categories()
        } label: {
          FinamiMenuLabel(title: "Категорії", icon: "tag.fill", color: .teal)
        }
        NavigationLink {
          Settings()
        } label: {
          FinamiMenuLabel(title: "Захист та резервні копії", icon: "lock.shield.fill", color: .green)
        }
      }
      VStack(alignment: .leading) {
        Text("Finami · 5.0 Preview 10.2\nБез реклами, серверів та платних API.").font(.footnote)
          .foregroundStyle(.secondary)
      }
    }.padding() }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Ще").toolbar{Button{menuSettings=true} label:{Image(systemName:"slider.horizontal.3")}.accessibilityLabel("Налаштування меню")}.sheet(isPresented:$menuSettings){NavigationStack{Form{Toggle("Компактні ілюстрації",isOn:Binding(get:{s.db.preferences?.menuCompact ?? false},set:{v in s.change{d in var p=d.preferences ?? .init();p.menuCompact=v;d.preferences=p}}));NavigationLink("Студія дизайну"){AppearanceView()};NavigationLink("Блоки головної"){DashboardSettings()};NavigationLink("Рахунки"){FinamiAccountSettings()}}.navigationTitle("Налаштування меню").toolbar{Button("Готово"){menuSettings=false}}}}
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
struct Obligations: View {
  @EnvironmentObject var s: Store
  var kind: ObligationKind
  @State private var edit: Obligation?
  var body: some View {
    List {
      if kind == .installment { NavigationLink { FinamiScanView(initialMode: .installment) } label: { Label("Додати зі скриншота", systemImage: "doc.viewfinder") } }
      Section("Загальний залишок") {
        Text(s.visibleMoney(s.db.obligations.filter { $0.kind == kind }.reduce(0) { $0 + $1.remaining }))
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
              Text(s.visibleMoney(o.remaining))
            }
            if !s.privateAmounts { ProgressView(value: o.target > 0 ? min(1, Double(o.paid) / Double(o.target)) : 0) }
            Text(
              "\(s.visibleMoney(o.paid)) із \(s.visibleMoney(o.target)) · \(o.due.formatted(date:.abbreviated,time:.omitted))"
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
  @State var remainingText: String
  @State var payment = ""
  @State var log = false
  @State var account = cash
  @State var confirm = false
  init(original: Obligation) {
    _o = State(initialValue: original)
    _target = State(initialValue: amountText(original.target))
    _paid = State(initialValue: amountText(original.paid))
    _monthly = State(initialValue: amountText(original.monthly))
    _remainingText = State(initialValue: amountText(original.remaining))
  }
  var baseTarget: Int64? { cents(target) }
  var basePaid: Int64? { o.kind == .installment ? cents(remainingText).flatMap { r in baseTarget.map { $0 - r } } : cents(paid) }
  var valid: Bool {
    !o.name.trimmingCharacters(in: .whitespaces).isEmpty && (baseTarget ?? 0) > 0
      && (o.kind != .installment || (cents(remainingText) ?? -1) >= 0)
      && (basePaid ?? -1) >= 0 && (basePaid ?? 0) <= (baseTarget ?? 0)
      && (cents(monthly) ?? -1) >= 0
      && (payment.isEmpty
        || ((cents(payment) ?? 0) > 0
          && (cents(payment) ?? 0) <= (baseTarget ?? 0) - (basePaid ?? 0)))
  }
  var body: some View {
    NavigationStack {
      Form {
      if let rows = o.importedSchedule, !rows.isEmpty {
        Section("Графік з банківського скриншота") {
          ForEach(rows) { row in LabeledContent(row.date.formatted(date: .abbreviated, time: .omitted), value: s.visibleMoney(row.amount)) }
          Text("Довідкові дані імпорту; можуть застаріти після зміни договору.").font(.caption)
          Button("Видалити довідковий графік", role: .destructive) { o.importedSchedule = nil }
        }
      }

        Section("Параметри") {
          FinamiField("Назва", text: $o.name)
          if o.kind == .installment {
            FinamiField("Загальний кредит, ₴", text: $target, keyboard: .decimalPad)
            FinamiField("Поточний залишок розстрочки, ₴", text: $remainingText, keyboard: .decimalPad)
            Text("Введи залишок боргу, не суму вже сплачених платежів.").font(.caption)
          } else {
            FinamiField("Загальна сума, ₴", text: $target, keyboard: .decimalPad)
            FinamiField("Вже сплачено / накопичено", text: $paid, keyboard: .decimalPad)
          }
          FinamiField("Регулярний платіж, ₴", text: $monthly, keyboard: .decimalPad)
          DatePicker("Наступна дата / термін", selection: $o.due, displayedComponents: [.date, .hourAndMinute])
          if let imageID = o.scanImageID { NavigationLink("Вкладений скриншот") { FinamiScanAttachment(imageID: imageID) } }
          if s.db.obligations.contains(where: { $0.id == o.id }) {
            NavigationLink("Нагадування") { ReminderEditor(original: PersonalReminder(title: o.name, date: o.due, linkedID: o.id)) }
          }
        }
        Section("Додати платіж або накопичення") {
          FinamiField("Сума", text: $payment, keyboard: .decimalPad)
          if o.kind != .goal {
            Toggle("Також записати операцію", isOn: $log)
            if log {
              Picker("Рахунок", selection: $account) {
                ForEach(s.db.accounts.filter{$0.code == "UAH"}) { Text($0.name).tag($0.id) }
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
            guard valid, let t = baseTarget, let p = basePaid, let m = cents(monthly) else {
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
              if extra > 0 && log && o.kind != .goal && d.accounts.contains(where:{$0.id==account && $0.code=="UAH"}) {
                d.operations.append(
                  Operation(
                    kind: o.kind == .owed ? .movementIn : o.kind == .recurring ? .expense : .creditRepayment, amount: extra, category: "Інше",
                    note: o.name, account: account))
              }
            }) {
              dismiss()
            }
          }.disabled(!valid)
        }
      }.confirmationDialog("Видалити запис?", isPresented: $confirm) {
        Button("Видалити", role: .destructive) {
          let linked=(s.db.reminders ?? []).filter{$0.linkedID==o.id}
        if s.change({d in d.obligations.removeAll{$0.id==o.id};d.reminders?.removeAll{$0.linkedID==o.id}}) {linked.forEach{ReminderScheduler.cancel($0)};dismiss()}
        }
      }
    }
  }
}
struct CalendarView: View {
  @EnvironmentObject var s: Store
  @State private var selected: FinamiPayment?
  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        FinamiMonthPayments()
        if s.upcomingPayments.isEmpty { Text("Немає запланованих платежів").foregroundStyle(.secondary).padding() }
        ForEach(s.upcomingPayments) { p in
          Button { selected = p } label: { FinamiPaymentCard(payment:p) }.buttonStyle(.plain)
        }
      }.padding()
    }.background(Color(uiColor:.systemGroupedBackground)).navigationTitle("Календар платежів")
      .sheet(item:$selected) { FinamiPaymentDetails(payment:$0) }
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
    }.navigationTitle("Категорії").toolbar { EditButton(); Button { editing=nil;name="";parent="";adding=true } label:{Image(systemName:"plus.circle.fill")} }
      .sheet(isPresented:$adding) { NavigationStack { Form { TextField("Іконка та назва",text:$name); if !income { TextField("Група (необов’язково)",text:$parent) }; Button("Зберегти") { save() }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (cats.contains(name.trimmingCharacters(in:.whitespacesAndNewlines)) && editing != name.trimmingCharacters(in:.whitespacesAndNewlines))) }.navigationTitle(editing == nil ? "Нова категорія" : "Редагування").toolbar { Button("Скасувати") { adding=false } } } }
      .confirmationDialog("Перенести операції перед видаленням",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) { ForEach(cats.filter{$0 != deleting},id:\.self) { c in Button("Перенести в «"+c+"»") { if let old=deleting { replace(old,with:c,remove:true) };deleting=nil } }; Button("Скасувати",role:.cancel){deleting=nil} } message:{Text("Операції не видаляються. Бюджет і правила категорії буде перенесено.")}
  }
  func toggle(_ c:String) { s.change { d in var list=income ? d.hiddenIncomeCategories ?? [] : d.hiddenExpenseCategories ?? []; if list.contains(c) { list.removeAll{$0==c} } else { list.append(c) }; if income {d.hiddenIncomeCategories=list} else {d.hiddenExpenseCategories=list} } }
  func save() { let c=name.trimmingCharacters(in:.whitespacesAndNewlines); guard !c.isEmpty, !cats.contains(c) || editing==c else{return}; if let old=editing,old != c { replace(old,with:c,remove:false) } else if editing==nil {s.change{d in if income{d.incomeCategories.append(c)}else{d.expenseCategories.append(c)}}}; if !income {s.change{d in var groups=d.categoryParents ?? [:];groups[c]=parent.isEmpty ? nil : parent;d.categoryParents=groups}};adding=false }
  func replace(_ old:String,with new:String,remove:Bool) { s.change { d in
    if income { d.incomeCategories.removeAll{$0==old};if !remove{d.incomeCategories.append(new)};d.hiddenIncomeCategories?.removeAll{$0==old} }
    else {d.expenseCategories.removeAll{$0==old};if !remove{d.expenseCategories.append(new)};d.hiddenExpenseCategories?.removeAll{$0==old};d.categoryParents?.removeValue(forKey:old);if let limit=d.limits.removeValue(forKey:old){d.limits[new,default:0]+=limit} }
    for i in d.operations.indices where d.operations[i].category==old && (income ? d.operations[i].kind == .income : [.expense,.refund].contains(d.operations[i].kind)) {d.operations[i].category=new}
    if var rules=d.merchantRules {for key in Array(rules.keys) where rules[key]==old && (income ? key.hasPrefix("income:") : key.hasPrefix("expense:")){rules[key]=new};d.merchantRules=rules}
    if !income, var items=d.dashboard {for i in items.indices {items[i].categorySelection=items[i].categorySelection?.map{$0==old ? new : $0}};d.dashboard=items}
  } }
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
  @State private var fileName = "Finami-backup"
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
        NavigationLink("Зашифровані резервні копії") { FinamiSecureBackupView() }
        NavigationLink("Локальні попередні копії") { SnapshotView() }
        Text("Зберігай експорт JSON у «Файли» / iCloud Drive. Автоматична хмарна синхронізація ще не підключена.").font(.caption)
        Button("Експорт JSON") {
          format = .json
          fileName = "Finami-backup"
          doc = s.backup()
          exporting = true
        }
        Button("Експорт CSV для Excel") {
          format = .commaSeparatedText
          fileName = "Finami-operations"
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
