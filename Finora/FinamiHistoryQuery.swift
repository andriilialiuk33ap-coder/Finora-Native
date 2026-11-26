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
    func apply(to operations: [Operation], names: [String: String], maskedAccounts: Set<String> = []) -> [Operation] {
        operations.filter { o in
            if reviewOnly && !o.kind.needsReview { return false }
            if let sourceBank, o.sourceBank != sourceBank { return false }
            if let from, o.date < from { return false }
            if let until, o.date >= until { return false }
            let masked = hideAmounts || maskedAccounts.contains(o.account) || (o.kind == .transfer && maskedAccounts.contains(o.destination))
            if !hideAmounts && (minimum != nil || maximum != nil) {
                if masked { return false }
                if let minimum, o.amount < minimum { return false }
                if let maximum, o.amount > maximum { return false }
            }
            if kind != "all" && o.kind.rawValue != kind { return false }
            if account != "all" && o.account != account && !(o.kind == .transfer && o.destination == account) { return false }
            if category != "all" && o.category != category { return false }
            if search.isEmpty { return true }
            let amount = masked ? "" : String(format:"%.2f",Double(o.amount)/100)
            let content = [o.note,o.category,amount,names[o.account] ?? "Рахунок",(o.tags ?? []).joined(separator:" ")].joined(separator:" ")
            return content.localizedCaseInsensitiveContains(search)
        }.sorted { sort.orders($0,$1) }
    }
}
