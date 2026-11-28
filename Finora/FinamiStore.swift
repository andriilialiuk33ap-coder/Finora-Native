import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

@MainActor final class Store: ObservableObject {
  @Published private(set) var db = Database() {
    didSet {
      mutationVersion &+= 1
      if assigningAppearanceOnly { return }
      cachedPaymentLookup = nil
      paymentRevision &+= 1
      if oldValue.operations != db.operations { ledgerIndex = nil; reportCache.removeAll(); comparisonCache.removeAll(); activityCache.removeAll(); historyCache.removeAll(); dashboardMonthCache.removeAll(); dashboardMetricsCache.removeAll() }
      if oldValue.accounts.map(\.id) != db.accounts.map(\.id) || oldValue.accounts.map(\.name) != db.accounts.map(\.name) || oldValue.accounts.map(\.hideAmounts) != db.accounts.map(\.hideAmounts) { historyCache.removeAll() }
      if oldValue.accounts.map(\.reconciliationDate) != db.accounts.map(\.reconciliationDate) || oldValue.accounts.map(\.reconciliationNet) != db.accounts.map(\.reconciliationNet) || oldValue.accounts.map(\.id) != db.accounts.map(\.id) {ledgerIndex=nil}
    }
  }
  private var mutationVersion: UInt64 = 0
  private var backgroundCommitInProgress = false
  private var writeBusyMessage: String { "Зберігається попередня зміна. Повтори дію після завершення." }
  private var assigningAppearanceOnly = false
  private var paymentRevision: UInt64 = 0
  private var cachedPaymentLookup: (revision: UInt64, value: FinamiPaymentLookup)?
  var paymentLookup: FinamiPaymentLookup {
    if let cachedPaymentLookup, cachedPaymentLookup.revision == paymentRevision { return cachedPaymentLookup.value }
    let value = FinamiPaymentLookup(operations: db.operations, records: db.paidRecords ?? [])
    cachedPaymentLookup = (paymentRevision, value)
    return value
  }
  private var ledgerIndex: FinamiLedgerIndex?
  private var dashboardMonthCache: [DateInterval: [Operation]] = [:]
  private var dashboardMetricsCache: [DateInterval: FinamiDashboardMetrics] = [:]
  func dashboardMetrics(_ date: Date) -> FinamiDashboardMetrics {
    guard let interval = Calendar.current.dateInterval(of: .month, for: date) else { return FinamiDashboardMetrics(operations: month(date)) }
    if let cached = dashboardMetricsCache[interval] { return cached }
    let metrics = FinamiDashboardMetrics(operations: month(date))
    if dashboardMetricsCache.count >= 4 { dashboardMetricsCache.removeAll(keepingCapacity: true) }
    dashboardMetricsCache[interval] = metrics
    return metrics
  }
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
  // Snapshot immutable inputs on MainActor, filter/sort elsewhere. Never return
  // results for an obsolete ledger or privacy setting.
  func searchOperationsInBackground(_ term: String, expectedVersion: UInt64, masked: Bool) async -> [Operation]? {
    guard expectedVersion == mutationVersion, masked == privateAmounts, !Task.isCancelled else { return nil }
    let rows = db.operations
    let accounts = db.accounts
    let query = FinamiHistoryQuery(kind: "all", account: "all", category: "all", search: term, sort: .newest, hideAmounts: masked)
    let work = Task.detached(priority: .userInitiated) {
      let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
      let hidden = Set(accounts.filter { $0.hideAmounts == true }.map(\.id))
      return query.apply(to: rows, names: names, maskedAccounts: hidden, isCancelled: { Task.isCancelled })
    }
    let result = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
    guard expectedVersion == mutationVersion, masked == privateAmounts, !Task.isCancelled else { return nil }
    return result
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
  var captureRefreshInProgress = false
  @Published private var ready = true
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
        try FinamiQAFixtures.reset(file: file, settingsFile: settingsFile)
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
        try FinamiQAFixtures.populate(&loaded, file: file)
        #endif
        try FinamiDatabaseSafety.validate(loaded)
        // Restore derived report labels using the same rules as JSON restore.
        guard finamiSynchronizeRefundLinks(&loaded.operations) else { throw FinamiDatabaseSafety.Failure.refundLink }
        let (migrated, migrationWarning) = FinamiScanStorage.migrateOnLoad(loaded, file: file)
        let warnings = [warning, migrationWarning].compactMap { $0 }.joined(separator: " · ")
        return (migrated, warnings.isEmpty ? nil : warnings)
      }.value
      db = result.0; error = result.1; ready = true
    } catch let loadError { self.error = "База не читається. Запис заблоковано, щоб не втратити дані. " + loadError.localizedDescription }
    loading = false
  }
  @discardableResult func change(forceSnapshot: Bool = false, _ update: (inout Database) -> Void) -> Bool {
    guard let (copy, newlyCaptured) = prepareChange(update) else { return false }
    let saved = write(copy, forceSnapshot: forceSnapshot)
    if saved && newlyCaptured > 0 { FinamiSavedNotification.post(count: newlyCaptured) }
    return saved
  }
  // Batch actions encode and persist immutable candidates off MainActor.
  // During disk replacement, a single-writer reservation rejects competing edits.
  @discardableResult func changeInBackground(_ update: (inout Database) -> Void) async -> Bool {
    let version = mutationVersion
    guard let (copy, newlyCaptured) = prepareChange(update) else { return false }
    var revised = copy; revised.appearanceRevision = UUID().uuidString
    let candidate = revised
    do {
      let data = try await Task.detached(priority: .userInitiated) { try JSONEncoder().encode(candidate) }.value
      guard ready, !Task.isCancelled, version == mutationVersion else { error = "Дані змінилися під час підготовки. Повтори дію."; return false }
      let saved = await commitInBackground(candidate, data: data, expectedVersion: version)
      if saved && newlyCaptured > 0 { FinamiSavedNotification.post(count: newlyCaptured) }
      return saved
    } catch { self.error = "Не вдалося підготувати запис: " + error.localizedDescription; return false }
  }
  private func prepareChange(_ update: (inout Database) -> Void) -> (Database, Int)? {
    guard !backgroundCommitInProgress else { error = writeBusyMessage; return nil }
    guard ready else {
      error = "Запис заблоковано. Віднови базу з копії."
      return nil
    }
    var copy = db
    update(&copy)
    do { try FinamiDatabaseSafety.validate(copy) } catch { self.error = error.localizedDescription; return nil }
    guard finamiLinkedOperationsPreserved(before: db, after: copy) else {
      error = "Операція пов’язана з оплаченим платежем. Зміна суми, рахунку, дати, типу або видалення заблоковані, щоб не порушити графік."
      return nil
    }
    guard paymentIntegrityPreserved(in: copy) else { error = "Новий зв’язок оплати не відповідає операції, рахунку або сумі. Перевір дані."; return nil }
    guard finamiSynchronizeRefundLinks(&copy.operations) else {error="Повернення пов’язано з покупкою. Спочатку перевір або відв’яжи повернення.";return nil}
    if !finamiGroupedTransfersPreserved(before:db.operations,after:copy.operations) {
      guard copy.reconciliationUndo == nil,let data=db.reconciliationUndo,let undo=try? JSONDecoder().decode(FinamiBalanceUndo.self,from:data),undo.restore(current:db.operations)==copy.operations else {error="Груповий переказ захищено. Спочатку скасуй звірку.";return nil}
    }
    if db.operations != copy.operations, db.reconciliationUndo == copy.reconciliationUndo {copy.reconciliationUndo=nil}
    // Keep attachment metadata, including undo and archived contracts, until a
    // snapshot-aware cleanup can prove the bytes are no longer needed.
    var newlyCaptured = 0
    if copy.capturePreferences?.notifySaved == true {
      let oldIDs = Set(db.operations.map(\.id))
      newlyCaptured = copy.operations.filter { $0.captureSource != nil && !oldIDs.contains($0.id) }.count
    }
    return (copy, newlyCaptured)
  }
  @discardableResult func changeAppearance(_ update: (inout AppearancePreferences) -> Void) -> Bool {
    guard !backgroundCommitInProgress else { error = writeBusyMessage; return false }
    guard ready else { error = "Запис заблоковано. Віднови базу з копії."; return false }
    var prefs = db.preferences ?? .init(); update(&prefs)
    guard let revision = db.appearanceRevision, FileManager.default.fileExists(atPath:url.path) else {
      var copy = db; copy.preferences = prefs; return write(copy)
    }
    do {
      let data = try JSONEncoder().encode(FinamiAppearanceSidecar(revision:revision,preferences:prefs))
      try data.write(to:appearanceURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
      assigningAppearanceOnly = true
      db.preferences = prefs
      assigningAppearanceOnly = false
      return true
    } catch { self.error = "Не вдалося зберегти налаштування: " + error.localizedDescription; return false }
  }
  // Heavy statement imports encode a snapshot off the UI thread. The live
  // version must be unchanged before committing, so no edit can be overwritten.
  var databaseVersion: UInt64 { mutationVersion }
  func replaceOperationsForImport(_ operations: [Operation], expectedVersion: UInt64, recordUndo:Bool = false) async -> Bool {
    guard !backgroundCommitInProgress else { error = writeBusyMessage; return false }
    guard expectedVersion == mutationVersion else { error = "Дані змінилися. Повтори перевірку виписки."; return false }
    guard ready else { error = "Запис заблоковано."; return false }
    let version = mutationVersion
    var copy = db; copy.operations = operations; copy.appearanceRevision = UUID().uuidString
    do { try FinamiDatabaseSafety.validate(copy) } catch { self.error = error.localizedDescription; return false }
    guard finamiLinkedOperationsPreserved(before: db, after: copy) else { error = "Імпорт змінює операцію, пов’язану з платежем. Перевір зіставлення."; return false }
    guard paymentIntegrityPreserved(in: copy) else { error = "Імпорт порушує зв’язок оплати з операцією."; return false }
    guard finamiSynchronizeRefundLinks(&copy.operations) else {error="Імпорт порушує зв’язок повернення з покупкою.";return false}
    guard finamiGroupedTransfersPreserved(before:db.operations,after:copy.operations) else {error="Імпорт змінює груповий переказ.";return false}
    if db.operations != copy.operations {
      copy.reconciliationUndo = recordUndo ? try? JSONEncoder().encode(FinamiBalanceUndo(before:db.operations,after:copy.operations)) : nil
    }
    let candidate = copy
    do {
      let data = try await Task.detached(priority:.userInitiated) { try JSONEncoder().encode(candidate) }.value
      guard version == mutationVersion, ready, !Task.isCancelled else { error = "Дані змінилися під час імпорту. Повтори перевірку виписки."; return false }
      return await commitInBackground(candidate, data: data, expectedVersion: version)
    } catch { self.error = "Не вдалося підготувати імпорт: " + error.localizedDescription; return false }
  }
  private func commitInBackground(_ candidate: Database, data: Data, expectedVersion: UInt64) async -> Bool {
    guard !backgroundCommitInProgress else { error = writeBusyMessage; return false }
    guard ready, expectedVersion == mutationVersion, !Task.isCancelled else {
      error = "Дані змінилися. Повтори дію."; return false
    }
    backgroundCommitInProgress = true
    defer { backgroundCommitInProgress = false }
    let previous = db
    let file = url, appearance = appearanceURL
    do {
      // Once disk replacement begins it must finish, even if the initiating view
      // is dismissed. Publishing the matching state is part of that transaction.
      try await Task.detached(priority: .userInitiated) {
        try FinamiLocalSnapshots.persist(before: previous, candidate: candidate, bytes: data,
                                         file: file, appearance: appearance, healthy: true, forceSnapshot: true)
      }.value
      db = candidate
      ready = true
      return true
    } catch { self.error = "Не вдалося зберегти: " + error.localizedDescription; return false }
  }
  private func paymentIntegrityPreserved(in copy: Database) -> Bool {
    finamiPaymentIntegrityPreserved(beforeOperations: db.operations, beforeAccounts: db.accounts, beforeRecords: db.paidRecords ?? [], afterOperations: copy.operations, afterAccounts: copy.accounts, afterRecords: copy.paidRecords ?? [])
  }
  private func write(_ copy: Database, forceSnapshot: Bool = false) -> Bool {
    do {
      var candidate = copy; candidate.appearanceRevision = UUID().uuidString
      return commit(candidate,data:try JSONEncoder().encode(candidate), forceSnapshot: forceSnapshot)
    } catch { self.error = "Не вдалося зберегти: " + error.localizedDescription; return false }
  }
  private func commit(_ copy: Database, data: Data, forceSnapshot: Bool = false) -> Bool {
    do {
      try FinamiLocalSnapshots.persist(before: db, candidate: copy, bytes: data, file: url,
                                      appearance: appearanceURL, healthy: ready, forceSnapshot: forceSnapshot)
      db = copy
      ready = true
      return true
    } catch { self.error = "Не вдалося зберегти: \(error.localizedDescription)"; return false }
  }
  func totals(_ operations: [Operation], _ kind: Kind) -> Int64 {
    if kind == .expense {return operations.reduce(0) { $0 + $1.expenseValue }}
    if kind == .income {return operations.reduce(0) { $0 + $1.incomeValue }}
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
  // Recovery never publishes unvalidated financial data or writes through normal editing paths.
  func recoveryOriginal() throws -> Data {
    guard !loading, !ready, !backgroundCommitInProgress else { throw CocoaError(.fileReadUnknown) }
    return try Data(contentsOf: url)
  }
  func validateRecovery(_ data: Data) throws {
    let candidate = try JSONDecoder().decode(Database.self, from: data)
    try FinamiDatabaseSafety.validate(candidate)
  }
  func applyRecovery(_ data: Data, expectedOriginal: Data) {
    do {
      guard try recoveryOriginal() == expectedOriginal else { throw CocoaError(.fileWriteUnknown) }
      try validateRecovery(data)
      // Preserve local attachment references and use the existing quarantining commit.
      restoreDatabase(data, localSnapshot: true, recovery: true)
    } catch { self.error = "Відновлення не виконано: " + error.localizedDescription }
  }
  func restore(_ data: Data) { restoreDatabase(data, localSnapshot: false) }
  func restoreSnapshot(_ snapshot: URL) {
    do {
      guard snapshotURLs().contains(snapshot) else { throw CocoaError(.fileReadNoSuchFile) }
      restoreDatabase(try Data(contentsOf: snapshot), localSnapshot: true)
    } catch { self.error = "Не вдалося відкрити локальну копію: " + error.localizedDescription }
  }
  private func restoreDatabase(_ data: Data, localSnapshot: Bool, recovery: Bool = false) {
    guard !backgroundCommitInProgress else { error = writeBusyMessage; return }
    guard !loading else { error = "Дочекайся завантаження бази."; return }
    do {
      var decoded = try JSONDecoder().decode(Database.self, from: data)
      try FinamiDatabaseSafety.validate(decoded)
      let accountCodes = Dictionary(uniqueKeysWithValues: decoded.accounts.map { ($0.id, $0.code) })
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
        decoded.obligations.allSatisfy({ o in (o.importedSchedule ?? []).allSatisfy { $0.amount >= 0 && $0.amount <= 1_000_000_000_000 } && (o.currentDuePaid.map { $0 >= 0 && $0 < o.monthly && $0 <= o.paid } ?? true) }),
        (decoded.balanceObservations ?? [:]).values.allSatisfy({ $0.available >= 0 && $0.available <= 1_000_000_000_000 && ["UAH","USD"].contains($0.currency) }),
        decoded.operations.allSatisfy({ o in
          o.amount > 0 && o.amount <= 1_000_000_000_000
            && finamiValidGroupedBankParts(o)
            && (o.sourceMinor.map { $0 > 0 && $0 <= 1_000_000_000_000 } ?? true)
            && (o.destinationMinor.map { $0 > 0 && $0 <= 1_000_000_000_000 } ?? true)
            && (accountCodes[o.account] != "USD" || (o.sourceMinor != nil && fxRate(o.exchangeRate ?? "") != nil))
            && (o.kind != .transfer || accountCodes[o.destination] != "USD" || o.destinationMinor != nil)
            && accountCodes[o.account] != nil
            && (o.kind != .transfer
              || (o.account != o.destination
                && accountCodes[o.destination] != nil))
        })
      else { throw CocoaError(.fileReadCorruptFile) }
      guard finamiSynchronizeRefundLinks(&decoded.operations) else {error="Копія містить некоректні зв’язки повернень.";return}
      if localSnapshot {
        // Verify all referenced bytes before replacing the ledger.
        _ = try FinamiScanStorage.portable(decoded, file: url)
      } else if !(decoded.scanFileHashes ?? [:]).isEmpty {
        error = "Це локальна копія з окремими файлами. Для перенесення використай повний JSON або зашифровану копію."
        return
      }
      if recovery, decoded.appearanceRevision != nil, FileManager.default.fileExists(atPath: appearanceURL.path) {
        decoded.preferences = try FinamiAppearanceSidecar<AppearancePreferences>.resolve(base: decoded.preferences, revision: decoded.appearanceRevision, data: Data(contentsOf: appearanceURL))
      }
      decoded = FinamiScanStorage.externalized(decoded, file: url)
      if write(decoded, forceSnapshot: true) { error = nil }
    } catch { self.error = "Не вдалося відновити JSON: \(error.localizedDescription)" }
  }
  func importLegacy(_ data: Data) {
    do {
      let old = try JSONDecoder().decode(Legacy.self, from: data)
      var incoming: [Operation] = []
      for (kind, rows) in [(Kind.expense, old.items), (.income, old.incomes)] {
        for row in rows {
          guard let minor = finamiLegacyMinor(row.amt), row.ts.isFinite, abs(row.ts) < 1e14
          else { throw CocoaError(.fileReadCorruptFile) }
          incoming.append(
            Operation(
              kind: kind, amount: minor,
              date: Date(timeIntervalSince1970: row.ts / 1000), category: row.cat ?? "Інше",
              note: row.note ?? "", account: db.accounts.first(where:{$0.code=="UAH"})?.id ?? cash))
        }
      }
      var count = 0
      if change(forceSnapshot: true, { d in
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
        if d.budget == 0, let b = old.budget, let minor = finamiLegacyMinor(b) {
          d.budget = minor
        }
      }) {
        error =
          "Імпортовано операцій: \(count). Дублікати пропущено. Борги, цілі та розстрочки перенеси вручну."
      }
    } catch { self.error = "Не вдалося прочитати стару базу: \(error.localizedDescription)" }
  }
  func snapshotURLs() -> [URL] { FinamiLocalSnapshots.urls(for: url) }
  var storageHealthy: Bool { ready }
  func backupData() throws -> Data {
    guard ready, !loading else { throw CocoaError(.fileReadCorruptFile) }
    return try JSONEncoder().encode(FinamiScanStorage.portable(db, file: url))
  }
  func backup() throws -> DataFile { DataFile(data: try backupData()) }
  func stageScanImage(_ data: Data) throws -> String {
    guard ready, !loading else { throw CocoaError(.fileWriteUnknown) }
    return try FinamiScanStorage.files(for: url).stage(data)
  }
  func scanImageData(_ id: String) -> Data? {
    if let inline = db.scanImages?[id] { return inline }
    guard let hash = db.scanFileHashes?[id] else { return nil }
    return try? FinamiScanStorage.files(for: url).read(hash)
  }

  func csv() -> DataFile {
    func q(_ s: String) -> String { finamiCSVText(s) }
    let f = ISO8601DateFormatter()
    let rows = db.operations.map { o in
      [
        f.string(from: o.date), o.displayKindTitle, amountText(o.amount), q(o.category),
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
