import Foundation

let cash = "cash"

enum Kind: String, Codable, CaseIterable, Identifiable {
  case expense, income, transfer, creditDraw, creditRepayment, creditRepaymentIncoming, movementIn, movementOut, refund, unclassifiedCredit, unclassifiedDebit, receipt
  var id: String { rawValue }
  var incoming: Bool { [.income,.creditDraw,.creditRepaymentIncoming,.movementIn,.refund,.unclassifiedCredit,.receipt].contains(self) }
  var needsReview: Bool { self == .unclassifiedCredit || self == .unclassifiedDebit }
  var isReportCategory: Bool { self == .income || self == .expense || self == .refund || self == .receipt }
  var title: String {
    switch self {
    case .expense: return "Витрата"
    case .income: return "Дохід"
    case .receipt: return "Зарахування коштів"
    case .transfer: return "Переказ коштів"
    case .creditDraw: return "Отримання кредиту"
    case .creditRepayment: return "Погашення кредиту"
    case .creditRepaymentIncoming: return "Поповнення кредитної картки"
    case .movementIn: return "Переказ коштів (вхідний)"
    case .movementOut: return "Переказ коштів (вихідний)"
    case .refund: return "Повернення покупки"
    case .unclassifiedCredit: return "Зарахування: уточнити"
    case .unclassifiedDebit: return "Списання: уточнити"
    }
  }
}
// Editor choices are deliberately separate from persisted ledger classifications.
enum FinamiOperationChoice: String, CaseIterable, Identifiable {
  case expense, income, transfer, withdrawal, repayment, refund, reviewCredit, reviewDebit, legacy, receipt
  var id: String { rawValue }
  var title: String {
    switch self {
    case .expense: return "Витрата"
    case .income: return "Дохід"
    case .receipt: return "Зарахування коштів"
    case .transfer: return "Переказ коштів"
    case .withdrawal: return "Зняття готівки"
    case .repayment: return "Погашення кредиту"
    case .refund: return "Повернення покупки"
    case .reviewCredit: return "Зарахування: уточнити"
    case .reviewDebit: return "Списання: уточнити"
    case .legacy: return "Збережений банківський тип"
    }
  }
  static func current(_ kind: Kind, withdrawal: Bool) -> Self {
    switch kind {
    case .expense: return .expense
    case .income: return .income
    case .receipt: return .receipt
    case .transfer, .movementOut: return withdrawal ? .withdrawal : .transfer
    case .movementIn: return .transfer
    case .creditRepayment: return .repayment
    case .refund: return .refund
    case .unclassifiedCredit: return .reviewCredit
    case .unclassifiedDebit: return .reviewDebit
    case .creditDraw, .creditRepaymentIncoming: return .legacy
    }
  }
  static func options(bankIncoming: Bool?, current: Self) -> [Self] {
    var values: [Self]
    switch bankIncoming {
    case true?: values = [.income, .receipt, .transfer, .refund, .reviewCredit]
    case false?: values = [.expense, .transfer, .withdrawal, .repayment, .reviewDebit]
    case nil: values = [.expense, .income, .receipt, .transfer, .withdrawal, .repayment, .refund, .reviewCredit, .reviewDebit]
    }
    if !values.contains(current) { values.append(current) }
    return values
  }
  func ledgerKind(bankIncoming: Bool?, existing: Kind) -> Kind {
    switch self {
    case .expense: return .expense
    case .income: return .income
    case .receipt: return .receipt
    case .transfer:
      if [.transfer, .movementIn, .movementOut].contains(existing) { return existing }
      return bankIncoming.map { $0 ? .movementIn : .movementOut } ?? .transfer
    case .withdrawal: return bankIncoming == nil ? .transfer : .movementOut
    case .repayment: return .creditRepayment
    case .refund: return .refund
    case .reviewCredit: return .unclassifiedCredit
    case .reviewDebit: return .unclassifiedDebit
    case .legacy: return existing
    }
  }
}
// A receipt is a confirmed external inflow, not an own-account transfer.
// Missing treatment is intentionally undecided and never counted as income.
enum FinamiReceiptTreatment: String, Codable, CaseIterable, Identifiable {
  case pending, income, neutral, reimbursement
  var id: String { rawValue }
  var title: String {
    switch self {
    case .pending: return "Визначити пізніше"
    case .income: return "Врахувати в доходах"
    case .neutral: return "Не враховувати в доходах"
    case .reimbursement: return "Компенсувати попередню витрату"
    }
  }
  static let unlinkedChoices: [Self] = [.pending, .income, .neutral]
  static let categories = ["👤 Переказ від іншої людини", "🎁 Подарунок", "👪 Допомога", "🤝 Повернення боргу", "🍽️ Компенсація витрат", "💵 Отримані позикові кошти", "Інші зарахування", "Без категорії"]
  static func suggestion(_ category: String) -> Self {
    switch category {
    case "🎁 Подарунок", "👪 Допомога": return .income
    case "🤝 Повернення боргу": return .neutral
    default: return .pending
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
  // Optional for backward-compatible decoding; the underlying transfer accounting stays unchanged.
  var cashWithdrawal: Bool? = nil
  var receiptTreatment: FinamiReceiptTreatment? = nil
  var receiptExpenseCategory: String? = nil
  var isReimbursement: Bool { kind == .receipt && receiptTreatment == .reimbursement && refundOriginalID != nil && receiptExpenseCategory != nil }
  var countsAsIncome: Bool { kind == .income || (kind == .receipt && receiptTreatment == .income) }
  var incomeValue: Int64 { countsAsIncome ? amount : 0 }
  var requiresReview: Bool { kind.needsReview || (kind == .receipt && (receiptTreatment == nil || receiptTreatment == .pending || (receiptTreatment == .reimbursement && !isReimbursement) || category == "Без категорії")) }
  var needsCaptureAttention: Bool { requiresReview || (captureSource != nil && (kind == .expense || kind == .income) && category == "Без категорії") }
  var displayKindTitle: String { cashWithdrawal == true && (kind == .transfer || kind == .movementOut) ? "Зняття готівки" : kind.title }
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
  var expenseValue: Int64 { kind == .expense ? amount : kind == .refund || isReimbursement ? -amount : neutralFee }
  var expenseGroup: String { if isReimbursement { return receiptExpenseCategory ?? "Без категорії" }; return kind == .expense || kind == .refund ? category : "🏦 Комісії" }
}

// Shared ledger invariants, used by validation on load, save and restore.
func finamiValidGroupedBankParts(_ o:Operation)->Bool {
    guard let parts=o.groupedBankParts else{return true}
    guard o.kind == .transfer, o.account != o.destination, o.destinationBankKey == nil, !parts.isEmpty,Set(parts.map(\.key)).count==parts.count,parts.allSatisfy({!$0.key.isEmpty && $0.key != o.bankKey && $0.date.timeIntervalSinceReferenceDate.isFinite && $0.amount>0 && $0.amount<=1_000_000_000_000}) else{return false}
    var sum:Int64=0
    for p in parts {let (value,overflow)=sum.addingReportingOverflow(p.amount);guard !overflow,value<=1_000_000_000_000 else{return false};sum=value}
    return sum==(o.destinationMinor ?? o.amount)
}

// A compensation is a distinct incoming operation, not a new debit or bank refund.
func finamiCanCompensate(_ receipt: Operation, _ original: Operation) -> Bool {
    receipt.kind == .receipt && original.kind == .expense && receipt.id != original.id && original.date <= receipt.date &&
    (receipt.entryCurrency ?? receipt.originalCurrency ?? "UAH") == "UAH" && (original.entryCurrency ?? original.originalCurrency ?? "UAH") == "UAH" &&
    receipt.amount > 0 && receipt.signedNative == receipt.amount && original.amount > 0 && original.signedNative == -original.amount && receipt.amount <= original.amount
}
func finamiSynchronizeRefundLinks(_ operations:inout [Operation], accountCodes: [String:String]? = nil, validateOnly: Bool = false)->Bool {
    // Validate the whole candidate before propagating derived category names.
    guard !operations.contains(where: { $0.kind == .receipt && $0.receiptTreatment == .reimbursement && $0.refundOriginalID == nil }) else { return false }
    let linked=operations.indices.filter{operations[$0].refundOriginalID != nil}
    if linked.isEmpty { return true }
    let lookup=Dictionary(operations.map{($0.id,$0)},uniquingKeysWith:{a,_ in a});var sums:[String:Int64]=[:]
    for i in linked {
        let o=operations[i]
        guard let id=o.refundOriginalID,let original=lookup[id],original.kind == .expense,original.date<=o.date,o.signedNative>0 else{return false}
        if o.kind == .receipt {
            guard o.receiptTreatment == .reimbursement, finamiCanCompensate(o, original),
                  accountCodes.map({ $0[o.account] == "UAH" && $0[original.account] == "UAH" }) ?? true else { return false }
        } else {
            guard o.kind == .refund, original.account == o.account else { return false }
        }
        let (sum,overflow)=(sums[id] ?? 0).addingReportingOverflow(o.signedNative)
        guard !overflow,sum <= -original.signedNative else{return false}
        sums[id]=sum
    }
    if validateOnly { return true }
    for i in linked {
        if let id=operations[i].refundOriginalID,let original=lookup[id] {
            if operations[i].kind == .receipt { operations[i].receiptExpenseCategory = original.category }
            else { operations[i].category=original.category }
        }
    }
    return true
}

