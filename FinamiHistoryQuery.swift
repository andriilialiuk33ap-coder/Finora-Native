import Foundation

struct FinamiHistoryQuery: Hashable {
    let kind: String
    let account: String
    let category: String
    let search: String
    let sort: OperationSort
    let hideAmounts: Bool
    var from: Date? = nil
    var until: Date? = nil
    var minimum: Int64? = nil
    var maximum: Int64? = nil
    var reviewOnly: Bool = false
    var sourceBank: String? = nil
    func apply(to operations: [Operation], names: [String: String], maskedAccounts: Set<String> = [], isCancelled: () -> Bool = { false }) -> [Operation] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match both Ukrainian decimal notation and the existing dot notation.
        let normalizedAmountTerm = term.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        let isAmountTerm = !normalizedAmountTerm.isEmpty && normalizedAmountTerm.utf8.allSatisfy { (48...57).contains($0) || $0 == 46 }
        let containsDigit = term.utf8.contains { (48...57).contains($0) }
        let filtered = operations.filter { o in
            if isCancelled() { return false }
            if reviewOnly && !o.requiresReview { return false }
            if let sourceBank, o.sourceBank != sourceBank { return false }
            if let from, o.date < from { return false }
            if let until, o.date >= until { return false }
            let masked = hideAmounts || maskedAccounts.contains(o.account) || (o.kind == .transfer && maskedAccounts.contains(o.destination))
            if !hideAmounts && (minimum != nil || maximum != nil) {
                if masked { return false }
                if let minimum, o.amount < minimum { return false }
                if let maximum, o.amount > maximum { return false }
            }
            if kind == "cashWithdrawal" {
                if o.cashWithdrawal != true || ![Kind.transfer, .movementOut].contains(o.kind) { return false }
            } else if kind != "all" && o.kind.rawValue != kind { return false }
            if account != "all" && o.account != account && !(o.kind == .transfer && o.destination == account) { return false }
            if category != "all" && o.category != category { return false }
            if term.isEmpty { return true }
            let destination = o.kind == .transfer ? (names[o.destination] ?? "") : ""
            let content = [o.note,o.category,names[o.account] ?? "Рахунок",destination,(o.tags ?? []).joined(separator:" ")].joined(separator:" ")
            if content.localizedCaseInsensitiveContains(term) { return true }
            guard !masked, isAmountTerm || containsDigit else { return false }
            let amount = finamiMinorText(o.amount)
            if isAmountTerm && amount.contains(normalizedAmountTerm) { return true }
            // Keep the original combined-text matching for older search habits.
            let legacy = [o.note, o.category, amount, names[o.account] ?? "Рахунок", (o.tags ?? []).joined(separator: " ")].joined(separator: " ")
            return legacy.localizedCaseInsensitiveContains(term)
        }
        guard !isCancelled() else { return [] }
        return filtered.sorted { sort.orders($0,$1) }
    }
}
