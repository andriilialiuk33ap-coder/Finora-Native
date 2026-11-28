import SwiftUI

struct FinamiReceiptCategoriesView: View {
    @EnvironmentObject private var s: Store
    @State private var name = ""
    @State private var editing: String?
    @State private var merging: String?
    var body: some View {
        List {
            Section("Зарахування коштів") {
                ForEach(s.db.availableReceiptCategories, id: \.self) { category in
                    Text(category).swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if category != "Без категорії" {
                            Button("Перенести", role: .destructive) { merging = category }
                            Button("Назва") { editing = category; name = category }.tint(.blue)
                        }
                    }
                }
            }
            Section(editing == nil ? "Нова категорія" : "Редагувати категорію") {
                TextField("Назва", text: $name)
                Button("Зберегти") { save(old: editing, new: name, merge: false) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editing != nil { Button("Скасувати") { editing = nil; name = "" } }
            }
            Text("Перейменування переносить категорію у транзакціях та правилах навчання. Спосіб обліку наявних зарахувань не змінюється.").font(.caption)
        }.navigationTitle("Категорії зарахувань")
            .confirmationDialog("Перенести всі операції та правила", isPresented: Binding(get: { merging != nil }, set: { if !$0 { merging = nil } }), titleVisibility: .visible) {
                ForEach(s.db.availableReceiptCategories.filter { $0 != merging }, id: \.self) { category in
                    Button(category) { if let old = merging { save(old: old, new: category, merge: true) }; merging = nil }
                }
                Button("Скасувати", role: .cancel) { merging = nil }
            }
    }
    private func save(old: String?, new: String, merge: Bool) {
        var candidate = s.db
        guard FinamiCategoryCore.editReceipt(&candidate, old: old, new: new, merge: merge) else { s.error = "Перевір назву категорії."; return }
        if s.change({ $0 = candidate }) { editing = nil; name = "" }
    }
}

struct FinamiBatchCategoriesView: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .expense
    @State private var selected: Set<String> = []
    @State private var category = ""
    @State private var treatment: FinamiReceiptTreatment = .pending
    @State private var filter = ""
    @State private var limit = 100
    @State private var undo: FinamiCategoryBatch?
    @State private var confirm = false
    @State private var saving = false
    private var rows: [Operation] {
        let protected = Set((s.db.paidRecords ?? []).compactMap(\.operationID) + s.db.operations.compactMap(\.refundOriginalID))
        return s.db.operations.filter { o in
            o.kind == kind && !protected.contains(o.id) && o.groupedBankParts == nil && o.destinationBankKey == nil && o.refundOriginalID == nil &&
            (filter.isEmpty || o.note.localizedCaseInsensitiveContains(filter) || o.category.localizedCaseInsensitiveContains(filter))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Змінити категорію") {
                    Picker("Тип", selection: $kind) {
                        ForEach([Kind.expense, .income, .receipt, .unclassifiedCredit]) { Text($0.title).tag($0) }
                    }
                    Picker("Категорія", selection: $category) {
                        Text("Обрати").tag("")
                        ForEach(FinamiCategoryCore.allowed(kind, in: s.db), id: \.self) { Text($0).tag($0) }
                    }
                    if kind == .receipt || kind == .unclassifiedCredit {
                        Picker("У звітах", selection: $treatment) { ForEach(FinamiReceiptTreatment.unlinkedChoices) { Text($0.title).tag($0) } }
                    }
                    if kind == .unclassifiedCredit { Text("Вибрані надходження стануть зарахуваннями від інших людей. Не обирай власні перекази або повернення покупок.").font(.caption) }
                    Text("Вибрано: \(selected.count). Суми, дати й рахунки не змінюються. Пов’язані платежі та повернення захищено.").font(.caption)
                    Button("Застосувати") { confirm = true }.disabled(saving || selected.isEmpty || category.isEmpty)
                    if saving { ProgressView("Збереження…") }
                    if undo != nil { Button("Скасувати останню групову зміну") { Task { await restore() } }.disabled(saving) }
                }
                Section("Операції") {
                    TextField("Пошук за описом або категорією", text: $filter)
                    ForEach(Array(rows.prefix(limit))) { o in
                        Button { if selected.contains(o.id) { selected.remove(o.id) } else { selected.insert(o.id) } } label: {
                            HStack { Image(systemName: selected.contains(o.id) ? "checkmark.circle.fill" : "circle"); OperationRow(o: o) }
                        }.buttonStyle(.plain)
                    }
                    if rows.count > limit { Button("Показати ще") { limit += 100 } }
                }
            }.disabled(saving).interactiveDismissDisabled(saving).navigationTitle("Масове уточнення")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() }.disabled(saving) } }
                .onChange(of: kind) { _ in selected.removeAll(); category = ""; treatment = .pending; limit = 100 }
                .onChange(of: category) { value in treatment = FinamiReceiptTreatment.suggestion(value) }
                .onChange(of: filter) { _ in limit = 100 }
                .confirmationDialog("Змінити вибрані операції?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Застосувати до \(selected.count) операцій") { Task { await apply() } }
                    Button("Скасувати", role: .cancel) {}
                }
        }
    }
    @MainActor private func apply() async {
        guard !saving else { return }; saving = true; defer { saving = false }
        guard let plan = FinamiCategoryBatch.plan(in: s.db, ids: selected, kind: kind, category: category, treatment: treatment),
              let rows = plan.applying(to: s.db.operations) else { s.error = "Немає змін або вибрані записи вже змінилися."; return }
        if await s.changeInBackground({ $0.operations = rows }) { undo = plan; selected.removeAll() }
    }
    @MainActor private func restore() async {
        guard !saving else { return }; saving = true; defer { saving = false }
        guard let plan = undo, let rows = plan.applying(to: s.db.operations, undo: true) else { s.error = "Операції змінилися після редагування. Автоматичне скасування небезпечне."; return }
        if await s.changeInBackground({ $0.operations = rows }) { undo = nil }
    }
}
