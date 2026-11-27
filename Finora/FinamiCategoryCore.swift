import Foundation

/// One transaction for category identity, references, and optional group changes.
/// Names remain the persisted identifiers in this version; no migration is required.
enum FinamiCategoryCore {
    /// A type switch must never carry an incompatible category into a new report.
    static func categoryAfterTypeChange(_ category: String, from: Kind, to: Kind, database: Database, note: String) -> String {
        guard to.isReportCategory else { return "Без категорії" }
        let income = to == .income
        let available = (income ? database.incomeCategories : database.expenseCategories).filter {
            !(income ? database.hiddenIncomeCategories ?? [] : database.hiddenExpenseCategories ?? []).contains($0)
        }
        if from.isReportCategory, (from == .income) == income, available.contains(category) { return category }
        guard to != .refund else { return "Без категорії" }
        return finamiIntelligentCategory(note, kind: to, allowed: available, learned: database.merchantRules ?? [:])
    }

    static func edit(_ db: inout Database, income: Bool, old: String?, new: String, parent: String? = nil, merge: Bool = false) -> Bool {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = income ? db.incomeCategories : db.expenseCategories
        guard !name.isEmpty, old.map({ list.contains($0) && !["Інше", "Без категорії"].contains($0) }) ?? !merge,
              merge ? (old != name && list.contains(name)) : (!list.contains(name) || old == name) else { return false }
        // Preflight the only arithmetic before mutating any data.
        var mergedLimit: Int64?
        if !income, let old, old != name, let limit = db.limits[old] {
            let (sum, overflow) = (db.limits[name] ?? 0).addingReportingOverflow(limit)
            guard !overflow else { return false }
            mergedLimit = sum
        }
        var next = list
        if let old, old != name {
            if merge { next.removeAll { $0 == old } }
            else { next = next.map { $0 == old ? name : $0 } }
        } else if old == nil { next.append(name) }
        if income { db.incomeCategories = next } else { db.expenseCategories = next }
        if let old, old != name {
            func remap(_ values: [String]) -> [String] {
                var seen = Set<String>()
                return values.map { $0 == old ? name : $0 }.filter { seen.insert($0).inserted }
            }
            if income {
                if let hidden = db.hiddenIncomeCategories { db.hiddenIncomeCategories = merge ? hidden.filter { $0 != old } : remap(hidden) }
            } else {
                if let hidden = db.hiddenExpenseCategories { db.hiddenExpenseCategories = merge ? hidden.filter { $0 != old } : remap(hidden) }
                if let mergedLimit { db.limits.removeValue(forKey: old); db.limits[name] = mergedLimit }
                if var parents = db.categoryParents {
                    let previous = parents.removeValue(forKey: old)
                    for key in Array(parents.keys) where parents[key] == old { parents[key] = key == name ? nil : name }
                    if !merge, let previous, previous != name && previous != old { parents[name] = previous }
                    db.categoryParents = parents
                }
                if var items = db.dashboard {
                    for i in items.indices { if let selected = items[i].categorySelection { items[i].categorySelection = remap(selected) } }
                    db.dashboard = items
                }
            }
            for i in db.operations.indices where db.operations[i].category == old && (income ? db.operations[i].kind == .income : [.expense, .refund].contains(db.operations[i].kind)) { db.operations[i].category = name }
            if var rules = db.merchantRules {
                let prefix = income ? "income:" : "expense:"
                for key in Array(rules.keys) where key.hasPrefix(prefix) && rules[key] == old { rules[key] = name }
                db.merchantRules = rules
            }
            if var preferences = db.preferences, let favorites = preferences.designEditorFavorites, favorites.contains(old) {
                // Favorites are currently shared between both category groups.
                let other = income ? db.expenseCategories : db.incomeCategories
                preferences.designEditorFavorites = other.contains(old) ? Array(Set(favorites + [name])).sorted() : remap(favorites)
                db.preferences = preferences
            }
        }
        if !income, !merge, let parent {
            let group = parent.trimmingCharacters(in: .whitespacesAndNewlines)
            var groups = db.categoryParents ?? [:]
            groups[name] = group.isEmpty || group == name ? nil : group
            db.categoryParents = groups
        }
        return true
    }
}
