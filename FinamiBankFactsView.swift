import SwiftUI

// Historical bank evidence, deliberately separate from the live outstanding balance.
struct FinamiBankFactsView: View {
    @EnvironmentObject private var s: Store
    let facts: FinamiBankContractSnapshot
    let masked: Bool
    private func visible(_ amount: Int64) -> String { masked ? "••••" : s.visibleMoney(amount) }
    var body: some View {
        Section("Дані банку на момент імпорту") {
            LabeledContent("Оновлено", value: facts.capturedAt.formatted(date: .abbreviated, time: .omitted))
            if let value = facts.firstContribution { LabeledContent("Перший внесок", value: visible(value)) }
            if let value = facts.totalBankFee { LabeledContent("Загальна комісія", value: visible(value)) }
            if let value = facts.monthlyBankFee { LabeledContent("Щомісячна комісія", value: visible(value)) }
            if let value = facts.paymentCount { LabeledContent("Кількість платежів", value: masked ? "••••" : String(value)) }
            if let value = facts.paidCount { LabeledContent("Сплачено на дату імпорту", value: masked ? "••••" : String(value)) }
            if let value = facts.nextAmount { LabeledContent("Внесок за даними банку", value: visible(value)) }
            if let value = facts.bankNextDue { LabeledContent("Дата внеску за даними банку", value: value.formatted(date: .abbreviated, time: .omitted)) }
            if let value = facts.opened { LabeledContent("Оформлено", value: value.formatted(date: .abbreviated, time: .omitted)) }
            if let value = facts.finalDue { LabeledContent("Кінцевий термін", value: value.formatted(date: .abbreviated, time: .omitted)) }
            Text("Довідкові дані. Поточний залишок і майбутні внески показано окремо. Комісія не списується автоматично.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
