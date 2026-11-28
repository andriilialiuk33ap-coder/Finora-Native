#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swift test --scratch-path "$tmp/swiftpm"
swiftc -warnings-as-errors -typecheck Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift
swiftc Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Tests/main.swift -o "$tmp/finami-core-tests"
"$tmp/finami-core-tests"
for test in check-model check-finami check-preview2 check-preview3 check-preview4 check-preview5 check-preview6 check-preview9 check-preview10 check-preview102 check-preview103 check-preview104 check-preview105 check-51 check-52 check-53 check-export-report check-532 check-54 check-privat check-60 check-61 check-611 check-62; do
  echo "=== $test ==="
  bash "Tests/$test.sh"
done
bash Tests/check-design3-integration.sh
bash Tests/check-build51.sh
bash Tests/check-build52.sh
bash Tests/check-build53.sh
bash Tests/check-build55.sh
bash Tests/check-build56.sh
bash Tests/check-build60-ocr.sh
bash Tests/check-build62-optimization.sh
bash Tests/check-build63-receipts.sh
bash Tests/check-build63-layout.sh
bash Tests/check-build64-brand-ocr.sh
bash Tests/check-build64-ocr-geometry.sh
bash Tests/check-build67-ocr.sh
bash Tests/check-build69-review.sh
python3 Tests/check-build64-assets.py
bash Tests/check-load-database.sh
bash Tests/check-storage-recovery.sh
bash Tests/check-stable-safety.sh
bash Tests/check-installment-schedule.sh
bash Tests/check-architecture-progress.sh
bash Tests/check-encryption-macos.sh
while IFS= read -r -d '' file; do swiftc -frontend -parse "$file"; done < <(find Finora UITests FinamiWidgets WidgetShared -name '*.swift' -print0)
echo 'PASS: Swift syntax (not iOS compilation)'
