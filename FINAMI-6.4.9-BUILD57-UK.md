# Finami 6.4.9 — Build 57 · CI Regression Hotfix

## Причина
Журнал GitHub Actions `logs_124440587252.zip` для Build 56 показав збій `Tests/check-51.sh`: діапазон вилучення платіжної логіки завершувався лише перед `FinamiPaymentCard`, тому після Build 55 у тестовий `Models.swift` потрапляли `FinamiAllUpcomingPayments` та `FinamiAllPaymentsLink`. Тестовий модуль не імпортує SwiftUI. UI-тести та компіляція iOS у цьому запуску не виконувались.

## Зміни
- Екран повного списку платежів та посилання «Усього» перенесено до `Finora/FinamiUpcomingPaymentsView.swift` без зміни поведінки. Додано явний ініціалізатор екрана.
- Для вилучення платіжної логіки в `Tests/check-51.sh` використано явний маркер `END_PAYMENT_STORE_CORE` із перевіркою його наявності.
- Версія 6.4.9 / 57. Обидва архіви містять `.github/workflows/build.yml` і `simulator.yml` без змін.
- Логіка платежів, балансів, звірки та її UI-тест залишилися ідентичними Build 56.

## Перевірка
Повний локальний `bash Tests/run-regression.sh` завершився з кодом 0: 694 рядки PASS, включно з перевіркою синтаксису Swift. `check-51.sh`: 65 PASS; `check-build56.sh`: 10 PASS. Тест CryptoKit/CommonCrypto пропущено на Linux (потребує macOS). Компіляція iOS, фактичний Vision OCR та XCUITest не виконані в цьому середовищі. Остаточне підтвердження UI-звірки — наступний запуск GitHub Actions. Деталі: `FINAMI-6.4.9-TEST-RESULTS.txt`.
