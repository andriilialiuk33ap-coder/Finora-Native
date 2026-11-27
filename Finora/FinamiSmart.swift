import SwiftUI
import UIKit
import UserNotifications
import PhotosUI
import AVFoundation
import Speech
import CryptoKit
import CommonCrypto
import Security
import UniformTypeIdentifiers

final class FinamiNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
@MainActor enum FinamiSavedNotification {
    static func post(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Finami"
        content.body = "Збережено нові операції: \(count)."
        let request = UNNotificationRequest(identifier: "finami-saved-" + UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
struct FinamiImportHub: View {
    @EnvironmentObject private var s: Store
    @State private var voice = false
    var body: some View {
        List {
            Section("Додати дані") {
                NavigationLink("Скриншоти операцій") { FinamiScanView(initialMode: .transactions) }
                NavigationLink("Скриншоти розстрочок") { FinamiScanView(initialMode: .installment) }
                NavigationLink("Звірка залишків") { FinamiReconciliation() }
                NavigationLink("Фото чека") { ReceiptScanView() }
                NavigationLink("Банківські виписки") { BankCenter() }
                Button("Голосовий запис") { voice = true }
                NavigationLink("Автоматизація") { AutomationCenter() }
            }
            Section("Експорт і резервні копії") { NavigationLink("PDF, Excel, CSV, календар") { FinamiExportView() }; NavigationLink("JSON та відновлення") { Settings() } }
            Section("Якість обліку") { NavigationLink("Аудит фінансової бази") { FinamiAuditView() }; NavigationLink("Правила категоризації") { FinamiRulesView() } }
            Section("Відновлення") {
                NavigationLink("Історія та скасування імпорту") { BankImportHistory() }
                NavigationLink("Локальні попередні копії") { SnapshotView() }
            }
        }.navigationTitle("Імпорт та експорт")
        .sheet(isPresented: $voice) { FinamiVoice() }
    }
}
struct FinamiDiagnostics: View {
    @EnvironmentObject private var s: Store
    @State private var notifications = "Не перевірено"
    @State private var scheduled = 0
    @State private var checked = false
    @State private var parser = "Не перевірено"
    @State private var diagnosticDocument:DataFile?
    @State private var exportingDiagnostics=false
    @AppStorage("finami.lastShortcutCheck") private var lastCheck: Double = 0
    @AppStorage("finami.lastWalletCapture") private var lastWallet: Double = 0
    @AppStorage("finami.lastWalletAttempt") private var lastWalletAttempt: Double = 0
    @AppStorage("finami.lastWalletStatus") private var lastWalletStatus = ""
    @AppStorage("finami.lastBankNotification") private var lastBank: Double = 0
    @AppStorage("finami.lastNotificationAttempt") private var lastNotificationAttempt: Double = 0
    @AppStorage("finami.lastNotificationStatus") private var lastNotificationStatus = ""
    @AppStorage("finami.notificationShortcutLink") private var bankLink = ""
    @AppStorage("finami.walletShortcutLink") private var walletLink = ""
    private func stamp(_ t: Double) -> String { t > 0 ? Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .shortened) : "Ще не отримано" }
    var body: some View {
        List {
            Section("Версія застосунку") {
                LabeledContent("Версія / Build",value:FinamiBuildInfo.version)
                LabeledContent("Оформлення",value:FinamiBuildInfo.edition)
            }
            Section("Локальні дані") {
                LabeledContent("Сховище", value: s.storageHealthy ? "База читається" : "Запис заблоковано")
                LabeledContent("Рахунки", value: String(s.db.accounts.count))
                LabeledContent("Резервні копії", value: String(s.snapshotURLs().count))
                LabeledContent("Вхідні", value: String(s.capturePending.count))
                if let warning = s.captureWarning { Text(warning).foregroundStyle(.orange) }
            }
            Section("Системні дозволи") {
                LabeledContent("Сповіщення", value: notifications)
                LabeledContent("Мікрофон", value: AVAudioSession.sharedInstance().recordPermission == .granted ? "Дозволено" : "Не дозволено / не запитано")
                LabeledContent("Мовлення", value: SFSpeechRecognizer.authorizationStatus() == .authorized ? "Дозволено" : "Не дозволено / не запитано")
                if checked { LabeledContent("Заплановані сповіщення Finami", value: String(scheduled)) }
                Button("Запросити дозвіл на сповіщення") { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]); await refresh() } }
            }
            Section("Команди") {
                LabeledContent("Посилання банку", value: finamiBankShortcutURL(bankLink) == nil ? "Не задано" : "Формат правильний")
                LabeledContent("Посилання Wallet", value: finamiSharedShortcutURL(walletLink) == nil ? "Не задано" : "Формат правильний")
                LabeledContent("Останній тест", value: stamp(lastCheck))
                LabeledContent("Останній Wallet", value: stamp(lastWallet))
                LabeledContent("Останній виклик Wallet", value: stamp(lastWalletAttempt))
                Text(FinamiNotificationStatus.display(lastWalletStatus)).font(.caption)
                LabeledContent("Карткові прив’язки", value: String(s.db.capturePreferences?.walletBindings?.count ?? 0))
                LabeledContent("Остання прийнята операція банку", value: stamp(lastBank))
                LabeledContent("Останній виклик сповіщення", value: stamp(lastNotificationAttempt))
                Text(FinamiNotificationStatus.display(lastNotificationStatus)).font(.caption).accessibilityIdentifier("qa.diagnostics.notificationStatus")
                Text("Це зафіксовані виклики, а не перевірка стану системної автоматизації. Правильний формат посилання не гарантує існування команди.").font(.caption)
                NavigationLink("Налаштувати автоматизацію") { AutomationCenter() }
            }
            Section("Знеособлений звіт") {
                Text("Містить лише версію, версію iOS, чисельність записів і статуси перевірок. Без назв рахунків, сум, нотаток, реквізитів, посилань на команди чи резервної копії.").font(.caption)
                Button("Експорт діагностики JSON") {
                    let report:[String:String] = ["version":FinamiBuildInfo.version,"edition":FinamiBuildInfo.edition,"ios":UIDevice.current.systemVersion,"storageHealthy":String(s.storageHealthy),"accounts":String(s.db.accounts.count),"operations":String(s.db.operations.count),"contracts":String(s.db.obligations.count),"snapshots":String(s.snapshotURLs().count),"parserSelfTest":String(finamiNotificationSelfTest()),"exchangeValid":String(finamiExchangeBalance(s.db.exchangeDiary ?? []) != nil),"partnerGroupsValid":String(finamiValidPartnerGroups(s.db.partnerGroups ?? []))]
                    do {let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];diagnosticDocument=DataFile(data:try encoder.encode(report));exportingDiagnostics=true}
                    catch {s.error="Не вдалося створити діагностичний звіт."}
                }
            }
            Section("Безпечні локальні перевірки") {
                Text("Парсер: " + parser)
                    .foregroundStyle(parser == "Тест не пройдено" ? Color.orange : Color.primary)
                    .accessibilityIdentifier("qa.diagnostics.parser")
                Button("Перевірити зараз") {
                    parser = finamiNotificationSelfTest() ? "Тест пройдено" : "Тест не пройдено"
                    Task { await refresh() }
                }.accessibilityIdentifier("qa.diagnostics.run")
                Text("Тест не додає операцій і не змінює баланс.").font(.caption)
            }
        }.navigationTitle("Діагностика").task { await refresh() }.fileExporter(isPresented:$exportingDiagnostics,document:diagnosticDocument,contentType:.json,defaultFilename:"Finami-diagnostics") { result in if case .failure(let e)=result {s.error=e.localizedDescription} }
    }
    @MainActor private func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus { case .authorized, .provisional, .ephemeral: notifications = "Дозволено"; case .denied: notifications = "Вимкнено"; default: notifications = "Не запитано" }
        scheduled = await center.pendingNotificationRequests().count; checked = true
        s.refreshCaptures(auto: false)
    }
}
struct FinamiSecureBackupView: View {
    @EnvironmentObject private var s: Store
    @State private var password = ""
    @State private var confirmation = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmRestore = false
    @State private var document: DataFile?
    @State private var pending: Data?
    @State private var status = ""
    var body: some View {
        Form {
            Section("Пароль копії") {
                SecureField("Пароль", text: $password)
                SecureField("Повтори пароль для експорту", text: $confirmation)
                Text("Не менше 12 символів для нової копії. Пароль не зберігається. Без нього відновити копію неможливо.").font(.caption)
            }
            Section("Експорт та відновлення") {
                Button("Створити зашифровану копію") {
                    do { let raw = try JSONEncoder().encode(s.db); document = DataFile(data: try FinamiBackupCrypto.seal(raw, password: password)); exporting = true; status = "" } catch { status = error.localizedDescription }
                }.disabled(password.count < 12 || password != confirmation || !s.storageHealthy)
                Button("Відкрити зашифровану копію") { importing = true }.disabled(password.isEmpty)
                if !status.isEmpty { Text(status).foregroundStyle(.orange) }
                Text("AES-GCM та PBKDF2-SHA256. Звичайний JSON-експорт і локальні попередні копії залишаються незашифрованими цим паролем. Вхідна черга та системні налаштування не входять до копії бази.").font(.caption)
            }
        }.navigationTitle("Зашифровані копії")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Finami-encrypted") { result in if case .failure(let error) = result { status = error.localizedDescription }; document = nil }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let plain = try FinamiBackupCrypto.open(Data(contentsOf: url), password: password); _ = try JSONDecoder().decode(Database.self, from: plain); pending = plain; confirmRestore = true } catch { status = error.localizedDescription }
        }.confirmationDialog("Замінити поточну базу?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Відновити", role: .destructive) { if let data = pending { s.restore(data) }; pending = nil; password = ""; confirmation = "" }
            Button("Скасувати", role: .cancel) { pending = nil }
        }
    }
}

