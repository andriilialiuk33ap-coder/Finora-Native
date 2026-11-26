import AppIntents
import Foundation

struct CaptureWalletIntent: AppIntent {
    static var title: LocalizedStringResource = "Finami: Apple Pay"
    static var description: IntentDescription? = IntentDescription("Capture a Wallet payment / Записати оплату Wallet")
    static var openAppWhenRun: Bool = false
    @Parameter(title:"Amount / Сума") var amount: Double
    @Parameter(title:"Merchant / Продавець") var merchant: String
    @Parameter(title:"Account code / Код рахунку") var account: String
    @Parameter(title:"Currency / Валюта") var currency: String
    static var parameterSummary: some ParameterSummary {
        Summary("Apple Pay: \(\.$amount) \(\.$currency), \(\.$merchant), \(\.$account)")
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try finamiQueueWallet(amount: amount, merchant: merchant, account: account, currency: currency)
        return .result(dialog:"Payment captured. Open Finami to process it. / Оплату отримано. Відкрийте Finami для обробки.")
    }
}
private func finamiQueueWallet(amount: Double, merchant: String, account: String, currency: String) throws {
    let defaults = UserDefaults.standard
    let now = Date().timeIntervalSince1970
    defaults.set(now, forKey: "finami.lastWalletAttempt")
    let event: CapturedPayment
    do { event = try captureWallet(amount: amount, merchant: merchant, account: account, currency: currency) }
    catch { defaults.set("invalid", forKey: "finami.lastWalletStatus"); throw error }
    do { try CaptureInbox.enqueue(event, in: CaptureInbox.folder()) }
    catch { defaults.set("storageError", forKey: "finami.lastWalletStatus"); throw error }
    defaults.set(now, forKey: "finami.lastWalletCapture")
    defaults.set("queued", forKey: "finami.lastWalletStatus")
}
// A separate action keeps all existing per-account shortcuts compatible.
struct CaptureWalletAliasIntent: AppIntent {
    static var title: LocalizedStringResource = "Finami: Apple Pay · прив’язка картки"
    static var description: IntentDescription? = IntentDescription("Передайте унікальну назву або маску картки, прив’язану в Finami. Не передавайте повний номер картки.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Сума") var amount: Double
    @Parameter(title: "Продавець") var merchant: String
    @Parameter(title: "Валюта") var currency: String
    @Parameter(title: "Ключ картки") var cardKey: String
    static var parameterSummary: some ParameterSummary {
        Summary("Apple Pay: \(\.$amount) \(\.$currency), \(\.$merchant), картка \(\.$cardKey)")
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Unknown or missing key is intentionally queued for manual routing.
        let key = finamiWalletAliasKey(cardKey) ?? "wallet:unresolved"
        try finamiQueueWallet(amount: amount, merchant: merchant, account: key, currency: currency)
        return .result(dialog: "Оплату отримано. Відкрийте Finami для обробки.")
    }
}
struct CaptureMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Finami: Bank message"
    static var description: IntentDescription? = IntentDescription("Recognize a bank payment message / Розпізнати банківське повідомлення")
    static var openAppWhenRun: Bool = false
    @Parameter(title:"Message text / Текст повідомлення") var message: String
    @Parameter(title:"Account code / Код рахунку") var account: String
    static var parameterSummary: some ParameterSummary {
        Summary("Bank message: \(\.$message), \(\.$account)")
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let event = try captureMessage(message,account:account)
        try CaptureInbox.enqueue(event,in:CaptureInbox.folder())
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "finami.lastBankNotification")
        return .result(dialog:"Message captured. Open Finami to review. / Повідомлення отримано. Відкрийте Finami для перевірки.")
    }
}

// On iOS 27 the user selects a bank notification trigger in Shortcuts and passes its text.
// The existing safe message parser and deduplication are reused, without persisting raw notifications.
struct CaptureBankNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Finami: сповіщення банку"
    static var description: IntentDescription? = IntentDescription("Записати операцію з тексту банківського сповіщення, переданого Командами")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Текст сповіщення") var message: String?
    @Parameter(title: "Заголовок сповіщення (необов’язково)") var notificationTitle: String?
    @Parameter(title: "Код рахунку Finami або auto") var account: String?
    @Parameter(title: "Банк (необов’язково)") var bank: String?
    static var parameterSummary: some ParameterSummary {
        Summary("Записати сповіщення \(\.$message) на рахунок \(\.$account)") {
            \.$notificationTitle
            \.$bank
        }
    }
    func perform() async throws -> some IntentResult {
        let status = finamiHandleNotification(title: notificationTitle, body: message, account: account, bank: bank) { event in
            try CaptureInbox.enqueue(event, in: CaptureInbox.folder())
        }
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        defaults.set(status.rawValue, forKey: "finami.lastNotificationStatus")
        defaults.set(now, forKey: "finami.lastNotificationAttempt")
        if status == .queued { defaults.set(now, forKey: "finami.lastBankNotification") }
        // No dialog or thrown parse error for an unattended automation.
        return .result()
    }
}

// Tests only action discovery, parameter processing and communication; never enqueues a payment.
struct FinamiShortcutCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Finami: перевірка зв’язку"
    static var description: IntentDescription? = IntentDescription("Перевірка без запису фінансової операції")
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard finamiNotificationSelfTest() else { return .result(dialog: "Локальний тест розпізнавання не пройдено. Фінансові дані не змінено.") }
        _ = try captureWallet(amount: 1.25, merchant: "Test", account: "diagnostic", currency: "UAH")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "finami.lastShortcutCheck")
        return .result(dialog: "Finami відповідає. Фінансові дані не змінено.")
    }
}
struct FinamiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureBankNotificationIntent(), phrases: ["Record bank notification with \(.applicationName)"], shortTitle: "Сповіщення банку", systemImageName: "bell.badge")
        AppShortcut(intent: CaptureWalletIntent(), phrases: ["Record Wallet payment with \(.applicationName)"], shortTitle: "Apple Pay", systemImageName: "creditcard")
        AppShortcut(intent: CaptureWalletAliasIntent(), phrases: ["Record linked card payment with \(.applicationName)"], shortTitle: "Apple Pay · картка", systemImageName: "creditcard.fill")
        AppShortcut(intent: CaptureMessageIntent(), phrases: ["Record bank message with \(.applicationName)"], shortTitle: "Банківське SMS", systemImageName: "message")
        AppShortcut(intent: FinamiShortcutCheckIntent(), phrases: ["Check \(.applicationName)"], shortTitle: "Перевірка зв’язку", systemImageName: "checkmark.shield")
    }
}
