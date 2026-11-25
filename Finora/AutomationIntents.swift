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
        return .result(dialog:"Message captured. Open Finami to review. / Повідомлення отримано. Відкрийте Finami для перевірки.")
    }
}
