#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -warnings-as-errors -typecheck Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Finora/FinamiScanCore.swift
swiftc Finora/BankCore.swift Finora/MoneyCore.swift Finora/AutomationCore.swift Tests/main.swift -o "$tmp/finami-core-tests"
"$tmp/finami-core-tests"
for test in check-model check-finami check-preview2 check-preview3 check-preview4 check-preview5 check-preview6 check-preview9 check-preview10 check-preview102 check-preview103 check-preview104; do
  echo "=== $test ==="
  bash "Tests/$test.sh"
done
bash Tests/check-encryption-macos.sh
for file in Finora/*.swift UITests/*.swift; do swiftc -frontend -parse "$file"; done
echo 'PASS: Swift syntax (not iOS compilation)'
