# Finami — 6.4.41 (Build 89, Ledger Integrity)

Приватний локальний фінансовий застосунок для iPhone, SwiftUI, iOS 16+. Рахунки, операції, розстрочки, підписки, бюджети, звіти, OCR, автоматизація та резервні копії. Aurora Balance і Fusion Crystal збережено.

## Розробка й тести

- `Finora/` — основний застосунок; `WidgetShared/` і `FinamiWidgets/` — віджети.
- `swift test` — ізольовані XCTest фінансових моделей та індексу, на тих самих Swift-файлах, що й iOS.
- `bash Tests/run-regression.sh` — фінансові, файлові та інші локальні регресії; на Apple SDK додатково перевіряється шифрування.
- `xcodegen generate` — генерація Xcode-проєкту з `project.yml`.
- GitHub Actions: **Test Finami on iOS Simulator**. За потреби вибрати `Build unsigned IPA after all tests pass`. Обидва workflows використовують однаковий release gate. IPA без підпису потребує окремого підписування.
- Результати CI: `Finami-Simulator-Results`, включно з `.xcresult`, логами та скриншотами; `Finami-IPA-Tested` лише після проходження gate.

## Важливо щодо даних

Зберігати резервні копії перед оновленням. З Build 71 локальна база може посилатися на окремі JPEG; для перенесення потрібен повний JSON або зашифрована копія. Старі версії не повинні відкривати новий локальний формат. Не змінювати bundle ID, App Group та існуючі шляхи даних.

## Документація

- [CHANGELOG](CHANGELOG.md) — зміни релізів стабілізації.
- [Build 89: фінансова цілісність та межі перевірки](docs/stable/build89-ledger-integrity.md).
- [Build 88: накопичувальний кандидат та межі перевірки](docs/stable/build88-architecture-candidate.md).
- [Build 80: підтверджені банківські графіки](docs/stable/build80-installment-engine.md).
- [Build 79: декомпозиція та тестова основа](docs/stable/build79-test-foundation.md).
- [Build 78: стан аудиту та release gate](docs/stable/build78-release-candidate.md).
- [Build 71: збереження та відновлення](docs/stable/build71-storage-recovery.md).
- [CI](docs/CI-UK.md), [специфікація дизайну](docs/FINAMI-DESIGN-3.0-SPEC-UK.md).
- [Архів попереднього README](docs/history/README-before-build78.md), [історія релізів](docs/history/releases/), [старі журнали тестування](docs/history/test-results/).
- [Каталог тестів за темами](Tests/README.md).

**Статус:** проміжна архітектурна збірка, а не підтверджений стабільний реліз. Остаточні результати Xcode, Vision, CryptoKit, XCUITest та тестів на iPhone не замінюються Linux-регресіями. Не передавати реальну фінансову базу, токени чи банківські реквізити до репозиторію.
