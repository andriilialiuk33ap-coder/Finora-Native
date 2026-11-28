import Foundation

/// One transaction for category identity, references, and optional group changes.
/// Names remain the persisted identifiers in this version; no migration is required.
enum FinamiCategoryCore {
    /// A type switch must never carry an incompatible category into a new report.
    static func categoryAfterTypeChange(_ category: String, from: Kind, to: Kind, database: Database, note: String) -> String {
        if to == .receipt {
            let allowed = database.availableReceiptCategories
            if from == .receipt, allowed.contains(category) { return category }
            return finamiIntelligentCategory(note, kind: to, allowed: allowed, learned: database.merchantRules ?? [:])
        }
        guard to.isReportCategory else { return "Без категорії" }
        let income = to == .income
        let available = (income ? database.incomeCategories : database.expenseCategories).filter {
            !(income ? database.hiddenIncomeCategories ?? [] : database.hiddenExpenseCategories ?? []).contains($0)
        }
        if from.isReportCategory, from != .receipt, (from == .income) == income, available.contains(category) { return category }
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
                let other = (income ? db.expenseCategories : db.incomeCategories) + db.availableReceiptCategories
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

extension FinamiCategoryCore {
    static func editReceipt(_ db: inout Database, old: String?, new: String, merge: Bool = false) -> Bool {
        let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = db.availableReceiptCategories
        guard !name.isEmpty, old.map({ list.contains($0) && $0 != "Без категорії" }) ?? !merge,
              merge ? (old != name && list.contains(name)) : (!list.contains(name) || old == name) else { return false }
        if let old, old != name {
            if merge { list.removeAll { $0 == old } }
            else { list = list.map { $0 == old ? name : $0 } }
            for i in db.operations.indices where db.operations[i].kind == .receipt && db.operations[i].category == old { db.operations[i].category = name }
            if var rules = db.merchantRules {
                for key in Array(rules.keys) where key.hasPrefix("receipt:") && rules[key] == old { rules[key] = name }
                db.merchantRules = rules
            }
            if var preferences = db.preferences, let favorites = preferences.designEditorFavorites, favorites.contains(old) {
                let shared = db.incomeCategories.contains(old) || db.expenseCategories.contains(old)
                preferences.designEditorFavorites = Array(Set((shared ? favorites : favorites.filter { $0 != old }) + [name])).sorted()
                db.preferences = preferences
            }
        } else if old == nil { list.append(name) }
        db.receiptCategories = list
        return true
    }

    static func allowed(_ kind: Kind, in db: Database) -> [String] {
        switch kind {
        case .expense: return db.expenseCategories.filter { !(db.hiddenExpenseCategories ?? []).contains($0) }
        case .income: return db.incomeCategories.filter { !(db.hiddenIncomeCategories ?? []).contains($0) }
        case .receipt, .unclassifiedCredit: return db.availableReceiptCategories
        default: return []
        }
    }
}

/// Undo is limited to the affected records and refuses if any were subsequently edited.
/// It cannot roll back unrelated writes, bank keys, balances, or newly imported rows.
struct FinamiCategoryBatch {
    let before: [Operation]
    let after: [Operation]

    static func plan(in db: Database, ids: Set<String>, kind: Kind, category: String, treatment: FinamiReceiptTreatment = .pending) -> Self? {
        guard treatment != .reimbursement, !ids.isEmpty, [.expense, .income, .receipt, .unclassifiedCredit].contains(kind),
              FinamiCategoryCore.allowed(kind, in: db).contains(category) else { return nil }
        let selected = db.operations.filter { ids.contains($0.id) }
        let protected = Set((db.paidRecords ?? []).compactMap(\.operationID) + db.operations.compactMap(\.refundOriginalID))
        guard selected.count == ids.count, selected.allSatisfy({ $0.kind == kind && !protected.contains($0.id) && $0.groupedBankParts == nil && $0.destinationBankKey == nil && $0.refundOriginalID == nil }) else { return nil }
        let changed = selected.map { old -> Operation in
            var next = old
            if kind == .unclassifiedCredit { next.kind = .receipt; next.classificationReviewed = true }
            next.category = category
            if next.kind == .receipt { next.receiptTreatment = treatment }
            return next
        }
        guard changed != selected else { return nil }
        return Self(before: selected, after: changed)
    }

    func applying(to operations: [Operation], undo: Bool = false) -> [Operation]? {
        let expected = undo ? after : before
        let replacement = undo ? before : after
        let ids = Set(expected.map(\.id))
        guard operations.filter({ ids.contains($0.id) }) == expected else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: replacement.map { ($0.id, $0) })
        return operations.map { byID[$0.id] ?? $0 }
    }
}
