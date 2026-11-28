# Build 79 — Test Foundation та перша декомпозиція

Основа: Build 78 / 6.4.30. Цей етап свідомо не змінює фінансові формули, схему JSON, шляхи файлів, SwiftUI-поведінку або шифрування.

## Структура

- `Finora/Finora.swift`: точка запуску, Root, спільні допоміжні функції.
- `Finora/Domain/Ledger`: Foundation-only моделі операцій, рахунків, фінансовий індекс, активність рахунків.
- `Finora/Domain/PaymentModels.swift`: договори, історія оплат, undo.
- `Finora/Domain/FinancialRecords.swift`: валютні записи та партнерські групи.
- `Finora/Domain/Database.swift`: база, категорії за замовчуванням, старий формат.
- `Finora/FinamiStore.swift`: Store як і раніше MainActor, ті самі методи збереження та кеші.
- `Finora/FinamiDataFile.swift`: FileDocument.
- `Finora/FinamiHomeViews.swift`, `FinamiAccountViews.swift`, `FinamiMoreView.swift`, `FinamiBudgetViews.swift`, `FinamiObligationViews.swift`, `FinamiPlanningViews.swift`, `FinamiSettingsView.swift`, `FinamiInsightsChart.swift`: перенесені екрани та компоненти.

Кожен непорожній рядок оригінального Finora.swift (крім import) збережено рівно в тій самій кількості; це структурна перевірка, а не доказ компіляції iOS. Усі перенесені декларації зберегли імена, властивості й тіла. XcodeGen рекурсивно включає `Finora/`, SwiftPM компілює лише `Domain/Ledger` без залежностей від UI. Мінімальна iOS 16 не змінена.

## Тести

- `swift test`: 8 XCTest на реальному Foundation-коді, не тестових копіях. Окремий швидкий тестовий пакет без зовнішніх залежностей.
- `bash Tests/run-regression.sh`: XCTest + усі попередні скрипти + рекурсивна перевірка синтаксису. Існуючі сценарії не видалено. Модельні адаптери тепер збираються з цілих файлів, а не вирізаються з `Finora.swift`. Інші історичні `sed`-адаптери (Store, UI-суміжна логіка, OCR, налаштування) залишаються до наступних етапів.
- У модельних адаптерах використовуються справжні production категорії за замовчуванням, не дубльовані константи. Сценарії з власними категоріями як і раніше явно їх задають.
- Release gate (30 UI-сценаріїв) збережено.

## Межі

Локальна перевірка SwiftPM/Swift Linux не є Apple SDK. Потрібні Xcode, Vision, CryptoKit, Simulator і реальний пристрій. Цей Build не завершує всі етапи Architecture 2.0: Store actor, ChangeSet, асинхронний пошук, OCR-декомпозиція, XCTest для всіх інших доменів і незалежні ViewModel залишаються окремими задачами.
