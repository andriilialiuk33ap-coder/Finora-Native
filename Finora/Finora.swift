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
  var statementIBAN: String? = nil
  var additionalCardMasks: [String]? = nil
  var reconciliationDate: Date? = nil
  var reconciliationNet: Int64? = nil
  var reconciliationEstimated: Bool? = nil
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
// Original bank legs of a confirmed grouped conversion; not separate ledger movements.
struct FinamiBankPart: Codable, Equatable {
  var key: String
  var date: Date
  var amount: Int64
  var note: String
  var importBatch: String?
  var sourceBank: String?
  var originalAmount: Int64?
  var originalCurrency: String?
  var postingDate: Date?
}
struct Operation: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var kind: Kind = .expense
  var amount: Int64 = 0
  var date = Date()
  var category = "Інше"
  var note = ""
  var account = cash
  var destination = ""
  var bankKey: String? = nil
  var destinationBankKey: String? = nil
  var groupedBankParts: [FinamiBankPart]? = nil
  var refundOriginalID: String? = nil
  var statementIBAN: String? = nil
  var bankPostingDate: Date? = nil
  var bankPostingKnown: Bool? = nil
  var creditContractSuffix: String? = nil
  var destinationBankNote: String? = nil
  var mergedImportBatches: [String]? = nil
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
  var tags: [String]? = nil
  var signedNative: Int64 { kind.incoming ? (sourceMinor ?? amount) : -(sourceMinor ?? amount) }
  // Only count an embedded fee separately when it is demonstrably part of a non-expense debit.
  var neutralFee: Int64 {
    guard !kind.incoming, kind != .expense, kind != .transfer, sourceBank == "А-БАНК", originalCurrency == "UAH", let originalAmount, let bankFee, bankFee > 0, originalAmount == amount - bankFee else {return 0}
    return bankFee
  }
  var sourceLabel: String {
    if let captureSource, !captureSource.isEmpty { return captureSource }
    if sourceBank != nil || bankKey != nil || groupedBankParts != nil || destinationBankKey != nil { return "Банківська виписка" }
    if scanImageID != nil || scanFingerprint != nil { return "Сканування" }
    if importBatch != nil { return "Імпорт" }
    return "Ручний / невідоме джерело"
  }
  var expenseValue: Int64 { kind == .expense ? amount : kind == .refund ? -amount : neutralFee }
  var expenseGroup: String { kind == .expense || kind == .refund ? category : "🏦 Комісії" }
}
// Derived, in-memory ledger index. Never persisted or used as a source of truth.
struct FinamiLedgerIndex {
  private var deltas: [String: Int64] = [:]
  private var histories: [String: [Operation]] = [:]
  private var anchors: [String: Date] = [:]
  private var anchoredDeltas: [String: Int64] = [:]
  init(operations: [Operation], accounts:[Account] = []) {
    for a in accounts { if let date=a.reconciliationDate,a.reconciliationNet != nil {anchors[a.id]=date} }
    for o in operations {
      if o.kind == .transfer {
        deltas[o.account, default: 0] -= o.sourceMinor ?? o.amount
        deltas[o.destination, default: 0] += o.destinationMinor ?? o.amount
        if o.destination != o.account { histories[o.destination, default: []].append(o) }
      } else { deltas[o.account, default: 0] += o.signedNative }
      histories[o.account, default: []].append(o)
      if let d=anchors[o.account] { anchoredDeltas[o.account,default:0] += Self.movement(o,account:o.account,after:d,until:nil) }
      if o.kind == .transfer,o.destination != o.account,let d=anchors[o.destination] { anchoredDeltas[o.destination,default:0] += Self.movement(o,account:o.destination,after:d,until:nil) }
    }
  }
  // Bank legs retain their actual timestamps for historical balances.
  private static func movement(_ o:Operation,account:String,after:Date?,until:Date?)->Int64 {
    func includes(_ date:Date)->Bool {(after.map{date>$0} ?? true) && (until.map{date<=$0} ?? true)}
    var value:Int64=0
    if o.account==account,includes(o.date){value += o.signedNative}
    if o.kind == .transfer,o.destination==account {
      if let parts=o.groupedBankParts {for p in parts where includes(p.date) {value += p.amount}}
      else if includes(o.date){value += o.destinationMinor ?? o.amount}
    }
    return value
  }
  func balance(_ a: Account) -> Int64 {
    if let date=a.reconciliationDate,let net=a.reconciliationNet {
      if anchors[a.id]==date {return net+(anchoredDeltas[a.id] ?? 0)}
      return net+history(a.id).reduce(0){$0+Self.movement($1,account:a.id,after:date,until:nil)}
    }
    return a.opening + (deltas[a.id] ?? 0)
  }
  func balanceAt(_ a:Account,date:Date)->Int64 {
    let rows=history(a.id)
    if let anchor=a.reconciliationDate,let net=a.reconciliationNet {
      if date>=anchor {return net+rows.reduce(0){$0+Self.movement($1,account:a.id,after:anchor,until:date)}}
      return net-rows.reduce(0){$0+Self.movement($1,account:a.id,after:date,until:anchor)}
    }
    return a.opening+rows.reduce(0){$0+Self.movement($1,account:a.id,after:nil,until:date)}
  }
  func history(_ id: String) -> [Operation] { histories[id] ?? [] }
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
  var creditContractSuffix: String? = nil
  var scanFingerprint: String? = nil
  var scanImageID: String? = nil
  var scanSourceIDs: [String]? = nil
  var importedSchedule: [FinamiScheduleRow]? = nil
  var currentDuePaid: Int64? = nil
  var remaining: Int64 { max(0, target - paid) }
  var nextCharge: Int64 { monthly > 0 ? min(max(0, monthly - max(0, currentDuePaid ?? 0)), remaining) : remaining }
}
// Optional history keeps older Finora.json files compatible.
struct FinamiPaidRecord: Codable, Identifiable {
  var id = UUID().uuidString
  var paymentID: String
  var scheduledDate: Date
  var paidDate: Date
  var amount: Int64
  var currency: String
  var accountID: String?
  var operationID: String?
  var obligationUndo: FinamiObligationUndo? = nil
  var historicalOnly: Bool? = nil
}
struct FinamiObligationUndo: Codable {
  var beforePaid: Int64; var beforeDue: Date; var beforeProgress: Int64?
  var afterPaid: Int64; var afterDue: Date; var afterProgress: Int64?
  var target: Int64; var monthly: Int64
  var priorReminders: [PersonalReminder]
  var renewedReminders: [PersonalReminder]
}
struct FinamiExchangeRecord: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var kind = "income"
  var date = Date()
  var units: Int64 = 0
  var fee: Int64 = 0
  var feeIncluded = true
  var orderUAH: Int64 = 0
  var receivedUAH: Int64 = 0
  var rate = ""
  var note = ""
  var linkedReceiptIDs: [String]? = nil
}
struct FinamiPartnerGroup: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var name = ""
  var limit: Int64 = 0
  var prepaid: Int64 = 0
  var obligationIDs: [String] = []
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
  var appearanceRevision: String? = nil
  var subscriptions: [SubscriptionRecord]? = nil
  var reminders: [PersonalReminder]? = nil
  var forecast: ForecastPreferences? = nil
  var merchantRules: [String: String]? = nil
  var dismissedRecurringSuggestions: [String]? = nil
  var currencyPreferences: CurrencyPreferences? = nil
  var capturePreferences: CapturePreferences? = nil
  var captureHandled: [String]? = nil
  var balanceObservations: [String: FinamiBalanceObservation]? = nil
  var captureMessageFingerprints: [String]? = nil
  var hiddenExpenseCategories: [String]? = nil
  var hiddenIncomeCategories: [String]? = nil
  var categoryParents: [String: String]? = nil
  var paymentPhotos: [String: Data]? = nil
  var paidRecords: [FinamiPaidRecord]? = nil
  var scanImages: [String: Data]? = nil
  var reconciliationUndo: Data? = nil
  var exchangeDiary: [FinamiExchangeRecord]? = nil
  var partnerGroups: [FinamiPartnerGroup]? = nil
  var removedInstallments: [Obligation]? = nil
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
  static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .pdf, UTType(filenameExtension: "xlsx") ?? .data, UTType(filenameExtension: "ics") ?? .data] }
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
  @Published private(set) var db = Database() {
    didSet {
      mutationVersion &+= 1
      if oldValue.operations != db.operations { ledgerIndex = nil; reportCache.removeAll(); comparisonCache.removeAll(); activityCache.removeAll(); historyCache.removeAll(); dashboardMonthCache.removeAll() }
      if oldValue.accounts.map(\.id) != db.accounts.map(\.id) || oldValue.accounts.map(\.name) != db.accounts.map(\.name) || oldValue.accounts.map(\.hideAmounts) != db.accounts.map(\.hideAmounts) { historyCache.removeAll() }
      if oldValue.accounts.map(\.reconciliationDate) != db.accounts.map(\.reconciliationDate) || oldValue.accounts.map(\.id) != db.accounts.map(\.id) {ledgerIndex=nil}
    }
  }
  private var mutationVersion: UInt64 = 0
  private var ledgerIndex: FinamiLedgerIndex?
  private var dashboardMonthCache: [DateInterval: [Operation]] = [:]
  private struct ActivityKey: Hashable { let account: String; let currency: String; let month: Date }
  private var activityCache: [ActivityKey: AccountActivity] = [:]
  private var historyCache: [FinamiHistoryQuery: [Operation]] = [:]
  func queryHistory(_ query: FinamiHistoryQuery) -> [Operation] {
    if let cached = historyCache[query] { return cached }
    let source = query.account == "all" ? db.operations : historyForAccount(query.account)
    let names = Dictionary(db.accounts.map{($0.id,$0.name)},uniquingKeysWith:{first,_ in first})
    let masked = Set(db.accounts.filter { $0.hideAmounts == true }.map { $0.id })
    let results = query.apply(to:source, names:names, maskedAccounts:masked)
    if historyCache.count >= 4 { historyCache.removeAll(keepingCapacity:true) }
    historyCache[query] = results
    return results
  }
  private var reportCache = FinamiReportCache()
  private var comparisonCache = FinamiComparisonCache()
  func reportComparison(current: DateInterval, previous: DateInterval, account: String?, elapsed: Bool) -> (current: FinamiReportTotals, previous: FinamiReportTotals) {
    comparisonCache.totals(operations:db.operations,current:current,previous:previous,account:account,elapsed:elapsed)
  }
  private var indexedLedger: FinamiLedgerIndex {
    if let ledgerIndex { return ledgerIndex }
    let index = FinamiLedgerIndex(operations: db.operations,accounts:db.accounts)
    ledgerIndex = index
    return index
  }
  func historyForAccount(_ id: String) -> [Operation] { indexedLedger.history(id) }
  func accountActivity(_ account: Account, month: Date) -> AccountActivity {
    let key = ActivityKey(account:account.id,currency:account.code,month:Calendar.current.dateInterval(of:.month,for:month)?.start ?? month)
    if let cached = activityCache[key] { return cached }
    let result = AccountActivity(account: account, operations: indexedLedger.history(account.id), month: month)
    if activityCache.count >= 64 { activityCache.removeAll(keepingCapacity:true) }
    activityCache[key] = result
    return result
  }
  func reportSnapshot(date: Date, annual: Bool, account: String?) -> FinamiReportSnapshot {
    reportCache.snapshot(operations: db.operations, date: date, annual: annual, account: account)
  }
  @Published var widgetRoute: String? = nil
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
  private var appearanceURL: URL { url.deletingLastPathComponent().appendingPathComponent("FinamiAppearance.json") }
  @Published private(set) var loading = true
  private var loadingStarted = false
  // Keep the first frame responsive and never show or mutate an empty ledger while the real database is loading.
  func loadDatabase() async {
    guard loading, !loadingStarted else { return }
    loadingStarted = true; ready = false
    let file = url, settingsFile = appearanceURL
    do {
      let result = try await Task.detached(priority:.userInitiated) { () throws -> (Database, String?) in
        let manager = FileManager.default
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--finami-qa"), ProcessInfo.processInfo.arguments.contains("--finami-qa-reset") {
          if manager.fileExists(atPath:file.path) { try manager.removeItem(at:file) }
          try? manager.removeItem(at:settingsFile)
        }
        #endif
        try manager.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        var loaded = Database()
        var warning: String?
        if manager.fileExists(atPath:file.path) {
          loaded = try JSONDecoder().decode(Database.self,from:Data(contentsOf:file,options:.mappedIfSafe))
          if loaded.appearanceRevision != nil, manager.fileExists(atPath:settingsFile.path) {
            do { loaded.preferences = try FinamiAppearanceSidecar<AppearancePreferences>.resolve(base:loaded.preferences,revision:loaded.appearanceRevision,data:Data(contentsOf:settingsFile)) }
            catch { warning = "Налаштування оформлення не читаються. Фінансові дані збережено." }
          }
        }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--finami-qa"), !manager.fileExists(atPath:file.path) {
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-recurring-fixture") {
            loaded.accounts.append(Account(id:"qa-recurring",name:"QA subscription card",opening:100000))
            let cal = Calendar.current
            loaded.operations = [-2,-1,0].map { offset in
                Operation(kind:.expense,amount:10000,date:cal.date(byAdding:.month,value:offset,to:Date().addingTimeInterval(-86400)) ?? Date(),category:"📺 Підписки",note:"QA Streaming",account:"qa-recurring")
            }
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-reports-fixture") {
            loaded.accounts.append(Account(id:"qa-pumb",name:"QA Pumb"))
            loaded.accounts.append(Account(id:"qa-otp",name:"QA OTP"))
            loaded.operations = [Operation(kind:.expense,amount:30000,account:"qa-pumb"),Operation(kind:.income,amount:100000,account:"qa-pumb"),Operation(kind:.expense,amount:10000,account:"qa-otp"),Operation(kind:.income,amount:20000,account:"qa-otp")]
            var p = AppearancePreferences(); p.reportsShowComparison=false; p.reportsShowCategories=false; p.reportsShowChart=false; loaded.preferences=p
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-design-fixture") {
            loaded.accounts = [Account(id:"qa-design-credit",name:"QA Credit Card",opening:-10000,accountType:"credit",creditLimit:100000),Account(id:"qa-design-debit",name:"QA Debit",opening:50000,accountType:"debit")]
            var p=AppearancePreferences();p.modernAccountGrid=true;p.designLayout="grid";p.accountsMode="all";loaded.preferences=p
          }
          if ProcessInfo.processInfo.arguments.contains("--finami-qa-payment-fixture") || ProcessInfo.processInfo.arguments.contains("--finami-qa-link-fixture") {
            loaded.accounts.append(Account(id:"qa-card",name:"QA Card",opening:100000))
            loaded.obligations.append(Obligation(id:"qa-loan",kind:.installment,name:"QA installment",target:30000,paid:10000,monthly:10000,due:Date().addingTimeInterval(-86400)))
            if ProcessInfo.processInfo.arguments.contains("--finami-qa-link-fixture") { loaded.operations.append(Operation(kind:.creditRepayment,amount:10000,note:"QA existing debit",account:"qa-card")) }
          }
        }
        #endif
        return (loaded,warning)
      }.value
      db = result.0; error = result.1; ready = true
    } catch let loadError { self.error = "База не читається. Запис заблоковано, щоб не втратити дані. " + loadError.localizedDescription }
    loading = false
  }
  @discardableResult func change(_ update: (inout Database) -> Void) -> Bool {
    guard ready else {
      error = "Запис заблоковано. Віднови базу з копії."
      return false
    }
    var copy = db
    update(&copy)
    guard finamiLinkedOperationsPreserved(before: db, after: copy) else {
      error = "Операція пов’язана з оплаченим платежем. Зміна суми, рахунку, дати, типу або видалення заблоковані, щоб не порушити графік."
      return false
    }
    guard finamiSynchronizeRefundLinks(&copy.operations) else {error="Повернення пов’язано з покупкою. Спочатку перевір або відв’яжи повернення.";return false}
    if !finamiGroupedTransfersPreserved(before:db.operations,after:copy.operations) {
      guard copy.reconciliationUndo == nil,let data=db.reconciliationUndo,let undo=try? JSONDecoder().decode(FinamiBalanceUndo.self,from:data),undo.restore(current:db.operations)==copy.operations else {error="Груповий переказ захищено. Спочатку скасуй звірку.";return false}
    }
    if db.operations != copy.operations, db.reconciliationUndo == copy.reconciliationUndo {copy.reconciliationUndo=nil}
    if let images = copy.scanImages {
      let references = Set(copy.operations.compactMap(\.scanImageID) + copy.obligations.compactMap(\.scanImageID) + (copy.removedInstallments ?? []).compactMap(\.scanImageID))
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
  @discardableResult func changeAppearance(_ update: (inout AppearancePreferences) -> Void) -> Bool {
    guard ready else { error = "Запис заблоковано. Віднови базу з копії."; return false }
    var prefs = db.preferences ?? .init(); update(&prefs)
    guard let revision = db.appearanceRevision, FileManager.default.fileExists(atPath:url.path) else {
      var copy = db; copy.preferences = prefs; return write(copy)
    }
    do {
      let data = try JSONEncoder().encode(FinamiAppearanceSidecar(revision:revision,preferences:prefs))
      try data.write(to:appearanceURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
      db.preferences = prefs
      return true
    } catch { self.error = "Не вдалося зберегти налаштування: " + error.localizedDescription; return false }
  }
  // Heavy statement imports encode a snapshot off the UI thread. The live
  // version must be unchanged before committing, so no edit can be overwritten.
  var databaseVersion: UInt64 { mutationVersion }
  func replaceOperationsForImport(_ operations: [Operation], expectedVersion: UInt64, recordUndo:Bool = false) async -> Bool {
    guard expectedVersion == mutationVersion else { error = "Дані змінилися. Повтори перевірку виписки."; return false }
    guard ready else { error = "Запис заблоковано."; return false }
    let version = mutationVersion
    var copy = db; copy.operations = operations; copy.appearanceRevision = UUID().uuidString
    guard finamiLinkedOperationsPreserved(before: db, after: copy) else { error = "Імпорт змінює операцію, пов’язану з платежем. Перевір зіставлення."; return false }
    guard finamiSynchronizeRefundLinks(&copy.operations) else {error="Імпорт порушує зв’язок повернення з покупкою.";return false}
    guard finamiGroupedTransfersPreserved(before:db.operations,after:copy.operations) else {error="Імпорт змінює груповий переказ.";return false}
    if db.operations != copy.operations {
      copy.reconciliationUndo = recordUndo ? try? JSONEncoder().encode(FinamiBalanceUndo(before:db.operations,after:copy.operations)) : nil
    }
    let candidate = copy
    do {
      let data = try await Task.detached(priority:.userInitiated) { try JSONEncoder().encode(candidate) }.value
      guard version == mutationVersion, ready else { error = "Дані змінилися під час імпорту. Повтори перевірку виписки."; return false }
      return commit(candidate, data:data)
    } catch { self.error = "Не вдалося підготувати імпорт: " + error.localizedDescription; return false }
  }
  private func write(_ copy: Database) -> Bool {
    do {
      var candidate = copy; candidate.appearanceRevision = UUID().uuidString
      return commit(candidate,data:try JSONEncoder().encode(candidate))
    } catch { self.error = "Не вдалося зберегти: " + error.localizedDescription; return false }
  }
  private func commit(_ copy: Database, data: Data) -> Bool {
    do {
      // Keep previous local snapshots before replacing the live database.
      if FileManager.default.fileExists(atPath: url.path) && ready {
        let folder = url.deletingLastPathComponent().appendingPathComponent("IzanamiSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snapshot = folder.appendingPathComponent(UUID().uuidString + ".json")
        // The live in-memory database includes the current appearance sidecar.
        if FileManager.default.fileExists(atPath:appearanceURL.path) {
          try JSONEncoder().encode(db).write(to:snapshot,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        } else { try FileManager.default.copyItem(at:url,to:snapshot) }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication, .creationDate: Date()], ofItemAtPath: snapshot.path)
        let files = snapshotURLs()
        for old in files.dropFirst(12) { try? FileManager.default.removeItem(at: old) }
      }
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      db = copy
      ready = true
      // The new revision is in the main database; older sidecar is harmless even if removal fails.
      try? FileManager.default.removeItem(at:appearanceURL)
      return true
    } catch { self.error = "Не вдалося зберегти: \(error.localizedDescription)"; return false }
  }
  func totals(_ operations: [Operation], _ kind: Kind) -> Int64 {
    if kind == .expense {return operations.reduce(0) { $0 + $1.expenseValue }}
    return operations.reduce(0) { $0 + ($1.kind == kind ? $1.amount : 0) }
  }
  func month(_ date: Date) -> [Operation] {
    let cal = Calendar.current
    guard let interval = cal.dateInterval(of:.month,for:date) else { return db.operations.filter { sameMonth($0.date,date) } }
    if let cached = dashboardMonthCache[interval] { return cached }
    let values = db.operations.filter { $0.date >= interval.start && $0.date < interval.end }
    if dashboardMonthCache.count >= 4 { dashboardMonthCache.removeAll(keepingCapacity:true) }
    dashboardMonthCache[interval] = values
    return values
  }
  var currentRate: Decimal? { fxRate(db.currencyPreferences?.usdRate ?? "") }
  func nativeBalance(_ a: Account) -> Int64 {
    indexedLedger.balance(a)
  }
  func cardPosition(_ a: Account) -> CardPosition { CardPosition(net:nativeBalance(a),limit:a.limit) }
  func ownFunds(_ a: Account) -> Int64 { cardPosition(a).own }
  func debt(_ a: Account) -> Int64 { cardPosition(a).used }
  func available(_ a: Account) -> Int64 { cardPosition(a).available }
  func unusedCredit(_ a: Account) -> Int64 { cardPosition(a).unused }
  func uah(_ n: Int64, account a: Account) -> Int64 { a.code == "USD" ? currentRate.flatMap{fxMinor(n,rate:$0)} ?? 0 : n }
  var includedAccounts: [Account] { db.accounts.filter { $0.excludedFromTotals != true } }
  var totalCreditLimit: Int64 { includedAccounts.filter(\.isCredit).reduce(0) { $0 + uah($1.limit, account: $1) } }
  var totalCreditUsed: Int64 { includedAccounts.filter(\.isCredit).reduce(0) { $0 + uah(debt($1), account: $1) } }
  var totalOwnFunds: Int64 { includedAccounts.reduce(0){$0+uah(ownFunds($1),account:$1)} }
  var totalAvailableCredit: Int64 { includedAccounts.filter(\.isCredit).reduce(0){$0+uah(unusedCredit($1),account:$1)} }
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
      var decoded = try JSONDecoder().decode(Database.self, from: data)
      guard !decoded.accounts.isEmpty,
        Set(decoded.accounts.map(\.id)).count == decoded.accounts.count,
        decoded.accounts.allSatisfy({ ["UAH","USD"].contains($0.code) && $0.opening >= -1_000_000_000_000 && $0.opening <= 1_000_000_000_000 && ($0.creditLimit ?? 0) >= 0 && ($0.creditLimit ?? 0) <= 1_000_000_000_000 && ($0.reconciliationNet.map{$0 >= -1_000_000_000_000 && $0 <= 1_000_000_000_000} ?? true) && (($0.reconciliationDate == nil) == ($0.reconciliationNet == nil)) }),
        (!decoded.accounts.contains(where:{$0.code=="USD"}) || fxRate(decoded.currencyPreferences?.usdRate ?? "") != nil),
        Set(decoded.operations.map(\.id)).count == decoded.operations.count,
        finamiExchangeBalance(decoded.exchangeDiary ?? []) != nil,
        finamiValidPartnerGroups(decoded.partnerGroups ?? []),
        Set((decoded.removedInstallments ?? []).map(\.id)).count == (decoded.removedInstallments ?? []).count,
        (decoded.removedInstallments ?? []).allSatisfy({ $0.kind == .installment && $0.target >= 0 && $0.paid >= 0 && $0.paid <= $0.target && $0.monthly >= 0 && $0.target <= 1_000_000_000_000 }),
        Set(decoded.obligations.map(\.id)).isDisjoint(with: (decoded.removedInstallments ?? []).map(\.id)),
        decoded.obligations.allSatisfy({ o in (o.importedSchedule ?? []).allSatisfy { $0.amount > 0 && $0.amount <= 1_000_000_000_000 } && (o.currentDuePaid.map { $0 >= 0 && $0 < o.monthly && $0 <= o.paid } ?? true) }),
        (decoded.balanceObservations ?? [:]).values.allSatisfy({ $0.available >= 0 && $0.available <= 1_000_000_000_000 && ["UAH","USD"].contains($0.currency) }),
        decoded.operations.allSatisfy({ o in
          o.amount > 0 && o.amount <= 1_000_000_000_000
            && finamiValidGroupedBankParts(o)
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
      guard finamiSynchronizeRefundLinks(&decoded.operations) else {error="Копія містить некоректні зв’язки повернень.";return}
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
    func q(_ s: String) -> String { finamiCSVText(s) }
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
  var body: some Scene {
    WindowGroup {
      Group {
        if store.loading { VStack(spacing:16) { Image(systemName:"wallet.pass.fill").font(.system(size:48)).foregroundStyle(finoraAccent); Text("Finami").font(.largeTitle.bold()); ProgressView("Завантаження фінансів…") }.frame(maxWidth:.infinity,maxHeight:.infinity).task { await store.loadDatabase() } }
        else { IzanamiShell().environmentObject(store) }
      }.onOpenURL { url in
          guard url.scheme == "finami-widget", let host = url.host, ["balance","payments","quick","planning"].contains(host) else { return }
          store.widgetRoute = host
      }
    }
  }
}
struct Root: View {
  @EnvironmentObject var store: Store
  @Environment(\.scenePhase) var phase
  @AppStorage("lockEnabled") var lockEnabled = false
  @AppStorage("finami.hideAppSwitcher") private var hideAppSwitcher = true
  @State private var unlocked = false
  @State private var authError = ""
  @AppStorage("finami.widgets.shareAmounts") private var widgetShare = false
  @State private var tab = 0
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
        TabView(selection: $tab) {
          NavigationStack { CustomDashboard() }.tabItem { Label(store.db.preferences?.homeTitle ?? "Головна", systemImage: "house.fill") }.tag(0)
          NavigationStack { Operations() }.tabItem {
            Label("Операції", systemImage: "arrow.left.arrow.right")
          }.tag(1)
          NavigationStack { Accounts() }.tabItem {
            Label("Рахунки", systemImage: "wallet.pass.fill")
          }.tag(2)
          NavigationStack { if store.privateAmounts { FinamiPrivacyNotice() } else { Reports() } }.tabItem { Label("Звіти", systemImage: "chart.bar.xaxis") }.tag(3)
          NavigationStack { More() }.tabItem { Label("Ще", systemImage: "ellipsis.circle") }.tag(4)
        }.task(id: phase) {
          guard phase == .active else {return}
          while !Task.isCancelled {
            store.refreshCaptures()
            do {try await Task.sleep(nanoseconds: store.capturePending.isEmpty ? 6_000_000_000 : 3_000_000_000)} catch {break}
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
      .onChange(of: phase) { p in if p == .background && lockEnabled { unlocked = false; widgetAdd = false; widgetCalendar = false; widgetPlanning = false }; if p == .active { updateWidgets() } }.alert(
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
        Image(systemName: "chevron.left").frame(width:44,height:44)
      }.accessibilityLabel("Попередній місяць")
      Spacer()
      Text(monthName(date).capitalized).font(.headline)
      Spacer()
      Button {
        date = shift(date, 1)
      } label: {
        Image(systemName: "chevron.right").frame(width:44,height:44)
      }.accessibilityLabel("Наступний місяць")
    }.padding(.vertical, 2)
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
          if s.nativeBalance(a) < 0 && !a.isCredit { Text("Чистий залишок: " + (a.hideAmounts == true ? "••••" : s.visibleMoney(s.nativeBalance(a), a.code))).font(.caption).foregroundStyle(.secondary) }
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
    ScrollView { LazyVStack(alignment: .leading, spacing: (s.db.preferences ?? .init()).finamiSpacing) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Finami").font(.title.bold())
        Text("Особисті фінанси.").font(.subheadline).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(18).modifier(FinamiCardStyle(tint: .teal))
      NavigationLink { FinamiGlobalSearch() } label: { FinamiMenuLabel(title:"Пошук Finami",icon:"magnifyingglass",color:.teal) }.buttonStyle(.plain)
      FinamiMenuGroup("Finami Next") {
        NavigationLink { FinamiNextReviewView() } label: { FinamiMenuLabel(title:"Центр перевірки операцій",icon:"checkmark.shield",color:.orange) }.accessibilityIdentifier("qa.next.review")
        NavigationLink { FinamiNextInsightsView() } label: { FinamiMenuLabel(title:"Фінансові підсумки",icon:"chart.bar.xaxis",color:.teal) }.accessibilityIdentifier("qa.next.insights")
        NavigationLink { FinamiExchangeDiaryView() } label: { FinamiMenuLabel(title:"Журнал USDT",icon:"arrow.left.arrow.right",color:.green) }.accessibilityIdentifier("qa.next.usdt")
        NavigationLink { FinamiPartnerCalculatorView() } label: { FinamiMenuLabel(title:"Партнерські кредитні ліміти",icon:"creditcard",color:.purple) }.accessibilityIdentifier("qa.next.partners")
      }
      FinamiMenuGroup("Планування") {
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
        NavigationLink { AutomationCenter() } label: { FinamiMenuLabel(title: "Автоматизація · Apple Pay / SMS (\(s.capturePending.count))", icon: "bolt.fill", color: .orange) }
      }
      FinamiMenuGroup("Персоналізація") {
        NavigationLink { FinamiWidgetsSettings() } label: { FinamiMenuLabel(title: "Віджети iPhone", icon: "square.grid.2x2", color: .teal) }
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
        Text("Finami · " + FinamiBuildInfo.version + " · " + FinamiBuildInfo.edition + "\nБез реклами, серверів та платних API.").font(.footnote)
          .foregroundStyle(.secondary)
      }
    }.padding() }.background(finamiScreenBackground(s.db.preferences)).navigationTitle("Ще").toolbar{Button{menuSettings=true} label:{Image(systemName:"slider.horizontal.3")}.accessibilityLabel("Налаштування меню")}.sheet(isPresented:$menuSettings){NavigationStack{Form{Toggle("Компактні ілюстрації",isOn:Binding(get:{s.db.preferences?.menuCompact ?? false},set:{v in s.changeAppearance { p in p.menuCompact=v }}));NavigationLink("Студія дизайну"){AppearanceView()};NavigationLink("Блоки головної"){DashboardSettings()};NavigationLink("Рахунки"){FinamiAccountSettings()}}.navigationTitle("Налаштування меню").toolbar{Button("Готово"){menuSettings=false}}}}
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
  @State private var paymentDetails: FinamiPayment?
  @State private var edit: Obligation?
  @State private var remove: Obligation?
  private func moveToArchive(_ o: Obligation) {
    let linked = (s.db.reminders ?? []).filter { $0.linkedID == o.id }
    if s.change({ d in finamiRemoveInstallment(o.id, from: &d) }) { linked.forEach { ReminderScheduler.cancel($0) } }
  }
  var body: some View {
    List {
      if kind == .installment { NavigationLink { FinamiScanView(initialMode: .installment) } label: { Label("Додати зі скриншота", systemImage: "doc.viewfinder") } }
      Section("Загальний залишок") {
        Text(s.visibleMoney(s.db.obligations.filter { $0.kind == kind }.reduce(0) { $0 + $1.remaining }))
          .font(.title.bold())
      }
      ForEach(s.db.obligations.filter { $0.kind == kind }) { o in
        HStack(spacing: 10) {
        Button {
          if let payment = s.upcomingPayments.first(where: { $0.id == o.id && !$0.subscription }) { paymentDetails = payment }
          else { edit = o }
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
        if kind == .installment {
          Button(role: .destructive) { remove = o } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44).accessibilityLabel("Видалити розстрочку") }.buttonStyle(.borderless)
        }
        }.swipeActions(edge: .trailing, allowsFullSwipe: false) {
          if kind == .installment { Button { remove = o } label: { Label("Видалити", systemImage: "trash") }.tint(.red) }
        }
      }
      if kind == .installment, let archived = s.db.removedInstallments, !archived.isEmpty {
        Section("Архів розстрочок") {
          ForEach(archived) { o in
            HStack { VStack(alignment: .leading) { Text(o.name); Text(s.visibleMoney(o.remaining)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Відновити") { s.change { d in finamiRestoreInstallment(o.id, into: &d) } }.buttonStyle(.borderless) }
          }
          Text("Відновлення повертає графік. Нагадування та прив’язку до партнерської групи налаштуй повторно.").font(.caption).foregroundStyle(.secondary)
        }
      }
    }.confirmationDialog("Прибрати розстрочку з активного плану?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
      Button("Видалити в архів", role: .destructive) { if let o = remove { moveToArchive(o) }; remove = nil }
      Button("Скасувати", role: .cancel) { remove = nil }
    } message: { Text("Банківські операції та історія сплати залишаться. Майбутні платежі й нагадування буде прибрано. Розстрочку можна відновити з архіву.") }
    .navigationTitle(kind.title).toolbar {
      Button {
        edit = Obligation(kind: kind)
      } label: {
        Image(systemName: "plus")
      }
    }.sheet(item: $edit) { ObligationEditor(original: $0) }
      .sheet(item: $paymentDetails) { FinamiPaymentDetails(payment: $0) }
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
  @State private var undoRecord: String?
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
            TextField("Останні 4 цифри договору (необов’язково)",text:Binding(get:{o.creditContractSuffix ?? ""},set:{o.creditContractSuffix=String($0.filter{$0.isASCII && $0.isNumber}.prefix(4))})).keyboardType(.numberPad)
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
        if !(s.db.paidRecords ?? []).filter({$0.paymentID == o.id}).isEmpty {
          Section("Історія оплат") { ForEach((s.db.paidRecords ?? []).filter{$0.paymentID==o.id}.sorted{$0.paidDate>$1.paidDate}) { record in VStack(alignment:.leading) { LabeledContent(record.paidDate.formatted(date:.abbreviated,time:.omitted) + " · " + (record.accountID.map{s.accountName($0)} ?? "Без списання"),value:s.visibleMoney(record.amount,record.currency)); if s.canUndoObligationPayment(record.id) { Button("Скасувати зв’язок оплати",role:.destructive) { undoRecord=record.id }.font(.caption) } } } }
        }
        if o.kind == .installment, s.db.obligations.contains(where: { $0.id == o.id }) {
          Section("Оплата") { Text("Для часткової або дострокової оплати відкрий розстрочку та натисни «Сплатив з картки / рахунку».").font(.caption) }
        } else { Section("Додати платіж або накопичення") {
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
            if o.target != t || o.paid != p || o.monthly != m || extra > 0 || s.db.obligations.first(where:{$0.id==o.id})?.due != o.due { o.currentDuePaid = nil }
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
      }.confirmationDialog("Скасувати лише зв’язок? Банківська операція залишиться в обліку.",isPresented:Binding(get:{undoRecord != nil},set:{if !$0 {undoRecord=nil}})) { Button("Відновити графік",role:.destructive) { if let id=undoRecord, s.undoObligationPayment(id) { dismiss() };undoRecord=nil } }
      .confirmationDialog("Видалити запис?", isPresented: $confirm) {
        Button("Видалити", role: .destructive) {
          let linked=(s.db.reminders ?? []).filter{$0.linkedID==o.id}
        if s.change({d in
          if o.kind == .installment { finamiRemoveInstallment(o.id, from: &d) }
          else { d.obligations.removeAll{$0.id==o.id};d.reminders?.removeAll{$0.linkedID==o.id} }
        }) {linked.forEach{ReminderScheduler.cancel($0)};dismiss()}
        }
      }
    }
  }
}
struct CalendarView: View {
  @EnvironmentObject var s: Store
  var body: some View {
    ScrollView { VStack(alignment: .leading, spacing: 16) {
        FinamiCalendarGrid().padding(14).modifier(FinamiCardStyle(tint: .teal))
        FinamiMonthPayments()
    }.padding() }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Календар платежів")
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
          Label("Платежі та ризики", systemImage: "calendar.badge.exclamationmark").font(.headline)
          let overdue = s.upcomingPayments.filter(\.overdue)
          let planned = s.scheduledThisMonth(currency: "UAH")
          let overdueUAH = overdue.filter { $0.currency == "UAH" }.reduce(Int64(0)) { $0 + $1.amount }
          let reserve = max(0, s.db.forecast?.reserve ?? 0)
          if !s.privateAmounts {
            LabeledContent("До кінця місяця · UAH", value: s.visibleMoney(planned))
            LabeledContent("Прострочено · UAH", value: s.visibleMoney(overdueUAH))
            let ownUAH = s.includedAccounts.filter { $0.code == "UAH" }.reduce(Int64(0)) { $0 + s.ownFunds($1) }
            let free = ownUAH - planned - overdueUAH - reserve
            LabeledContent("Вільні власні кошти · UAH", value: s.visibleMoney(max(0,free)))
            if free < 0 { Label("Можлива нестача коштів на заплановані оплати",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
            if s.scheduledThisMonth(currency: "USD") > 0 { Text("Доларові зобов’язання рахуються окремо.").font(.caption).foregroundStyle(.secondary) }
          }
          if !overdue.isEmpty { Text("Прострочені платежі: \(overdue.count)").foregroundStyle(.orange) }
          NavigationLink("Відкрити календар") { CalendarView() }
          Text("Прогноз, а не фактичне списання. Не включає незаплановані витрати та очікувану зарплату.").font(.caption).foregroundStyle(.secondary)
        }
        Panel {
          Label("Розумні підказки",systemImage:"sparkles").font(.headline)
          let suggestions = s.recurringSuggestions
          if !suggestions.isEmpty { Text("Можливі нові підписки: \(suggestions.count)") }
          let increases = s.recurringPriceChanges
          if !increases.isEmpty { Label("Можливе зростання тарифів: \(increases.count)",systemImage:"exclamationmark.circle").foregroundStyle(.orange) }
          ForEach(Array(increases.prefix(3))) { candidate in
            HStack { Text(candidate.merchant).lineLimit(2); Spacer(); Text(s.db.accounts.first(where:{$0.id == candidate.account})?.hideAmounts == true ? "••••" : s.visibleMoney(candidate.amount,candidate.currency)).font(.subheadline.bold()) }
          }
          if !increases.isEmpty { NavigationLink("Перевірити тарифи підписок") { SubscriptionsView() } }
          let review = s.db.operations.filter { $0.kind.needsReview }.count + s.capturePending.count
          Text("Потребують уточнення: \(review)").font(.subheadline)
          NavigationLink("Виявлення підписок") { FinamiRecurringSuggestionsView() }
          NavigationLink("Звірити залишки") { FinamiReconciliation() }
          NavigationLink("Уточнити операції") { FinamiImportHub() }
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
  @AppStorage("finami.hideAppSwitcher") private var hideAppSwitcher = true
  @State private var exporting = false
  @State private var importing = false
  @State private var legacy = false
  @State private var doc: DataFile?
  @State private var format: UTType = .json
  @State private var fileName = "Finami-backup"
  @State private var confirm = false
  @State private var pending: Data?
  @State private var restoreSummary = ""
  var body: some View {
    List {
      Section("Безпека") {
        Toggle("Face ID / код-пароль", isOn: $lock)
        Toggle("Приховувати огляд у перемикачі застосунків",isOn:$hideAppSwitcher)
        Text("Захисний екран при згортанні; момент системного знімка залежить від iOS.").font(.caption)
        Text(
          "Дані зберігаються у локальному сховищі застосунку. Видалення програми видалить і базу, тому роби резервні копії."
        ).font(.caption)
      }
      Section("Резервні копії") {
        NavigationLink("PDF, Excel, CSV, календар") { FinamiExportView() }
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
          let preview = try JSONDecoder().decode(Database.self,from:data)
          guard !preview.accounts.isEmpty, finamiExchangeBalance(preview.exchangeDiary ?? []) != nil else { throw CocoaError(.fileReadCorruptFile) }
          restoreSummary = "Рахунків: \(preview.accounts.count), операцій: \(preview.operations.count), договорів: \(preview.obligations.count), записів USDT: \((preview.exchangeDiary ?? []).count). Поточні дані буде замінено; остаточна перевірка перед записом."
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
    } message: { Text(restoreSummary) }
  }
}
