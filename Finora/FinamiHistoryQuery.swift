import Foundation

struct FinamiHistoryQuery: Hashable {
    let kind: String
    let account: String
    let category: String
    let search: String
    let sort: OperationSort
    let hideAmounts: Bool
    func apply(to operations: [Operation], names: [String: String]) -> [Operation] {
        operations.filter { o in
            (kind == "all" || o.kind.rawValue == kind) &&
            (account == "all" || o.account == account || (o.kind == .transfer && o.destination == account)) &&
            (category == "all" || o.category == category) &&
            (search.isEmpty || (o.note + " " + o.category + " " + (hideAmounts ? "" : String(format:"%.2f",Double(o.amount)/100)) + " " + (names[o.account] ?? "Рахунок")).localizedCaseInsensitiveContains(search))
        }.sorted { sort.orders($0,$1) }
    }
}
