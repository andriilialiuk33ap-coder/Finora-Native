#!/usr/bin/env bash
# Source from repository root; use actual financial model definitions.
finami_safety_models() {
  echo 'import Foundation'
    cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift Finora/Domain/PaymentModels.swift Finora/Domain/FinancialRecords.swift Finora/Domain/Database.swift
  sed -n '/^enum SubscriptionPeriod:/,/^func currencyMoney/p' Finora/IzanamiFeatures.swift | sed '$d'
  grep '^struct ForecastPreferences:' Finora/IzanamiFeatures.swift
  cat <<'SWIFT'
struct DashboardItem: Codable {}
struct AppearancePreferences: Codable { var theme = "base" }
struct CapturePreferences: Codable {}
struct PersonalReminder: Codable { var id = UUID().uuidString; var linkedID: String? = nil }
SWIFT
}
