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
    @State private var event: CapturedPayment?
    @State private var operation: Operation?
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
            Section("Вхідні · \(s.capturePending.count)") {
                if s.capturePending.isEmpty { Text("Немає нових повідомлень").foregroundStyle(.secondary) }
                ForEach(s.capturePending) { e in
                    Button { event = e } label: { VStack(alignment: .leading) { Text(e.merchant.isEmpty ? e.source : e.merchant); Text(s.visibleMoney(e.minor,e.currency)).font(.caption); Text(e.account.isEmpty ? "Обери рахунок" : s.accountName(e.account)).font(.caption).foregroundStyle(.secondary) } }
                }
                if let warning = s.captureWarning { Text(warning).foregroundStyle(.orange) }
                Button("Оновити вхідні") { s.refreshCaptures(auto: false) }
            }
            Section("Потребують уточнення") {
                let pending = s.db.operations.filter { $0.kind.needsReview }.sorted { $0.date > $1.date }
                if pending.isEmpty { Text("Усе уточнено").foregroundStyle(.secondary) }
                ForEach(pending) { o in Button { operation = o } label: { VStack(alignment: .leading) { Text(o.note.isEmpty ? o.kind.title : o.note); Text(s.visibleMoney(o.amount)).font(.caption) } } }
            }
            Section("Відновлення") {
                NavigationLink("Історія та скасування імпорту") { BankImportHistory() }
                NavigationLink("Локальні попередні копії") { SnapshotView() }
            }
        }.navigationTitle("Центр імпорту").onAppear { s.refreshCaptures(auto: false) }
        .sheet(isPresented: $voice) { FinamiVoice() }
        .sheet(item: $event) { CaptureReview(event: $0) }
        .sheet(item: $operation) { OpEditor(original: $0) }
    }
}
struct FinamiDiagnostics: View {
    @EnvironmentObject private var s: Store
    @State private var notifications = "Не перевірено"
    @State private var scheduled = 0
    @State private var checked = false
    @State private var parser = "Не перевірено"
    @AppStorage("finami.lastShortcutCheck") private var lastCheck: Double = 0
    @AppStorage("finami.lastWalletCapture") private var lastWallet: Double = 0
    @AppStorage("finami.lastBankNotification") private var lastBank: Double = 0
    @AppStorage("finami.notificationShortcutLink") private var bankLink = ""
    @AppStorage("finami.walletShortcutLink") private var walletLink = ""
    private func stamp(_ t: Double) -> String { t > 0 ? Date(timeIntervalSince1970: t).formatted(date: .abbreviated, time: .shortened) : "Ще не отримано" }
    var body: some View {
        List {
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
                LabeledContent("Посилання банку", value: finamiSharedShortcutURL(bankLink) == nil ? "Не задано" : "Формат правильний")
                LabeledContent("Посилання Wallet", value: finamiSharedShortcutURL(walletLink) == nil ? "Не задано" : "Формат правильний")
                LabeledContent("Останній тест", value: stamp(lastCheck))
                LabeledContent("Останній Wallet", value: stamp(lastWallet))
                LabeledContent("Останнє повідомлення", value: stamp(lastBank))
                Text("Це зафіксовані виклики, а не перевірка стану системної автоматизації. Правильний формат посилання не гарантує існування команди.").font(.caption)
                NavigationLink("Налаштувати автоматизацію") { AutomationCenter() }
            }
            Section("Безпечні локальні перевірки") {
                LabeledContent("Парсер", value: parser).accessibilityIdentifier("qa.diagnostics.parser")
                Button("Перевірити зараз") { Task { await refresh() } }
                Text("Тест не додає операцій і не змінює баланс.").font(.caption)
            }
        }.navigationTitle("Діагностика").task { await refresh() }
    }
    @MainActor private func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus { case .authorized, .provisional, .ephemeral: notifications = "Дозволено"; case .denied: notifications = "Вимкнено"; default: notifications = "Не запитано" }
        scheduled = await center.pendingNotificationRequests().count; checked = true
        s.refreshCaptures(auto: false)
        do { let e = try captureMessage("Купівля 20.00UAH; Магазин: Test", account: "diagnostic"); parser = e.minor == 2000 ? "Тест пройдено" : "Неправильна сума" } catch { parser = error.localizedDescription }
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
                            if s.db.operations.contains(where: { ($0.account == account.id || ($0.kind == .transfer && $0.destination == account.id)) && $0.date > observation.date }) {
                                Text("Після повідомлення є нові операції — сума може бути застарілою.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                let available = s.available(account)
                                LabeledContent("Розрахунок Finami", value: account.hideAmounts == true ? "••••" : s.visibleMoney(available, account.code))
                                LabeledContent("Різниця", value: account.hideAmounts == true ? "••••" : s.visibleMoney(observation.available-available, account.code))
                                Text("Різниця не є підтвердженою помилкою: банк може враховувати холди або комісії.").font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if (s.db.balanceObservations ?? [:]).isEmpty { Text("Ще немає підтверджених повідомлень із доступним залишком.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Звірка залишків")
    }
}
