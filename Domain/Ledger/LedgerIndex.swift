import Foundation

// Derived, in-memory ledger index. Never persisted or used as a source of truth.
struct FinamiLedgerIndex {
  private var deltas: [String: Int64] = [:]
  private var histories: [String: [Operation]] = [:]
  private var anchors: [String: Date] = [:]
  private var anchoredDeltas: [String: Int64] = [:]
  init(operations: [Operation], accounts:[Account] = []) {
    for a in accounts { if let date=a.reconciliationDate,a.reconciliationNet != nil {anchors[a.id]=date} }
    for o in operations {
      record(o, account: o.account)
      if o.kind == .transfer, o.destination != o.account {
        record(o, account: o.destination)
      }
    }
  }
  // Current and historical positions use exactly the same native movement rules.
  private mutating func record(_ o: Operation, account: String) {
    histories[account, default: []].append(o)
    deltas[account, default: 0] += Self.movement(o, account: account, after: nil, until: nil)
    if let anchor = anchors[account] {
      anchoredDeltas[account, default: 0] += Self.movement(o, account: account, after: anchor, until: nil)
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
    income = period.filter { $0.account == account.id && $0.countsAsIncome }.reduce(0) { $0 + ($1.sourceMinor ?? $1.amount) }
    spending = period.filter { $0.account == account.id }.reduce(0) { total, o in
      if o.kind == .expense { return total + (o.sourceMinor ?? o.amount) }
      if o.kind == .refund || o.isReimbursement { return total - (o.sourceMinor ?? o.amount) }
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
