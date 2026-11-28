import SwiftUI
import UniformTypeIdentifiers

/// Shown inside Root's existing authentication and app-switcher privacy gate.
struct FinamiRecoveryView: View {
    @EnvironmentObject private var store: Store
    @State private var original: Data?
    @State private var selectedIndex = ""
    @State private var amountText = ""
    @State private var accountText = ""
    @State private var destinationText = ""
    @State private var comparison = ""
    @State private var draft = ""
    @State private var status = ""
    @State private var validated: Data?
    @State private var exporting = false
    @State private var importing = false
    @State private var confirming = false
    @State private var snapshot: URL?
    @State private var confirmingSnapshot = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Дані захищено") {
                    Text("База не пройшла перевірку. Звичайні фінансові операції заблоковано. Оригінал не буде замінено без підтвердження та створення карантинної копії.")
                    Text(status).font(.caption).textSelection(.enabled)
                    Button("Експортувати оригінальний JSON") { exporting = true }.disabled(original == nil)
                    Text("JSON містить приватні фінансові дані. Зберігай його в захищеному місці. Окремі вкладення не входять у цей файл.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Ручне виправлення") {
                    Text("Виправ лише відомий помилковий запис. Суми у JSON зберігаються в мінімальних одиницях валюти. Не видаляй операції для обходу перевірки.").font(.caption)
                    if original != nil && !draft.isEmpty {
                        DisclosureGroup("Редактор операції") {
                            TextField("Номер операції (з повідомлення)", text: $selectedIndex).keyboardType(.numberPad)
                            Button("Завантажити поля") { loadOperation() }
                            TextField("Сума в копійках", text: $amountText).keyboardType(.numberPad)
                            TextField("ID рахунку", text: $accountText).autocorrectionDisabled()
                            TextField("ID рахунку призначення", text: $destinationText).autocorrectionDisabled()
                            if !recoveryAccounts.isEmpty {
                                Menu("Вибрати рахунок за назвою") {
                                    ForEach(recoveryAccounts, id: \.id) { a in Button(a.name) { accountText = a.id } }
                                }
                                Menu("Вибрати рахунок призначення") {
                                    ForEach(recoveryAccounts, id: \.id) { a in Button(a.name) { destinationText = a.id } }
                                }
                            }
                            Button("Оновити чернетку") { updateOperation() }
                        }
                        if !comparison.isEmpty { Text(comparison).font(.caption).monospacedDigit() }
                        TextEditor(text: $draft).font(.system(.caption, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never).frame(minHeight: 220)
                            .onChange(of: draft) { _ in validated = nil; comparison = "" }
                        Button("Перевірити виправлення") { validate() }
                        Button("Застосувати перевірений JSON") { confirming = true }.disabled(validated == nil)
                    }
                    Button("Відкрити виправлений JSON") { importing = true }.disabled(original == nil)
                }
                Section("Локальні копії") {
                    ForEach(store.snapshotURLs(), id: \.self) { url in
                        Button(url.lastPathComponent) { snapshot = url; confirmingSnapshot = true }
                    }
                    if store.snapshotURLs().isEmpty { Text("Локальних копій немає.").foregroundStyle(.secondary) }
                }
            }.navigationTitle("Відновлення бази")
                .task {
                    do {
                        let bytes = try store.recoveryOriginal()
                        original = bytes
                        draft = String(data: bytes, encoding: .utf8) ?? ""
                        do { try store.validateRecovery(bytes); status = "JSON пройшов базову перевірку. Можлива інша помилка завантаження." }
                        catch {
                            status = error.localizedDescription
                            if let failure = error as? FinamiDatabaseSafety.OperationFailure {
                                selectedIndex = String(failure.index + 1); loadOperation(); status = failure.localizedDescription
                            }
                        }
                    } catch { status = error.localizedDescription }
                }
                .fileExporter(isPresented: $exporting, document: DataFile(data: original ?? Data()), contentType: .json, defaultFilename: "Finami-original") { result in
                    if case .failure(let error) = result { status = error.localizedDescription }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let bytes = try Data(contentsOf: url)
                        guard let text = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                        draft = text; validated = nil; status = "Файл відкрито. Перевір його перед застосуванням."
                    } catch { status = error.localizedDescription }
                }
                .confirmationDialog("Замінити базу виправленим JSON?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Створити карантин і відновити") {
                        guard let bytes = validated, let original, bytes == Data(draft.utf8) else { return }
                        store.applyRecovery(bytes, expectedOriginal: original)
                    }
                } message: { Text("Оригінал залишиться у локальному карантині. Перевір зміни фінансових записів перед підтвердженням.") }
                .confirmationDialog("Відновити стару копію?", isPresented: $confirmingSnapshot, titleVisibility: .visible) {
                    Button("Відновити копію", role: .destructive) { if let snapshot { store.restoreSnapshot(snapshot) } }
                } message: { Text("Операції після дати копії можуть не увійти у відновлену базу. Поточний файл буде збережено в карантині.") }
        }
    }
    private struct RecoveryAccount { let id: String; let name: String }
    private var recoveryAccounts: [RecoveryAccount] {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(draft.utf8))) as? [String: Any], let rows = root["accounts"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return RecoveryAccount(id: id, name: row["name"] as? String ?? id)
        }
    }
    private func operationDocument() throws -> ([String: Any], [[String: Any]], Int) {
        guard let root = try JSONSerialization.jsonObject(with: Data(draft.utf8)) as? [String: Any],
              let rows = root["operations"] as? [[String: Any]],
              let number = Int(selectedIndex), number > 0, number <= rows.count else { throw CocoaError(.fileReadCorruptFile) }
        return (root, rows, number - 1)
    }
    private func loadOperation() {
        do {
            let (_, rows, index) = try operationDocument()
            let row = rows[index]
            amountText = (row["amount"] as? NSNumber)?.stringValue ?? ""
            accountText = row["account"] as? String ?? ""
            destinationText = row["destination"] as? String ?? ""
            status = "Операція ID: " + (row["id"] as? String ?? "невідомий")
        } catch { status = error.localizedDescription }
    }
    private func updateOperation() {
        do {
            var (root, rows, index) = try operationDocument()
            guard let amount = Int64(amountText), amount > 0, amount <= 1_000_000_000_000, !accountText.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            rows[index]["amount"] = amount
            rows[index]["account"] = accountText
            rows[index]["destination"] = destinationText
            root["operations"] = rows
            let bytes = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            draft = String(decoding: bytes, as: UTF8.self)
            validated = nil; comparison = ""
            status = "Чернетку оновлено. Перевір перед записом."
        } catch { status = error.localizedDescription }
    }
    private func recoveryComparison(_ bytes: Data) -> String {
        guard let after = try? JSONDecoder().decode(Database.self, from: bytes) else { return "" }
        let afterIndex = FinamiLedgerIndex(operations: after.operations, accounts: after.accounts)
        let before = original.flatMap { try? JSONDecoder().decode(Database.self, from: $0) }
        let safeBefore = before.flatMap { candidate -> Database? in
            guard (try? FinamiDatabaseSafety.validate(candidate)) != nil else { return nil }
            return candidate
        }
        let beforeIndex = safeBefore.map { FinamiLedgerIndex(operations: $0.operations, accounts: $0.accounts) }
        var lines = ["Операції: \(before.map { String($0.operations.count) } ?? "—") → \(after.operations.count)"]
        for account in after.accounts {
            let old = safeBefore?.accounts.first { $0.id == account.id && $0.code == account.code }
            let prior = old.flatMap { beforeIndex?.balance($0) }.map { finamiMinorText($0) } ?? "не перевірено"
            lines.append("\(account.name): \(prior) → \(finamiMinorText(afterIndex.balance(account))) \(account.code)")
        }
        if safeBefore == nil { lines.append("Початкові баланси не обчислюються через помилку валідації.") }
        return lines.joined(separator: "\n")
    }
    private func validate() {
        validated = nil
        let bytes = Data(draft.utf8)
        do { try store.validateRecovery(bytes); validated = bytes; comparison = recoveryComparison(bytes); status = "Базова перевірка успішна. Перед записом буде виконано повну перевірку відновлення." }
        catch { status = error.localizedDescription }
    }
}
