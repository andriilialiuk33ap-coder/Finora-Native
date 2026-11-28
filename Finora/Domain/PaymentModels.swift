import Foundation

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
// Read-only bank facts captured when the contract was reviewed. These fields
// never alter the ledger, outstanding principal or payment schedule on their own.
struct FinamiBankContractSnapshot: Codable, Equatable {
  var capturedAt: Date
  var firstContribution: Int64?
  var totalBankFee: Int64?
  var monthlyBankFee: Int64?
  var paymentCount: Int?
  var paidCount: Int?
  var nextAmount: Int64?
  var bankNextDue: Date?
  var opened: Date?
  var finalDue: Date?
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
  var confirmedSchedule: [FinamiScheduleRow]? = nil
  var currentDuePaid: Int64? = nil
  var bankContractSnapshot: FinamiBankContractSnapshot? = nil
  var remaining: Int64 { max(0, target - paid) }
  var nextCharge: Int64 {
    if let rows = confirmedSchedule { return rows.first?.amount ?? 0 }
    return monthly > 0 ? min(max(0, monthly - max(0, currentDuePaid ?? 0)), remaining) : remaining
  }
  // nil = legacy projection; empty = confirmed schedule fully settled.
  var confirmedScheduleValid: Bool {
    guard let rows = confirmedSchedule else { return true }
    guard kind == .installment, target >= 0, target <= 1_000_000_000_000,
          paid >= 0, paid <= target, currentDuePaid == nil, rows.count <= 600 else { return false }
    if rows.isEmpty { return remaining == 0 }
    guard rows.first?.date == due else { return false }
    var left = remaining
    var previous: Date?
    for row in rows {
      guard row.date.timeIntervalSinceReferenceDate.isFinite, row.amount > 0, row.amount <= left,
            previous.map({ $0 < row.date }) ?? true else { return false }
      left -= row.amount; previous = row.date
    }
    return left == 0
  }
  // The user selects the first unpaid date; earlier rows are not inferred to be paid.
  static func outstandingSchedule(from rows: [FinamiScheduleRow], remaining: Int64, firstDue: Date, calendar: Calendar = .current) -> [FinamiScheduleRow]? {
    guard remaining > 0, remaining <= 1_000_000_000_000, rows.count <= 600,
          firstDue.timeIntervalSinceReferenceDate.isFinite,
          rows.allSatisfy({ $0.amount >= 0 && $0.amount <= 1_000_000_000_000 && $0.date.timeIntervalSinceReferenceDate.isFinite }) else { return nil }
    let firstDay = calendar.startOfDay(for: firstDue)
    var result = rows.filter { $0.amount > 0 && calendar.startOfDay(for: $0.date) >= firstDay }.sorted { $0.date < $1.date }
    guard let first = result.first, calendar.isDate(first.date, inSameDayAs: firstDue),
          Set(result.map { calendar.startOfDay(for: $0.date) }).count == result.count else { return nil }
    var left = remaining
    for row in result { guard row.amount <= left else { return nil }; left -= row.amount }
    guard left == 0 else { return nil }
    result[0].date = firstDue
    return result
  }
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
  var beforeSchedule: [FinamiScheduleRow]? = nil
  var afterSchedule: [FinamiScheduleRow]? = nil
}