struct FinamiReconciliation: View {
    @EnvironmentObject private var s: Store
    var body: some View {
        List {
            Section {
                NavigationLink("Ввести контрольний баланс банку") { FinamiBalanceView(initialMode:"anchor") }
                NavigationLink("Перенести записи або об’єднати обмін") { FinamiBalanceView() }
                NavigationLink("Перевірити схожі операції") { FinamiNextReviewView() }
                NavigationLink("Вхідні банківські події (\(s.capturePending.count))") { AutomationCenter() }
                NavigationLink("Звірити зі скриншота") { FinamiScanView(initialMode: .balance) }
                Text("Доступний залишок із банківського повідомлення зберігається як довідка. Він може включати кредит або блокування коштів. Finami не змінює баланс без підтвердження.").font(.caption)
            }
            Section("Останні суми, отримані від банку") {
                ForEach(s.db.accounts) { account in
                    if let observation = s.db.balanceObservations?[account.id], observation.currency == account.code {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(account.name).font(.headline)
                            Text(observation.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            LabeledContent("Доступно за даними банку", value: account.hideAmounts == true ? "••••" : s.visibleMoney(observation.available, account.code))
                            let result = finamiReconcile(account: account, operations: s.historyForAccount(account.id), observedAt: observation.date, reported: observation.available)
                            LabeledContent("Finami на час сповіщення", value: account.hideAmounts == true ? "••••" : s.visibleMoney(result.computedAtObservation, account.code))
                            LabeledContent("Різниця на ту дату", value: account.hideAmounts == true ? "••••" : s.visibleMoney(result.difference, account.code))
                            if result.laterOperations > 0 { Text("Після сповіщення: \(result.laterOperations) нових операцій. Вони не включені в історичну звірку.").font(.caption).foregroundStyle(.secondary) }
                            if result.possibleUnclassified > 0 { Text("Неуточнені операції до цієї дати: \(result.possibleUnclassified)").font(.caption) }
                            if result.difference != 0 {
                                NavigationLink("Перевірити банківську виписку") { BankCenter() }
                                NavigationLink("Переглянути неуточнені операції") { FinamiImportHub() }
                            }
                            Text("Історична оцінка за поточними початковим балансом і лімітом. Якщо ліміт змінився, банк врахував холди чи комісії, різниця не є підтвердженою помилкою. Автоматичного коригування немає.").font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
                if (s.db.balanceObservations ?? [:]).isEmpty { Text("Ще немає підтверджених повідомлень із доступним залишком.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Звірка залишків")
    }
}
