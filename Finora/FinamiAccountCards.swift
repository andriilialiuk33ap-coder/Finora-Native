import SwiftUI
import PhotosUI
import UIKit
import ImageIO

// These identifiers are stored as strings to allow older data and future styles.
private enum HomeAccountStyle: String, CaseIterable, Identifiable {
    case premium, detailed, compact, physical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .premium: return "Комбінований Premium"
        case .detailed: return "Детальний банківський"
        case .compact: return "Компактний"
        case .physical: return "Банківська картка"
        }
    }
}
private enum HomeAccountRight: String, CaseIterable, Identifiable {
    case art, photo, expenses, credit, actions, last, count, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .art: return "Ілюстрація рахунку"
        case .photo: return "Власна фотографія"
        case .expenses: return "Витрати за місяць"
        case .credit: return "Кредитний ліміт"
        case .actions: return "Швидкі дії"
        case .last: return "Остання операція"
        case .count: return "Кількість операцій"
        case .none: return "Без правої частини"
        }
    }
}
private enum HomeAccountField: String, CaseIterable, Identifiable {
    case own, limit, used, available, currency, type, income, expenses, last, updated, count, actions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .own: return "Власні кошти"
        case .limit: return "Кредитний ліміт"
        case .used: return "Використано кредиту"
        case .available: return "Доступний кредит"
        case .currency: return "Валюта рахунку"
        case .type: return "Тип рахунку"
        case .income: return "Доходи за місяць"
        case .expenses: return "Витрати за місяць"
        case .last: return "Остання операція"
        case .updated: return "Дата останньої операції"
        case .count: return "Кількість операцій"
        case .actions: return "Швидкі дії"
        }
    }
    static let defaults = [own, limit, used, available, currency, type, expenses, last, updated, actions].map(\.rawValue)
}
private func accountStyle(_ value: String?) -> HomeAccountStyle { HomeAccountStyle(rawValue: value ?? "") ?? .premium }
private func accountRight(_ value: String?, style: HomeAccountStyle) -> HomeAccountRight {
    HomeAccountRight(rawValue: value ?? "") ?? (style == .compact ? .none : style == .detailed ? .expenses : .art)
}
private func accountArtIcon(_ a: Account) -> String {
    a.accountType == "cash" || a.id == cash ? "banknote.fill" : a.isCredit || a.accountType == "debit" ? "creditcard.fill" : "wallet.pass.fill"
}
private func accountTint(_ a: Account, fallback: Color) -> Color {
    if let accent = a.cardOptions?.accent, let theme = IzanamiTheme.all.first(where: { $0.name == accent }) { return theme.color }
    let name = (a.bankName ?? a.name).lowercased()
    if name.contains("пумб") || name.contains("pumb") { return .pink }
    if name.contains("mono") || name.contains("моно") { return .gray }
    if name.contains("приват") || name.contains("privat") || name.contains("а-банк") || name.contains("а банк") || name.contains("abank") || a.id == cash || a.accountType == "cash" { return .green }
    return fallback
}

// An original local illustration: a bank-card stack or a cash wallet.
private struct HomeAccountArt: View {
    var account: Account
    var tint: Color
    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.12)).frame(width: 90, height: 90)
            Circle().strokeBorder(tint.opacity(0.12), lineWidth: 1).frame(width: 106, height: 106)
            if account.id == cash || account.accountType == "cash" {
                RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.28)).frame(width: 70, height: 40).rotationEffect(.degrees(-15)).offset(y: -13)
                RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 92, height: 58).rotationEffect(.degrees(5))
                Image(systemName: "banknote.fill").font(.system(size: 28, weight: .medium)).foregroundStyle(.primary)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.30)).frame(width: 89, height: 56).rotationEffect(.degrees(-15)).offset(x: -6, y: -10)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [tint.opacity(0.65), tint.opacity(0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(alignment: .leading, spacing: 7) {
                        Image(systemName: "creditcard.fill").font(.system(size: 15, weight: .medium))
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.75)).frame(width: 18, height: 12)
                        HStack(spacing: 3) { Capsule().fill(Color.white.opacity(0.65)).frame(width: 19, height: 3); Spacer(); Circle().fill(Color.white.opacity(0.55)).frame(width: 9); Circle().fill(Color.white.opacity(0.35)).frame(width: 9) }
                    }.padding(8).foregroundStyle(.white)
                }.frame(width: 95, height: 60).rotationEffect(.degrees(8)).offset(x: 5, y: 7)
            }
        }.scaleEffect(0.80).frame(width: 92, height: 82).accessibilityHidden(true)
    }
}

