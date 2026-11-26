import SwiftUI
import WidgetKit

@MainActor enum FinamiWidgetBridge {
    static func update(store: Store, enabled: Bool, locked: Bool) {
        guard let url = FinamiWidgetSnapshot.url() else { return }
        guard enabled, !locked, !store.privateAmounts, store.storageHealthy, !store.loading else {
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) } catch {
                    // If removal failed, atomically invalidate content when possible.
                    try? Data().write(to: url, options: [.atomic, .completeFileProtection])
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        let own = store.includedAccounts.filter { $0.code == "UAH" && $0.hideAmounts != true }.reduce(Int64(0)) { $0 + store.ownFunds($1) }
        let payment = store.upcomingPayments.first
        let snapshot = FinamiWidgetSnapshot(ownUAH: own, dueAmount: payment?.amount, dueCurrency: payment?.currency, dueDate: payment?.date, updated: Date())
        if let old = FinamiWidgetSnapshot.read(), old.ownUAH == snapshot.ownUAH, old.dueAmount == snapshot.dueAmount, old.dueCurrency == snapshot.dueCurrency, old.dueDate == snapshot.dueDate, Date().timeIntervalSince(old.updated) < 3600 { return }
        do {
            try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
            WidgetCenter.shared.reloadAllTimelines()
        } catch { /* Widgets are optional. Never block the ledger. */ }
    }
}
struct FinamiWidgetsSettings: View {
    @EnvironmentObject private var s: Store
    @AppStorage("finami.widgets.shareAmounts") private var share = false
    @AppStorage("lockEnabled") private var lockEnabled = false
    var body: some View {
        Form {
            Section("Віджети iPhone") {
                Label("Швидкі дії · додати витрату", systemImage: "plus.circle")
                Label("Найближчий платіж", systemImage: "calendar")
                Label("Власні кошти · UAH", systemImage: "wallet.pass")
                Text("Затисни головний екран iPhone → Додати віджет → Finami. Доступність залежить від підпису IPA та підтримки розширень.").font(.caption)
            }
            Section("Приватність") {
                Toggle("Дозволити суми у віджетах", isOn: $share).disabled(FinamiWidgetSnapshot.url() == nil || lockEnabled)
                LabeledContent("Спільний контейнер", value: FinamiWidgetSnapshot.url() == nil ? "Недоступний" : "Доступний")
                Text("Без App Groups віджети відкривають відповідні розділи без показу сум. З увімкненим Face ID або приховуванням сум фінансова копія видаляється; iOS може оновити вже намальований віджет із затримкою. Не вмикай показ сум, якщо потрібна абсолютна приватність.").font(.caption)
            }
        }.navigationTitle("Віджети").onChange(of: share) { value in FinamiWidgetBridge.update(store:s,enabled:value,locked:lockEnabled) }
    }
}
