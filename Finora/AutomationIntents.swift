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
        let event = try captureWallet(amount:amount,merchant:merchant,account:account,currency:currency)
        try CaptureInbox.enqueue(event,in:CaptureInbox.folder())
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "finami.lastWalletCapture")
        return .result(dialog:"Payment captured. Open Finami to process it. / Оплату отримано. Відкрийте Finami для обробки.")
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
    @Parameter(title: "Текст сповіщення") var message: String
    @Parameter(title: "Код рахунку Finami") var account: String
    static var parameterSummary: some ParameterSummary {
        Summary("Записати сповіщення \(\.$message) на рахунок \(\.$account)")
    }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let event = try captureMessage(message, account: account)
        try CaptureInbox.enqueue(event, in: CaptureInbox.folder())
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "finami.lastBankNotification")
        return .result(dialog: "Сповіщення прийнято. Відкрий Finami для обробки.")
    }
}

// Tests only action discovery, parameter processing and communication; never enqueues a payment.
struct FinamiShortcutCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Finami: перевірка зв’язку"
    static var description: IntentDescription? = IntentDescription("Перевірка без запису фінансової операції")
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try captureWallet(amount: 1.25, merchant: "Test", account: "diagnostic", currency: "UAH")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "finami.lastShortcutCheck")
        return .result(dialog: "Finami відповідає. Фінансові дані не змінено.")
    }
}
struct FinamiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FinamiShortcutCheckIntent(), phrases: ["Check \(.applicationName)"], shortTitle: "Перевірка зв’язку", systemImageName: "checkmark.shield")
    }
}
