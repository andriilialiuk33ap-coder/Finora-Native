import SwiftUI

// Migration is explicit. Keep the amount, source account, import key and date intact.
struct CreditImportCorrection: View {
    @EnvironmentObject var s: Store
    @State private var account = ""
    @State private var confirm = false
    @State private var correctionVersion: UInt64?
    @State private var correctionAccount = ""
    @State private var edited: Operation?
    private var candidates: [Operation] {
        s.db.operations.filter { $0.account == account && $0.sourceBank != nil && $0.classificationReviewed != true && ($0.kind == .income || $0.kind == .expense) }
            .sorted { $0.date > $1.date }
    }
    private func proposed(_ o: Operation) -> Kind {
        let credit = s.db.accounts.first(where: {$0.id == o.account})?.isCredit ?? false
        // Old PUMB imports didn't retain the operation type. Never downgrade a normal old purchase just because that metadata is missing.
        let type = o.bankType ?? (o.sourceBank == "ПУМБ" && o.kind == .expense && !["переказ","transfer","account ","card*","поповнення","зняття"].contains(where:{o.note.lowercased().contains($0)}) ? "Покупка" : nil)
        let value = bankKind(signed:o.signedNative,note:o.note,mcc:o.bankMCC,operationType:type,creditAccount:credit)
        let kind = Kind(rawValue:value) ?? o.kind
        if o.kind == .expense && kind == .unclassifiedDebit && o.bankType == nil && o.bankMCC == nil && !["переказ","transfer","account ","card*","поповнення","зняття"].contains(where:{o.note.lowercased().contains($0)}) {return .expense}
        return kind.incoming == o.kind.incoming ? kind : o.kind
    }
    private var changes: [Operation] {candidates.filter {proposed($0) != $0.kind}}
    private var pending: [Operation] {s.db.operations.filter {$0.account == account && $0.kind.needsReview}.sorted {$0.date > $1.date}}
    var body: some View {
        List {
            Section {
                Picker("Рахунок", selection:$account) {
                    Text("Вибрати").tag("")
                    ForEach(s.db.accounts) { Text($0.name).tag($0.id) }
                }
                Text("Перевірка змінює лише тип операцій. Залишок рахунку не зміниться. Невідомі зарахування не є доходом до уточнення.").font(.caption)
            }
            Section("Запропоновані зміни") {
                if changes.isEmpty {Text("Немає запропонованих змін")}
                ForEach(changes) { o in
                    Button {edited=o} label: {
                        VStack(alignment:.leading,spacing:5) {
                            Text(o.note.isEmpty ? "Без опису" : o.note).foregroundStyle(.primary)
                            Text(o.kind.title + " → " + proposed(o).title).font(.caption).foregroundStyle(.orange)
                            Text(s.privateAmounts || s.db.accounts.first(where: {$0.id == o.account})?.hideAmounts == true ? "••••" : currencyMoney(o.sourceMinor ?? o.amount, s.db.accounts.first(where: {$0.id == o.account})?.code ?? "UAH")).font(.subheadline.bold()).monospacedDigit()
                        }
                    }
                }
                Button("Застосувати запропоновані зміни") {
                    correctionVersion = s.databaseVersion
                    correctionAccount = account
                    confirm = true
                }.disabled(changes.isEmpty)
            }
            Section("Потребують уточнення") {
                ForEach(pending) { o in Button {edited=o} label: {OperationRow(o:o)}.buttonStyle(.plain) }
                if pending.isEmpty {Text("Немає операцій")}
            }
        }.navigationTitle("Виправлення обліку")
        .sheet(item:$edited) {OpEditor(original:$0)}
        .confirmationDialog("Застосувати зміни типів?",isPresented:$confirm) {
            Button("Застосувати") {
                guard correctionVersion == s.databaseVersion, correctionAccount == account,
                      s.db.accounts.contains(where: { $0.id == correctionAccount }) else {
                    s.error = "Рахунок або операції змінилися. Перевір запропоновані виправлення ще раз."
                    return
                }
                let types = Dictionary(uniqueKeysWithValues: changes.map {($0.id, proposed($0))})
                s.change { d in
                    for i in d.operations.indices {
                        guard d.operations[i].account == correctionAccount, let k = types[d.operations[i].id] else {continue}
                        d.operations[i].kind=k
                        if !k.isReportCategory {d.operations[i].category="Без категорії"}
                        d.operations[i].classificationReviewed=true
                    }
                }
            }
            Button("Скасувати",role:.cancel) {}
        }
    }
}
