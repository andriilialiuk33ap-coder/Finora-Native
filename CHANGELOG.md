## Build 92 — development candidate (6.4.41)

Based on B89 Recovery Iteration 2 CI Fix. This is a partial implementation of the Build 90–92 roadmap, not a completed production release.

- PrivatBank transaction detail parser: signed payment, separate balance, status, comma-separated timestamp, masked card suffix, conservative bank/account matching.
- YouTube Premium monthly subscription suggestion with explicit confirmation; creates one expense and linked payment history in the same database mutation. Existing subscriptions are not duplicated or advanced automatically. Date and account remain subject to confirmation.
- History global privacy override, linked hidden subscription masking, amount-sort fallback, CSV amount redaction and conservative report export masking. This is not a full privacy/security audit; free-text descriptions and explicit backup exports can contain financial data.
- Bounded LRU caches for dashboard months/metrics, history and account activity. Broad invalidation is retained for safety.
- Recovery account name selectors and automatic loading of the operation identified by validation.
- Added transaction OCR regression script using a manually transcribed layout with synthetic card identifiers, integrated into CI. No actual private screenshot included.

Local verification: 13 new transaction OCR checks, 16 history/privacy checks, existing Build 60, 64 brand and 67 OCR scripts, and syntax parsing of changed Swift files. Apple Vision on actual screenshot, full iOS build, UI tests, and real database migration remain pending. No claim of fixing the previously reported one-cent discrepancy. Cross-process storage, full background validation/serialization, installment currency, complete identity engine and full redesign are not implemented here.

# Changelog — Finami Stable

## 6.4.41 (Build 89) — Ledger Integrity

- Спільна перевірка згрупованих переказів, рахунків, валют, звірки та зв’язків повернень на всіх шляхах запису/завантаження.
- Єдина функція руху коштів для поточного й історичного індексів; контроль дати та суми звірки при інвалідації.
- Кредитні корекції не застосовуються після зміни ревізії або рахунку; суми показуються в нативній валюті з урахуванням приватності.
- Додані XCTest і сценарії валідатора/реального завантаження бази. Формат JSON, App Group та шляхи даних не змінені.

## 6.4.40 (Build 88) — Architecture Candidate, накопичувальні зміни від Build 80

- Довідкові банківські метадані розстрочок, консервативний OCR парсинг і окремий Vision-сервіс.
- Фоновий пошук із контролем ревізії та скасуванням; фоновий атомарний запис великих імпортів/масових змін з резервуванням запису.
- Точне представлення копійок, захист парсингу виписок і черги автоматизації, версійність обміну з віджетами.
- Декомпозиція IzanamiFeatures, спільні константи геометрії дизайну, додаткові регресії.
- Не є завершенням усіх запланованих етапів: див. [межі реалізації](docs/stable/build88-architecture-candidate.md).

## 6.4.32 (Build 80) — Installment Engine

- Окремий опційний підтверджений залишок банківського графіка; активація лише з явною перевіркою суми й першої дати.
- Часткове та повне погашення, календар, місячний план, прогноз, експорт і відновлення графіка після відв’язування оплати.
- Нульові рядки зберігаються як доказ імпорту, не як списання. Старі графіки залишаються довідковими.
- Валідація активного графіка при читанні/записі/відновленні; захист від повторного імпорту архівного скриншота.
- 30 нових цільових перевірок, див. [деталі](docs/stable/build80-installment-engine.md).

## 6.4.31 (Build 79) — Test Foundation / перша декомпозиція

- Розділено `Finora.swift` на доменні моделі, Store, файловий документ, головний екран, рахунки, меню, бюджети, розстрочки, планування, налаштування та графік. Тіла декларацій перенесено без змін.
- Swift Package та XCTest компілюють спільні виробничі файли моделей і ledger-індексу; 8 сценаріїв. Старі shell-тести збережено.
- Модельні адаптери shell-тестів використовують цілі доменні файли замість вирізання з `Finora.swift`. Перевірка синтаксису рекурсивна.
- Формати бази, bundle ID, App Group, дизайн, фінансова поведінка та release gate без змін. Xcode/Simulator ще потрібні.

## 6.4.30 (Build 78) — накопичувальний RC, етапи 72–78

- Фінансовий валідатор перед публікацією прочитаної бази, мутацією та імпортом/відновленням; перевірка діапазонів, сукупного обсягу, дат та унікальності ідентифікаторів.
- Захист від невалідного переходу дати підписки; адресація платежу за ID та видом.
- Індекси фінансових даних не скидаються при записі лише appearance sidecar. Перевірка ревізії для фонової обробки залишається.
- Читання періодичної черги поза UI-актором; валідація UUID, суми, валюти, розміру файлу та символічних посилань; збереження непрохідних подій для повторної спроби.
- QA-фікстури винесено в DEBUG-файл, документацію організовано; старі скрипти збережено, щоб не пошкодити регресії.
- Перевірка фінансових меж у діагностиці; тест приватності підписки при відкритті з глобального пошуку; захист історії оплат і віджетів.
- Release gate перевіряє не лише статус команди Xcode, але й кількість фактично пройдених/пропущених/невдалих UI-тестів.
- Без нових фінансових функцій або змін погодженого дизайну. Не змінено формати локальних вкладень та шифрування Build 71.

## 6.4.23 (Build 71) — Storage & Recovery

Окремі файли чеків, SHA-256, міграція, переносні резервні копії, снапшоти з політикою збереження, карантин, єдиний workflow. [Деталі](docs/stable/build71-storage-recovery.md).

## 6.4.22 (Build 70) — Financial Consistency I

Цілісність зв’язків платежів, облік комісій, чисті та валові витрати, наскрізні фінансові регресії. [Деталі](docs/history/releases/FINAMI-6.4.22-STABILITY-UK.md).

## 6.4.21 (Build 69) і попередні

[Архів нотаток](docs/history/releases/), [історичні результати](docs/history/test-results/).
