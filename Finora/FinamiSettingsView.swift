import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct Settings: View {
  @EnvironmentObject var s: Store
  @AppStorage("lockEnabled") var lock = false
  @AppStorage("finami.hideAppSwitcher") private var hideAppSwitcher = true
  @State private var exporting = false
  @State private var importing = false
  @State private var legacy = false
  @State private var doc: DataFile?
  @State private var format: UTType = .json
  @State private var fileName = "Finami-backup"
  @State private var confirm = false
  @State private var pending: Data?
  @State private var restoreSummary = ""
  var body: some View {
    List {
      Section("Безпека") {
        Toggle("Face ID / код-пароль", isOn: $lock)
        Toggle("Приховувати огляд у перемикачі застосунків",isOn:$hideAppSwitcher)
        Text("Захисний екран при згортанні; момент системного знімка залежить від iOS.").font(.caption)
        Text(
          "Дані зберігаються у локальному сховищі застосунку. Видалення програми видалить і базу, тому роби резервні копії."
        ).font(.caption)
      }
      Section("Резервні копії") {
        NavigationLink("PDF, Excel, CSV, календар") { FinamiExportView() }
        NavigationLink("Зашифровані резервні копії") { FinamiSecureBackupView() }
        NavigationLink("Локальні попередні копії") { SnapshotView() }
        Text("Зберігай експорт JSON у «Файли» / iCloud Drive. Автоматична хмарна синхронізація ще не підключена.").font(.caption)
        Button("Експорт JSON") {
          format = .json
          fileName = "Finami-backup"
          do { doc = try s.backup(); exporting = true }
          catch { doc = nil; s.error = "Не вдалося створити копію: " + error.localizedDescription }
        }
        Button("Експорт CSV для Excel") {
          format = .commaSeparatedText
          fileName = "Finami-operations"
          doc = s.csv()
          exporting = true
        }
        Button("Відновити нову базу JSON") {
          legacy = false
          importing = true
        }
        Button("Імпорт операцій Scriptable / PWA") {
          legacy = true
          importing = true
        }
        Text(
          "Старий імпорт переносить доходи, витрати, категорії та загальний бюджет. Рахунки, перекази, борги й цілі зі старих копій не переносяться автоматично."
        ).font(.caption)
      }
    }.navigationTitle("Налаштування").fileExporter(
      isPresented: $exporting, document: doc, contentType: format, defaultFilename: fileName
    ) { if case .failure(let e) = $0 { s.error = e.localizedDescription } }.fileImporter(
      isPresented: $importing, allowedContentTypes: [.json]
    ) { result in
      do {
        let u = try result.get()
        let allowed = u.startAccessingSecurityScopedResource()
        defer { if allowed { u.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: u)
        if legacy {
          s.importLegacy(data)
        } else {
          let preview = try JSONDecoder().decode(Database.self,from:data)
          guard !preview.accounts.isEmpty, finamiExchangeBalance(preview.exchangeDiary ?? []) != nil else { throw CocoaError(.fileReadCorruptFile) }
          restoreSummary = "Рахунків: \(preview.accounts.count), операцій: \(preview.operations.count), договорів: \(preview.obligations.count), записів USDT: \((preview.exchangeDiary ?? []).count). Поточні дані буде замінено; остаточна перевірка перед записом."
          pending = data
          confirm = true
        }
      } catch { s.error = error.localizedDescription }
    }.confirmationDialog(
      "Замінити поточну базу? Спершу зроби резервну копію.", isPresented: $confirm,
      titleVisibility: .visible
    ) {
      Button("Відновити", role: .destructive) {
        if let data = pending { s.restore(data) }
        pending = nil
      }
      Button("Скасувати", role: .cancel) { pending = nil }
    } message: { Text(restoreSummary) }
  }
}
