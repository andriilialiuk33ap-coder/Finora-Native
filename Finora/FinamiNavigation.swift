import SwiftUI

struct FinamiAccountsBalance: View {
    @EnvironmentObject var s: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    private var prefs: AppearancePreferences { s.db.preferences ?? .init() }
    private func change(_ action: (inout AppearancePreferences) -> Void) {
        s.change { d in var p = d.preferences ?? .init(); action(&p); d.preferences = p }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Мої кошти").font(.headline)
                Spacer()
                Menu {
                    Button { change { $0.accountsLayout = "split" } } label: { Label("Дві половини", systemImage: "rectangle.split.2x1") }
                    Button { change { $0.accountsLayout = "full" } } label: { Label("Один спільний блок", systemImage: "rectangle.stack") }
                } label: { Label(prefs.accountsLayout == "full" ? "Один блок" : "Дві картки", systemImage: "rectangle.split.2x1").font(.caption.weight(.medium)).frame(minHeight: 44) }.accessibilityLabel("Вигляд балансу")
            }
            if prefs.accountsLayout == "full" || typeSize.isAccessibilitySize {
                VStack(spacing: 10) { metric(true); Divider(); metric(false) }.padding(14).modifier(FinamiCardStyle(tint: .teal))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    metric(true).padding(12).modifier(FinamiCardStyle(tint: .green))
                    metric(false).padding(12).modifier(FinamiCardStyle(tint: .blue))
                }
            }
        }
    }
    private func metric(_ own: Bool) -> some View {
        let hidden = s.privateAmounts || (own ? prefs.accountsHideOwn == true : prefs.accountsHideCredit == true)
        let tint: Color = own ? .green : .blue
        let key = own ? "own" : "credit"
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                FinamiIconTile(icon: own ? "wallet.pass.fill" : "creditcard.fill", tint: tint, side: 32)
                Spacer(minLength: 0)
                Button { change { p in if own { p.accountsHideOwn = !(p.accountsHideOwn ?? false) } else { p.accountsHideCredit = !(p.accountsHideCredit ?? false) } } } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye").frame(width: 44, height: 44)
                }.buttonStyle(.plain).disabled(s.privateAmounts).accessibilityLabel((hidden ? "Показати " : "Приховати ") + (own ? "власний баланс" : "кредитний баланс"))
            }
            Button { change { $0.accountsMode = key } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(own ? "Власні кошти" : "Кредитні кошти").font(.subheadline.weight(.medium))
                    Text(hidden ? "••••" : s.displayed(own ? s.totalOwnFunds : s.totalAvailableCredit)).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                    Text(own ? "Без кредиту" : "Доступний кредит").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FinamiOrderEditor: View {
    enum Target { case accounts, dashboard }
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    var target: Target
    var closeButton = true
    private var accounts: [Account] { finamiOrderedAccounts(s.db.accounts) }
    private var blocks: [DashboardItem] { DashboardItem.merged(s.db.dashboard) }
    var body: some View {
        List {
            if target == .accounts {
                Section("Закріплені") { accountRows(accounts.filter { $0.cardOptions?.pinned == true }) }
                Section("Інші рахунки") { accountRows(accounts.filter { $0.cardOptions?.pinned != true }) }
                Section { Text("Порядок спільний для головної та рахунків. Закріплені залишаються зверху. Перетягни рядок або натисни стрілку.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Section("Видимі блоки") { blockRows(blocks.filter(\.enabled)) }
                Section { Text("Перетягни блок або скористайся стрілками. Приховані блоки та їхні налаштування зберігаються.").font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle(target == .accounts ? "Порядок рахунків" : "Порядок блоків")
        .environment(\.editMode, .constant(.active))
        .toolbar { if closeButton { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } } }
    }
    private func move(_ ids: [String], _ index: Int, _ offset: Int, save: ([String]) -> Void) {
        let destination = index + offset
        guard ids.indices.contains(destination) else { return }
        var copy = ids; copy.swapAt(index, destination); save(copy)
    }
    private func arrows(_ ids: [String], _ index: Int, save: @escaping ([String]) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { move(ids, index, -1, save: save) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }.disabled(index == 0).accessibilityLabel("Перемістити вище")
            Button { move(ids, index, 1, save: save) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.disabled(index == ids.count-1).accessibilityLabel("Перемістити нижче")
        }.buttonStyle(.borderless)
    }
    private func saveAccounts(_ ids: [String]) {
        let order = finamiReorderSubset(accounts.map(\.id), orderedSubset: ids)
        s.change { d in
            let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
            for i in d.accounts.indices { var opts = d.accounts[i].cardOptions ?? .init(); opts.order = ranks[d.accounts[i].id]; d.accounts[i].cardOptions = opts }
        }
    }
    private func saveBlocks(_ ids: [String]) {
        s.change { d in
            let all = DashboardItem.merged(d.dashboard)
            let lookup = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            d.dashboard = finamiReorderSubset(all.map(\.id), orderedSubset: ids).compactMap { lookup[$0] }
        }
    }
    @ViewBuilder private func accountRows(_ values: [Account]) -> some View {
        let ids = values.map(\.id)
        if values.isEmpty { Text("Немає рахунків").foregroundStyle(.secondary) }
        ForEach(Array(values.enumerated()), id: \.element.id) { index, a in
            HStack { VStack(alignment: .leading) { Text(a.name); Text(a.typeName).font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0); arrows(ids, index, save: saveAccounts) }
        }.onMove { from, to in var copy = ids; copy.move(fromOffsets: from, toOffset: to); saveAccounts(copy) }
    }
    @ViewBuilder private func blockRows(_ values: [DashboardItem]) -> some View {
        let ids = values.map(\.id)
        if values.isEmpty { Text("Немає видимих блоків").foregroundStyle(.secondary) }
        ForEach(Array(values.enumerated()), id: \.element.id) { index, item in
            HStack { Label(item.kind.title, systemImage: item.kind.icon); Spacer(minLength: 0); arrows(ids, index, save: saveBlocks) }
        }.onMove { from, to in var copy = ids; copy.move(fromOffsets: from, toOffset: to); saveBlocks(copy) }
    }
}
