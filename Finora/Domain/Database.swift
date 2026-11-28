import Foundation

let expenseDefaults = [
  "🛒 Продукти", "🍽️ Ресторани", "☕ Кава", "🚗 Транспорт", "⛽ Паливо", "🚕 Таксі", "🏠 Дім",
  "🧾 Комунальні", "🔑 Оренда", "🛠️ Ремонт", "👕 Одяг", "💇 Краса", "💊 Здоров’я", "🏋️ Спорт", "🎬 Розваги",
  "📺 Підписки", "💻 Техніка", "📱 Зв’язок", "✈️ Подорожі", "📚 Освіта", "🐾 Тварини", "👶 Діти",
  "🎁 Подарунки", "💳 Розстрочка", "🛡️ Страхування", "🏦 Комісії", "📦 Доставка", "❤️ Благодійність",
  "🏪 Побут", "🅿️ Паркування", "🚆 Поїздки", "🦷 Стоматологія", "🧴 Гігієна", "🎮 Ігри", "🍕 Доставка їжі", "📦 Маркетплейси", "🧰 Робочі витрати", "🪴 Сад", "🧾 Податки", "🏥 Лікування", "Без категорії", "Інше",
]
let incomeDefaults = [
  "💼 Зарплата", "💻 Підробіток", "🏢 Бізнес", "🎁 Подарунок", "↩️ Повернення", "💵 Кешбек", "📈 Відсотки",
  "Без категорії", "Інше",
]
struct Database: Codable {
  var accounts = [Account(id: cash, name: "Готівка")]
  var operations: [Operation] = []
  var obligations: [Obligation] = []
  var expenseCategories = expenseDefaults
  var incomeCategories = incomeDefaults
  var receiptCategories: [String]? = nil
  var availableReceiptCategories: [String] { receiptCategories ?? FinamiReceiptTreatment.categories }
  var budget: Int64 = 0
  var limits: [String: Int64] = [:]
  var dashboard: [DashboardItem]? = nil
  var preferences: AppearancePreferences? = nil
  var appearanceRevision: String? = nil
  var subscriptions: [SubscriptionRecord]? = nil
  var reminders: [PersonalReminder]? = nil
  var forecast: ForecastPreferences? = nil
  var merchantRules: [String: String]? = nil
  var dismissedRecurringSuggestions: [String]? = nil
  var currencyPreferences: CurrencyPreferences? = nil
  var capturePreferences: CapturePreferences? = nil
  var captureHandled: [String]? = nil
  var balanceObservations: [String: FinamiBalanceObservation]? = nil
  var captureMessageFingerprints: [String]? = nil
  var hiddenExpenseCategories: [String]? = nil
  var hiddenIncomeCategories: [String]? = nil
  var categoryParents: [String: String]? = nil
  var paymentPhotos: [String: Data]? = nil
  var paidRecords: [FinamiPaidRecord]? = nil
  var scanImages: [String: Data]? = nil
  var scanFileHashes: [String: String]? = nil
  var reconciliationUndo: Data? = nil
  var exchangeDiary: [FinamiExchangeRecord]? = nil
  var partnerGroups: [FinamiPartnerGroup]? = nil
  var removedInstallments: [Obligation]? = nil
}
struct Legacy: Decodable {
  struct Entry: Decodable {
    var amt: Decimal
    var ts: Double
    var cat: String?
    var note: String?
  }
  var items: [Entry]
  var incomes: [Entry]
  var budget: Decimal?
}