struct FinamiHomeAccountCard: View {
    @EnvironmentObject private var s: Store
    @Environment(\.finamiMask) private var blockMasked
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var accountID: String
    var date: Date
    var fallbackTint: Color
    var mode: String = "all"
    var onAccountsScreen = false
    var dashboardSize: DashboardSize? = nil
    @State private var route: Route?
    private enum Route: Identifiable {
        case settings, history, reconcile, edit(Account), operation(Operation)
        var id: String { switch self { case .settings: return "settings"; case .history: return "history"; case .reconcile: return "reconcile"; case .edit: return "edit"; case .operation: return "operation" } }
    }
    var body: some View {
        if let a = s.db.accounts.first(where: { $0.id == accountID }) {
            let variant = s.db.preferences?.designAccountStyle(for: a.id)
            let legacy = accountStyle(a.cardOptions?.style ?? s.db.preferences?.homeAccountLayout)
            let preferredStyle: HomeAccountStyle = variant == "bankingSplit" || variant == "creditRing" ? .detailed : variant == "auroraCard" ? .physical : legacy
            let style: HomeAccountStyle = dashboardSize == .small ? .compact : preferredStyle
            let selectedRight: HomeAccountRight = dashboardSize == .small ? .none : accountRight(a.cardOptions?.right ?? s.db.preferences?.homeAccountRight, style: style)
            let right: HomeAccountRight = mode == "own" && selectedRight == .credit ? .art : selectedRight
            let excludedFields: Set<String> = mode == "own" ? ["limit", "used", "available"] : mode == "credit" ? ["own"] : []
            let preferredFields = Set(a.cardOptions?.fields ?? s.db.preferences?.homeAccountFields ?? HomeAccountField.defaults).subtracting(excludedFields)
            let fields = dashboardSize == .small ? preferredFields.intersection(["own", "limit", "used", "available", "currency", "type"]) : preferredFields
            let activity = s.accountActivity(a, month: date)
            let tint = accountTint(a, fallback: fallbackTint)
            card(a, style: style, right: right, fields: fields, activity: activity, tint: tint, variant: variant)
                .sheet(item: $route) { route in
                    switch route {
                    case .settings: NavigationStack { FinamiHomeAccountSettings(accountID: a.id, closeButton: true) }
                    case .history: NavigationStack { HomeAccountHistory(accountID: a.id, blockMasked: isMasked(a)) }
                    case .reconcile: NavigationStack { FinamiBalanceView(initialMode:"anchor",accountID:a.id).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Готово") { self.route=nil } } } }
                    case .edit(let account): AccountEditor(a: account)
                    case .operation(let operation): OpEditor(original: operation)
                    }
                }
        }
    }
    private func baseMask(_ a: Account) -> Bool { blockMasked || s.privateAmounts || a.hideAmounts == true }
    private func isMasked(_ a: Account, field: String? = nil) -> Bool {
        if baseMask(a) { return true }
        guard onAccountsScreen else { return false }
        if field == "own" { return s.db.preferences?.accountsHideOwn == true }
        if field == "credit" { return s.db.preferences?.accountsHideCredit == true }
        return s.db.preferences?.accountsHideOwn == true || s.db.preferences?.accountsHideCredit == true
    }
    private func amount(_ n: Int64, _ a: Account, field: String? = nil) -> String { isMasked(a, field: field) ? "****" : currencyMoney(n, a.code) }
    private func start(_ kind: Kind, _ a: Account) { route = .operation(Operation(kind: kind, category: "Без категорії", account: a.id, entryCurrency: a.code)) }
    private func toggleMask(_ a: Account) {
        s.change { d in if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { d.accounts[i].hideAmounts = !(d.accounts[i].hideAmounts ?? false) } }
    }
    private func header(_ a: Account, fields: Set<String>, tint: Color) -> some View {
        HStack(spacing: 8) {
            FinamiIconTile(icon: accountArtIcon(a), tint: tint, side: 38)
            Button { route = .history } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    let info = [fields.contains("type") ? a.typeName : nil, fields.contains("currency") ? a.code : nil].compactMap { $0 }.joined(separator: " · ")
                    if !info.isEmpty { Text(info).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("Історія: " + a.name)
            if a.cardOptions?.pinned == true { Image(systemName: "pin.fill").font(.caption).foregroundStyle(tint).accessibilityLabel("Закріплений") }
            Button { toggleMask(a) } label: { Image(systemName: baseMask(a) ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.plain).disabled(blockMasked || s.privateAmounts).accessibilityLabel("Приховати або показати суми рахунку")
            Menu {
                Button { route = .settings } label: { Label("Оформлення картки", systemImage: "paintpalette") }
                Button { route = .history } label: { Label("Історія операцій", systemImage: "clock") }
                if a.code == "UAH" { Button { route = .reconcile } label: { Label("Звірити баланс",systemImage:"checkmark.circle") } }
                Button { route = .edit(a) } label: { Label("Редагувати рахунок / залишок", systemImage: "pencil") }
                Button { s.change { d in if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { var o = d.accounts[i].cardOptions ?? .init(); o.pinned = !(o.pinned ?? false); d.accounts[i].cardOptions = o } } } label: { Label(a.cardOptions?.pinned == true ? "Відкріпити" : "Закріпити зверху", systemImage: "pin") }
                Button { s.change { d in if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { if onAccountsScreen { d.accounts[i].hiddenInAccounts = true } else { d.accounts[i].hiddenInOverview = true } } } } label: { Label(onAccountsScreen ? "Приховати у рахунках" : "Приховати на головній", systemImage: "eye.slash") }
            } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Дії рахунку")
        }
    }
    private func card(_ a: Account, style: HomeAccountStyle, right: HomeAccountRight, fields: Set<String>, activity: AccountActivity, tint: Color, variant: String?) -> some View {
        VStack(alignment: .leading, spacing: dashboardSize == .small ? 6 : dashboardSize == .large ? 15 : style == .compact ? 8 : 12) {
            header(a, fields: fields, tint: tint)
            if variant == "auroraCard" && dashboardSize != .small {
                HStack { Image(systemName: "creditcard.fill").font(.title3); Spacer(); Text(isMasked(a) ? "••••" : a.lastFour.map { "•••• " + $0 } ?? a.code).font(.caption.monospacedDigit()) }
                    .foregroundStyle(tint).padding(10).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(isMasked(a))
            }
            if fields.contains("own") || right != .none {
                if dynamicTypeSize.isAccessibilitySize || right == .none || !fields.contains("own") {
                    VStack(alignment: .leading, spacing: 12) {
                        if fields.contains("own") { own(a) }
                        rightPanel(right, a: a, activity: activity, tint: tint)
                    }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        own(a).frame(maxWidth: .infinity, alignment: .leading)
                        rightPanel(right, a: a, activity: activity, tint: tint).frame(width: right == .art ? 92 : 116)
                    }
                }
            }
            if a.isCredit && mode != "own" { creditFields(a, fields: fields, right: right, style: style) }
            if variant == "creditRing" && a.isCredit && mode != "own" && fields.contains("used") && fields.contains("limit"), let fraction = FinamiDesignPolicy.creditFraction(used: s.debt(a), limit: a.limit, masked: isMasked(a, field: "credit")) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(tint.opacity(0.15), lineWidth: 7)
                        Circle().trim(from: 0, to: CGFloat(fraction)).stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text(Double(s.debt(a)) / Double(a.limit), format: .percent.precision(.fractionLength(0))).font(.caption.bold()).monospacedDigit()
                    }.frame(width: 64, height: 64).accessibilityHidden(true)
                    Text("Використання кредитного ліміту").font(.caption).foregroundStyle(.secondary)
                }.accessibilityLabel("Використання кредитного ліміту").accessibilityValue(Text(Double(s.debt(a)) / Double(a.limit), format: .percent.precision(.fractionLength(0))))
            }
            activityFields(a, fields: fields, right: right, activity: activity, style: style)
            if fields.contains("actions") && right != .actions { quickActions(a, vertical: dynamicTypeSize.isAccessibilitySize) }
        }
        .padding(dashboardSize == .small ? 9 : dashboardSize == .large ? 20 : style == .compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if variant == "auroraCard" && s.db.preferences?.designLowEffects != true {
                FinamiAccountSurface(tint: tint, radius: 24).overlay { RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [tint.opacity(0.17), .clear, tint.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)) }
            } else if style == .physical || style == .premium {
                FinamiAccountSurface(tint: tint, radius: 24)
            } else { FinamiAccountSurface(tint: tint, radius: 16) }
        }
        .clipShape(RoundedRectangle(cornerRadius: s.db.preferences?.designRadius.map { CGFloat(FinamiDesignPolicy.radius($0)) } ?? (style == .physical || style == .premium ? 24 : 16)))
        .contextMenu {
            Button { route = .settings } label: { Label("Оформлення", systemImage: "paintpalette") }
            Button { route = .history } label: { Label("Історія", systemImage: "clock") }
            Button { start(.expense, a) } label: { Label("Нова витрата", systemImage: "minus.circle") }
        }
    }
    private func own(_ a: Account) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Власні кошти").font(.caption).foregroundStyle(.secondary)
            Text(amount(s.ownFunds(a), a, field: "own")).font(.system(dashboardSize == .small ? .title3 : dashboardSize == .large ? .largeTitle : .title, design: .rounded).weight(.semibold)).monospacedDigit().lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.72)
            if a.isCredit { Text("Без кредиту").font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func metric(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(tint).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.70)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private func rightPanel(_ right: HomeAccountRight, a: Account, activity: AccountActivity, tint: Color) -> some View {
        switch right {
        case .art: HomeAccountArt(account: a, tint: tint)
        case .photo:
            if isMasked(a) { HomeAccountArt(account: a, tint: tint) }
            else if let data = a.cardOptions?.photo, let image = FinamiImageCache.shared.image(data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 110, height: 92).clipped().clipShape(RoundedRectangle(cornerRadius: 13)).accessibilityLabel("Фото рахунку")
            } else { Button { route = .settings } label: { VStack(spacing: 4) { HomeAccountArt(account: a, tint: tint); Text("Додати фото").font(.caption2) } }.buttonStyle(.plain) }
        case .expenses: panel { metric("Витрати за місяць", amount(activity.spending, a), tint: .primary) }
        case .credit:
            if a.isCredit { panel { metric("Кредитний ліміт", amount(a.limit, a, field: "credit")) } }
            else { HomeAccountArt(account: a, tint: tint) }
        case .actions: quickActions(a, vertical: true)
        case .last: panel { if let o = activity.history.first { metric("Остання операція", amount(activity.signed(o), a)); Text(o.note.isEmpty ? o.category : o.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2) } else { Text("Немає операцій").font(.caption).foregroundStyle(.secondary) } }
        case .count: panel { metric("Операцій за місяць", String(activity.count)) }
        case .none: EmptyView()
        }
    }
    @ViewBuilder private func creditFields(_ a: Account, fields: Set<String>, right: HomeAccountRight, style: HomeAccountStyle) -> some View {
        let showLimit = fields.contains("limit") && right != .credit
        let showUsed = fields.contains("used")
        let showAvailable = fields.contains("available")
        if showLimit || showUsed || showAvailable {
            Divider()
            if showLimit { metric("Кредитний ліміт", amount(a.limit, a, field: "credit")) }
            if showUsed || showAvailable {
                if style == .compact || dynamicTypeSize.isAccessibilitySize || !showUsed || !showAvailable {
                    VStack(spacing: 8) {
                        if showUsed { panel { metric("Використано кредиту", amount(s.debt(a), a, field: "credit"), tint: .orange) } }
                        if showAvailable { panel { metric("Доступний кредит", amount(s.unusedCredit(a), a, field: "credit"), tint: .teal) } }
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        panel { metric("Використано", amount(s.debt(a), a, field: "credit"), tint: .orange) }
                        panel { metric("Доступний кредит", amount(s.unusedCredit(a), a, field: "credit"), tint: .teal) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func activityFields(_ a: Account, fields: Set<String>, right: HomeAccountRight, activity: AccountActivity, style: HomeAccountStyle) -> some View {
        let showIncome = fields.contains("income")
        let showExpenses = fields.contains("expenses") && right != .expenses
        if showIncome || showExpenses {
            if showIncome && showExpenses && !dynamicTypeSize.isAccessibilitySize && style != .compact {
                HStack(alignment: .top, spacing: 8) {
                    panel { metric("Доходи за місяць", amount(activity.income, a), tint: .teal) }
                    panel { metric("Витрати за місяць", amount(activity.spending, a)) }
                }
            } else {
                if showIncome { panel { metric("Доходи за місяць", amount(activity.income, a), tint: .teal) } }
                if showExpenses { panel { metric("Витрати за місяць", amount(activity.spending, a)) } }
            }
        }
        if fields.contains("count") && right != .count { metric("Операцій за місяць", String(activity.count)) }
        if let last = activity.history.first {
            if fields.contains("last") && right != .last {
                Button { route = .history } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Остання операція").font(.caption).foregroundStyle(.secondary)
                        Text(last.note.isEmpty ? last.category : last.note).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                        Text(amount(activity.signed(last), a)).font(.headline).monospacedDigit().foregroundStyle(.primary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            if fields.contains("updated") { Text("Останній запис: " + last.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
        } 
    }
    private func action(_ kind: Kind, _ label: String, _ icon: String, _ a: Account) -> some View {
        Button { start(kind, a) } label: {
            VStack(spacing: 4) { Image(systemName: icon).font(.body.weight(.medium)); Text(label).font(.caption2).fixedSize(horizontal: false, vertical: true) }
                .frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 3).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(label + " — " + a.name)
            .disabled(kind == .transfer && s.db.accounts.count < 2)
    }
    @ViewBuilder private func quickActions(_ a: Account, vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 5) { action(.expense, "Витрата", "minus.circle", a); action(.income, "Дохід", "plus.circle", a); action(.transfer, "Переказ", "arrow.left.arrow.right", a) }
        } else {
            HStack(spacing: 5) { action(.expense, "Витрата", "minus.circle", a); action(.income, "Дохід", "plus.circle", a); action(.transfer, "Переказ", "arrow.left.arrow.right", a) }
        }
    }
}

// General defaults and sorting. Hidden accounts remain available here.
struct FinamiHomeAccountsSettings: View {
    @EnvironmentObject private var s: Store
    private var accounts: [Account] { finamiOrderedAccounts(s.db.accounts) }
    private func preference<T>(_ key: WritableKeyPath<AppearancePreferences, T?>, fallback: T) -> Binding<T> {
        Binding(get: { (s.db.preferences ?? .init())[keyPath: key] ?? fallback }, set: { value in s.changeAppearance { p in p[keyPath: key] = value } })
    }
    private func field(_ field: HomeAccountField) -> Binding<Bool> {
        Binding(get: { (s.db.preferences?.homeAccountFields ?? HomeAccountField.defaults).contains(field.rawValue) }, set: { enabled in
            s.changeAppearance { p in var values = p.homeAccountFields ?? HomeAccountField.defaults; values.removeAll { $0 == field.rawValue }; if enabled { values.append(field.rawValue) }; p.homeAccountFields = values }
        })
    }
    var body: some View {
        List {
            Section("Загальний стиль") {
                FinamiComponentStylePicker(component: "accounts", title: "Design 3.0")
                Picker("Шаблон", selection: Binding(get: { accountStyle(s.db.preferences?.homeAccountLayout).rawValue }, set: { v in s.changeAppearance { p in p.homeAccountLayout = v } })) {
                    ForEach(HomeAccountStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Права частина", selection: preference(\.homeAccountRight, fallback: "")) {
                    Text("За шаблоном").tag(""); ForEach(HomeAccountRight.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text("Права частина налаштовується окремо. Якщо показник вибраний праворуч, він не дублюється нижче.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Показники за замовчуванням") { ForEach(HomeAccountField.allCases) { f in Toggle(f.title, isOn: field(f)) } }
            Section("Закріплені") { accountRows(accounts.filter { $0.cardOptions?.pinned == true }, pinned: true) }
            Section("Інші рахунки") { accountRows(accounts.filter { $0.cardOptions?.pinned != true }, pinned: false) }
            Section { Text("Натисни «Редагувати», щоб змінити порядок у кожній групі. Персональне оформлення має пріоритет над загальними налаштуваннями. Історія й залишки не змінюються.").font(.caption) }
        }.navigationTitle("Мої рахунки").toolbar { EditButton() }
    }
    @ViewBuilder private func accountRows(_ rows: [Account], pinned: Bool) -> some View {
        if rows.isEmpty { Text("Немає рахунків").foregroundStyle(.secondary) }
        ForEach(rows) { a in
            NavigationLink { FinamiHomeAccountSettings(accountID: a.id) } label: {
                HStack { FinamiArt(icon: accountArtIcon(a), tint: accountTint(a, fallback: .teal), size: 36); VStack(alignment: .leading) { Text(a.name); Text(a.hiddenInOverview == true ? "Приховано на головній" : accountStyle(a.cardOptions?.style ?? s.db.preferences?.homeAccountLayout).title).font(.caption).foregroundStyle(.secondary) } }
            }
        }.onMove { source, destination in
            var moved = rows; moved.move(fromOffsets: source, toOffset: destination)
            let ids = (pinned ? moved + accounts.filter { $0.cardOptions?.pinned != true } : accounts.filter { $0.cardOptions?.pinned == true } + moved).map(\.id)
            s.change { d in for (order, id) in ids.enumerated() { if let i = d.accounts.firstIndex(where: { $0.id == id }) { var options = d.accounts[i].cardOptions ?? .init(); options.order = order; d.accounts[i].cardOptions = options } } }
        }
    }
}

struct FinamiHomeAccountSettings: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    var accountID: String
    var closeButton = false
    @State private var photo: PhotosPickerItem?
    @State private var photoError = false
    @State private var photoLoading = false
    private var account: Account? { s.db.accounts.first { $0.id == accountID } }
    private var options: AccountCardOptions { account?.cardOptions ?? .init() }
    private func update(_ action: (inout AccountCardOptions) -> Void) {
        s.change { d in if let i = d.accounts.firstIndex(where: { $0.id == accountID }) { var o = d.accounts[i].cardOptions ?? .init(); action(&o); d.accounts[i].cardOptions = o } }
    }
    private func selection(_ key: WritableKeyPath<AccountCardOptions, String?>) -> Binding<String> {
        Binding(get: { options[keyPath: key] ?? "" }, set: { v in update { $0[keyPath: key] = v.isEmpty ? nil : v } })
    }
    private func field(_ f: HomeAccountField) -> Binding<Bool> {
        Binding(get: { (options.fields ?? s.db.preferences?.homeAccountFields ?? HomeAccountField.defaults).contains(f.rawValue) }, set: { v in
            update { o in var fields = o.fields ?? s.db.preferences?.homeAccountFields ?? HomeAccountField.defaults; fields.removeAll { $0 == f.rawValue }; if v { fields.append(f.rawValue) }; o.fields = fields }
        })
    }
    var body: some View {
        Form {
            if let a = account {
                Section("На головній") {
                    Toggle("Показувати рахунок", isOn: Binding(get: { account?.hiddenInOverview != true }, set: { v in s.change { d in if let i = d.accounts.firstIndex(where: { $0.id == accountID }) { d.accounts[i].hiddenInOverview = !v } } }))
                    Toggle("Закріпити зверху", isOn: Binding(get: { options.pinned == true }, set: { v in update { $0.pinned = v } }))
                    Toggle("Приховати суми", isOn: Binding(get: { account?.hideAmounts == true }, set: { v in s.change { d in if let i = d.accounts.firstIndex(where: { $0.id == accountID }) { d.accounts[i].hideAmounts = v } } }))
                }
                Section("Дизайн") {
                    FinamiComponentStylePicker(component: "accounts", title: "Design 3.0", accountID: a.id)
                    Picker("Шаблон", selection: selection(\.style)) { Text("Загальний").tag(""); ForEach(HomeAccountStyle.allCases) { Text($0.title).tag($0.rawValue) } }
                    Picker("Права частина", selection: selection(\.right)) { Text("Загальна").tag(""); ForEach(HomeAccountRight.allCases) { Text($0.title).tag($0.rawValue) } }
                    Picker("Акцент", selection: selection(\.accent)) { Text("Автоматично").tag(""); ForEach(IzanamiTheme.all) { theme in Label(theme.name, systemImage: "circle.fill").foregroundStyle(theme.color).tag(theme.name) } }
                    if !a.isCredit { Text("Кредитні показники відображаються лише для кредитних рахунків.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Фото рахунку") {
                    if let data = options.photo, let image = FinamiImageCache.shared.image(data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Вибрати фото", systemImage: "photo") }.disabled(photoLoading)
                    if photoLoading { ProgressView("Обробка фото") }
                    if options.photo != nil { Button("Видалити фото", role: .destructive) { update { $0.photo = nil; if $0.right == "photo" { $0.right = "art" } } } }
                    Text("Фото зберігається локально у резервній копії. Не додавай фото з повним номером картки або CVV.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Інформація на картці") {
                    Toggle("Використовувати загальні показники", isOn: Binding(get: { options.fields == nil }, set: { v in update { $0.fields = v ? nil : (s.db.preferences?.homeAccountFields ?? HomeAccountField.defaults) } }))
                    if options.fields != nil { ForEach(HomeAccountField.allCases) { f in Toggle(f.title, isOn: field(f)) } }
                }
                Section { Button("Скинути індивідуальний дизайн") { update { $0.style = nil; $0.right = nil; $0.fields = nil; $0.accent = nil }; s.changeAppearance { $0.setDesignAccountStyle(nil, for: accountID) } } }
            } else { Text("Рахунок не знайдено") }
        }.navigationTitle(account?.name ?? "Оформлення рахунку")
            .toolbar { if closeButton { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } } }
            .onChange(of: photo) { item in
                guard let item = item else { return }
                photoLoading = true
                Task { @MainActor in
                    defer { photoLoading = false; photo = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let jpeg = await Task.detached(priority:.userInitiated, operation:{finamiThumbnailJPEG(data,maxPixels:640)}).value else { photoError = true; return }
                    update { $0.photo = jpeg; $0.right = "photo" }
                }
            }
            .alert("Не вдалося завантажити фото", isPresented: $photoError) { Button("Гаразд", role: .cancel) {} }
    }
}

private struct HomeAccountHistory: View {
    @EnvironmentObject private var s: Store
    @Environment(\.dismiss) private var dismiss
    var accountID: String
    var blockMasked: Bool
    @State private var edit: Operation?
    var body: some View {
        List {
            if let a = s.db.accounts.first(where: { $0.id == accountID }) {
                let activity = s.accountActivity(a, month: Date())
                let mask = blockMasked || s.privateAmounts || a.hideAmounts == true
                if activity.history.isEmpty { Text("Немає операцій") }
                ForEach(activity.history) { o in
                    Button { edit = o } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(o.note.isEmpty ? o.category : o.note).font(.headline).foregroundStyle(.primary)
                            Text(o.kind.title + " · " + o.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text(mask ? "****" : currencyMoney(activity.signed(o), a.code)).font(.title3.weight(.semibold)).foregroundStyle(.primary).monospacedDigit()
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            } else { Text("Рахунок не знайдено") }
        }.navigationTitle("Операції рахунку").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }.sheet(item: $edit) { OpEditor(original: $0) }
    }
}

struct FinamiCompactAccountsGrid: View {
    @EnvironmentObject private var s: Store
    @Environment(\.finamiMask) private var masked
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var accounts: [Account]
    var mode: String
    var date: Date
    var onAccountsScreen = false
    var forceList = false
    @State private var selected: Account?
    private var p: AppearancePreferences { s.db.preferences ?? .init() }
    private var list: Bool { forceList || p.finamiLayout == "list" || dynamicTypeSize.isAccessibilitySize }
    private func isHidden(_ a: Account, field: String?) -> Bool {
        masked || s.privateAmounts || a.hideAmounts == true || (onAccountsScreen && (field == "own" ? p.accountsHideOwn == true : p.accountsHideCredit == true))
    }
    private func metric(_ a: Account) -> (String,String) {
        let fields = Set(a.cardOptions?.fields ?? p.homeAccountFields ?? HomeAccountField.defaults)
        let key = FinamiDesignPolicy.primaryField(fields:fields,credit:a.isCredit,mode:mode)
        let label: String; let amount: Int64
        switch key {
        case "available": label="Доступний кредит";amount=s.unusedCredit(a)
        case "used": label="Використано кредиту";amount=s.debt(a)
        case "limit": label="Кредитний ліміт";amount=a.limit
        case "own": label="Власні кошти";amount=s.ownFunds(a)
        default: return ("Показники приховано", "—")
        }
        return (label,isHidden(a,field:key) ? "••••" : s.visibleMoney(amount,a.code))
    }
    private func icon(_ a:Account) -> some View {
        FinamiIconTile(icon:accountArtIcon(a),tint:accountTint(a,fallback:.teal),side:32)
    }
    private func markers(_ a:Account) -> some View {
        HStack(spacing:4) {
            if a.excludedFromTotals == true { Image(systemName:"minus.circle").accessibilityLabel("Поза підсумками") }
            if a.hiddenInAccounts == true && onAccountsScreen { Image(systemName:"eye.slash").accessibilityLabel("Прихований рахунок") }
            if a.cardOptions?.pinned == true { Image(systemName:"pin.fill").accessibilityLabel("Закріплено") }
        }.font(.caption2).foregroundStyle(.secondary)
    }
    private func gridCard(_ a:Account) -> some View {
        let value=metric(a)
        return VStack(alignment:.leading,spacing:5) {
            HStack { icon(a);Spacer(minLength:2);markers(a);Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary) }
            Text(a.name).font(.subheadline.weight(.semibold)).lineLimit(2,reservesSpace:true)
            Spacer(minLength:0)
            Text(value.0).font(.caption2).foregroundStyle(.secondary).lineLimit(2,reservesSpace:true)
            Text(value.1).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55).accessibilityLabel(value.1)
        }.frame(maxWidth:.infinity,minHeight:132,alignment:.topLeading).padding(12)
    }
    private func listCard(_ a:Account) -> some View {
        let value=metric(a)
        return HStack(alignment:.center,spacing:10) {
            icon(a)
            VStack(alignment:.leading,spacing:4) {
                Text(a.name).font(.subheadline.weight(.semibold)); Text(value.0).font(.caption).foregroundStyle(.secondary);markers(a)
                if dynamicTypeSize.isAccessibilitySize { Text(value.1).font(.headline).monospacedDigit() }
            }.frame(maxWidth:.infinity,alignment:.leading)
            if !dynamicTypeSize.isAccessibilitySize { Text(value.1).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.7) }
            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(10).frame(minHeight:54)
    }
    @ViewBuilder private func compactVariant(_ a: Account) -> some View {
        let variant = p.designAccountStyle(for: a.id)
        let fields = Set(a.cardOptions?.fields ?? p.homeAccountFields ?? HomeAccountField.defaults)
        if variant == "bankingSplit" && a.isCredit && mode == "all" && fields.contains("own") && fields.contains("available") {
            let key = FinamiDesignPolicy.primaryField(fields: fields, credit: a.isCredit, mode: mode)
            let showOwn = key != "own"
            HStack {
                Text(showOwn ? "Власні кошти" : "Доступний кредит").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(isHidden(a,field:showOwn ? "own" : "available") ? "••••" : s.visibleMoney(showOwn ? s.ownFunds(a) : s.unusedCredit(a),a.code)).font(.caption.monospacedDigit()).minimumScaleFactor(0.6)
            }.padding(.horizontal, 10).padding(.bottom, 10)
        } else if variant == "creditRing" && a.isCredit && mode != "own" && fields.contains("used") && fields.contains("limit"), let fraction = FinamiDesignPolicy.creditFraction(used:s.debt(a),limit:a.limit,masked:isHidden(a,field:"used")) {
            let tint = accountTint(a,fallback:.teal)
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(fraction)).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: 26, height: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Використано кредиту").font(.caption2).foregroundStyle(.secondary)
                    Text(Double(s.debt(a)) / Double(a.limit), format: .percent.precision(.fractionLength(0))).font(.caption.weight(.semibold)).monospacedDigit()
                }
                Spacer(minLength: 0)
            }.padding(.horizontal,10).padding(.bottom,10)
        } else if variant == "auroraCard" {
            HStack { Image(systemName:"creditcard"); Spacer(); Text(isHidden(a,field:"own") || isHidden(a,field:"used") ? "••••" : a.lastFour.map { "•••• " + $0 } ?? a.code) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,10).padding(.bottom,10)
        }
    }
    private func card(_ a:Account) -> some View {
        Button { selected=a } label: {
            VStack(spacing: 0) { if list { listCard(a) } else { gridCard(a) }; compactVariant(a) }
                .frame(maxWidth:.infinity,alignment:.topLeading).contentShape(Rectangle())
                .modifier(FinamiCardStyle(tint:accountTint(a,fallback:.teal)))
        }.buttonStyle(.plain).accessibilityIdentifier("qa.account.compact." + a.id)
    }
    var body: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10,alignment:.top),count:list ? 1 : 2),alignment:.center,spacing:10) {
            ForEach(accounts) { a in card(a) }
        }.sheet(item:$selected) { a in
            NavigationStack {
                ScrollView {
                    FinamiHomeAccountCard(accountID:a.id,date:date,fallbackTint:.teal,mode:mode,onAccountsScreen:onAccountsScreen)
                        .environment(\.finamiMask,masked)
                        .padding()
                }.navigationTitle("Деталі рахунку").toolbar { ToolbarItem(placement:.confirmationAction) { Button("Готово") { selected=nil } } }
            }
        }
    }
}
