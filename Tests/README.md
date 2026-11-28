# Каталог перевірок

Єдиний повний вхід: `bash Tests/run-regression.sh`. Першим запускається Swift Package (`swift test` окремо для швидкого локального прогону). XCTest використовує справжні моделі та індекс із `Finora/Domain/Ledger/`, без їх копіювання. Старі імена скриптів збережені для сумісності, але каталог організований за функціями. Один скрипт може охоплювати кілька тем; це не повна специфікація кожного assertion.

| Тема | Основні перевірки |
|---|---|
| Ledger, рахунки, фінансові звіти | `main.swift`, `check-model.sh`, `check-finami.sh`, `check-51.sh`, `check-52.sh`, `check-53.sh`, `check-build63-receipts.sh`, `check-stable-safety.sh` |
| Імпорт, виписки, звірка | `check-privat.sh`, `check-532.sh`, `check-54.sh`, `check-60.sh`, `check-61.sh`, `check-611.sh`, `check-62.sh` |
| Підтверджені графіки розстрочок | `check-installment-schedule.sh`, `check-51.sh`, `check-stable-safety.sh` |
| OCR та банківські макети | `check-preview4.sh`, `check-build60-ocr.sh`, `check-build64-brand-ocr.sh`, `check-build64-ocr-geometry.sh`, `check-build67-ocr.sh`, `check-build69-review.sh` |
| Автоматизація та дублі | `main.swift`, `check-model.sh`, `check-preview102.sh`, `check-preview103.sh`, `check-stable-safety.sh` |
| Збереження, відновлення, шифрування | `check-load-database.sh`, `check-storage-recovery.sh`, `check-encryption-macos.sh`, `check-stable-safety.sh` |
| Продуктивність | `check-build62-optimization.sh`, `check-build53.sh`, `check-stable-safety.sh` |
| Дизайн, налаштування, іконки | `check-design3-integration.sh`, `check-build51.sh`, `check-build52.sh`, `check-build55.sh`, `check-build56.sh`, `check-build63-layout.sh`, `check-build64-assets.py` |
| Експорт та планування | `check-export-report.sh`, `check-preview9.sh`, `check-preview10.sh`, `check-preview104.sh`, `check-preview105.sh` |
| Поведінка інтерфейсу | `UITests/FinamiUITests.swift` (30 сценаріїв; Xcode/iOS Simulator) |

Локальний прогін компілює Foundation-ядро та окремі виробничі методи через тестові адаптери; перевірка SwiftUI-синтаксису не є збіркою iOS. SHA-256/CryptoKit, реальний Vision та UI-тести виконуються в Apple-середовищі. Не вносити фінансові дані користувача в тестові фікстури. Нові журнали зберігати окремо від коду, у CI-артефактах.
