import SwiftUI
import UserNotifications

struct AppearancePreferences: Codable {
    var theme = "Crimson"
    var mode = "system"
    var font = "default"
    var largeIcons = true
    var glow = true
    var colorfulDashboard: Bool? = nil
    var design: String? = nil
    var cardTemplate: String? = nil
    var hideAmounts: Bool? = nil
    var showIncome: Bool? = nil
    var showExpenses: Bool? = nil
    var noCharts: Bool? = nil
    var accountsLayout: String? = nil
    var accountsMode: String? = nil
    var accountsShowHidden: Bool? = nil
    var accountsShowLimit: Bool? = nil
    var accountsShowUsed: Bool? = nil
    var accountsShowAvailable: Bool? = nil
    var homeTitle: String? = nil
    var voiceHideHint: Bool? = nil
    var homeAccountLayout: String? = nil
    var homeAccountRight: String? = nil
    var homeAccountFields: [String]? = nil
    var operationsFilter: String? = nil
    var operationsSort: String? = nil
    var reportsShowChart: Bool? = nil
    var reportsShowMonths: Bool? = nil
    var reportsShowCategories: Bool? = nil
    var reportsHiddenSections: [String]? = nil
    var menuCompact: Bool? = nil
    var accountsHideOwn: Bool? = nil
    var accountsHideCredit: Bool? = nil
    var reportsPeriod: String? = nil
    var reportsAccount: String? = nil
    var reportsShowIncome: Bool? = nil
    var reportsShowIncoming: Bool? = nil
    var reportsCompareElapsed: Bool? = nil
    var reportsShowComparison: Bool? = nil
    var reportsShowAccounts: Bool? = nil
    var reportsShowReview: Bool? = nil
    var reportsCategoryLimit: Int? = nil
    // Missing account key preserves the original detailed report. Empty array hides every row.
    var reportsAccountFields: [String: [String]]? = nil
    var modernAccountGrid: Bool? = nil
    var modernCompactSpacing: Bool? = nil
    var modernPaymentIcons: String? = nil
    var modernPaymentTotal: Bool? = nil
    var modernPaymentMonthly: Bool? = nil
    var modernPaymentRemaining: Bool? = nil
    var designLayout: String? = nil
    var designDashboard: String? = nil
    var simpleHome: Bool? = nil
    var qualityQuickActions: Bool? = nil
    var designAccent: String? = nil
    var designRadius: Int? = nil
    var designLowEffects: Bool? = nil
    var designPresets: [String: [String: String]]? = nil
    var dashboardLayoutPresets: [String: Data]? = nil
    var collapsedDashboard: [String]? = nil
    var hideEmptyDashboard: Bool? = nil
    var collapsedMenu: [String]? = nil
    var collapsedReports: [String]? = nil
    // Optional, additive Design 3.0 preferences. Legacy backups decode unchanged.
    var componentStyles: [String: String]? = nil
    var componentSizes: [String: String]? = nil
    var individualCardStyles: [String: String]? = nil
    var collapsedInstallments: [String]? = nil
    var collapsedSubscriptions: [String]? = nil
    var designUpcomingCount: Int? = nil
    var designUpcomingFields: [String]? = nil
    var designSubscriptionIcons: [String: String]? = nil
    var designSubscriptionColors: [String: String]? = nil
    var designHiddenSubscriptions: [String]? = nil
    var designCalendarListCollapsed: Bool? = nil
    var designReportCharts: [String: String]? = nil
    var designEditorKeyboard: Bool? = nil
    var designEditorHaptics: Bool? = nil
    var designEditorConfirm: Bool? = nil
    var designEditorLastAccountEnabled: Bool? = nil
    var designEditorLastAccount: String? = nil
    var designEditorFavorites: [String]? = nil
    var designReportOrder: [String]? = nil
    var designReportBlockStyles: [String: String]? = nil
}
struct IzanamiTheme: Identifiable {
    var id: String { name }
    let name: String
    let color: Color
    static let all: [Self] = [
        .init(name: "Crimson", color: .init(red: 0.85, green: 0.12, blue: 0.25)),
        .init(name: "Sharingan", color: .red), .init(name: "Emerald", color: .green),
        .init(name: "Midnight", color: .indigo), .init(name: "Sakura", color: .pink),
        .init(name: "AMOLED", color: .gray), .init(name: "Gold", color: .orange),
        .init(name: "Arctic", color: .cyan), .init(name: "Ocean", color: .teal),
        .init(name: "Royal Purple", color: .purple), .init(name: "Light", color: .blue),
        .init(name: "Cyberpunk", color: .yellow)
    ]
}
struct IzanamiShell: View {
    @EnvironmentObject var s: Store
    var p: AppearancePreferences { s.db.preferences ?? .init() }
    var preset: FinamiDesign { FinamiDesign(rawValue: p.design ?? "Dark Classic") ?? .darkClassic }
    var accent: Color { if let custom = finamiDesignAccent(p.designAccent) { return custom }; return (p.design == nil && p.theme == "Crimson") || p.theme == "Preset" ? preset.tint : IzanamiTheme.all.first(where: { $0.name == p.theme })?.color ?? preset.tint }
    var scheme: ColorScheme? { p.mode == "dark" ? .dark : p.mode == "light" ? .light : p.mode == "preset" ? preset.scheme : nil }
    var design: Font.Design { p.font == "rounded" ? .rounded : p.font == "serif" ? .serif : p.font == "monospaced" ? .monospaced : p.font == "preset" ? preset.font : .default }
    var body: some View {
        Root(navigationAccent: accent).tint(accent).preferredColorScheme(scheme).environment(\.font, .system(.body, design: design)).environment(\.locale, Locale(identifier:"uk_UA"))
    }
}
// A single visual vocabulary for menus and overview cards.
struct IzanamiGlyph: View {
    @EnvironmentObject var s: Store
    var icon: String
    var color: Color
    var compact = false
    var body: some View {
        let p = s.db.preferences ?? .init()
        let side: CGFloat = compact ? 30 : (p.largeIcons ? 42 : 34)
        Image(systemName: icon)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: side, height: side)
            .background(color.opacity(p.glow ? 0.19 : 0.09), in: RoundedRectangle(cornerRadius: side * 0.28))
            .accessibilityHidden(true)
    }
}
struct IzanamiLabel: View {
    @EnvironmentObject var s: Store
    var title: String; var icon: String; var color: Color
    var body: some View {
        let p = s.db.preferences ?? .init()
        let tint = (p.colorfulDashboard ?? true) ? color : (IzanamiTheme.all.first(where: { $0.name == p.theme })?.color ?? finoraAccent)
        HStack(spacing: 12) {
            FinamiIconTile(icon: icon, tint: tint, side: p.menuCompact == true ? 36 : 48)
            Text(title).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }.frame(minHeight: 46, alignment: .leading).padding(.vertical, 2)
    }
}
struct AppearanceView: View {
    @EnvironmentObject var s: Store
    func binding<T>(_ key: WritableKeyPath<AppearancePreferences,T>) -> Binding<T> {
        Binding(get: { (s.db.preferences ?? .init())[keyPath: key] }, set: { value in
            s.changeAppearance { p in p[keyPath: key] = value }
        })
    }
    @State private var preview: FinamiDesign?
    private func designRow(_ preset:FinamiDesign)->some View {
        Button { preview=preset } label: {
            HStack(alignment:.center,spacing:12) {
                RoundedRectangle(cornerRadius:12).fill(preset.scheme == .dark ? Color(red:0.12,green:0.13,blue:0.15) : Color(red:0.94,green:0.95,blue:0.97)).overlay { Image(systemName:"creditcard.fill").foregroundStyle(preset.tint) }.frame(width:54,height:48)
                VStack(alignment:.leading,spacing:4) { Text(preset.rawValue).font(.headline);Text(preset.description).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength:4)
                Image(systemName:s.db.preferences?.design == preset.rawValue ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(.tint)
            }.frame(minHeight:54)
        }.buttonStyle(.plain)
    }
    var body: some View {
        Form {
            Section("Головний екран") {
                Picker("Компонування",selection:Binding(get:{s.db.preferences?.simpleHome == true},set:{v in s.changeAppearance{$0.simpleHome=v}})) { Text("Поточна").tag(false);Text("Спрощена").tag(true) }.pickerStyle(.segmented).accessibilityIdentifier("qa.home.layout")
                Text("Поточні блоки та їх порядок збережено. Перемикання не змінює фінанси.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("Налаштувати поточні блоки") { DashboardSettings() }
            }
            Section("6.2 · Finami Design") {
                ForEach(FinamiDesign.simplicity) { preset in designRow(preset) }
                ForEach(FinamiDesign.revolution) { preset in designRow(preset) }
                NavigationLink("Design Lab · власні стилі") { FinamiDesignLab() }
            }
            Section("Finami Design · нові стилі") {
                ForEach(FinamiDesign.featured) { preset in designRow(preset) }
            }
            Section("Щільність та платежі") {
                Toggle("Компактна сітка рахунків",isOn:Binding(get:{(s.db.preferences ?? .init()).finamiLayout == "grid"},set:{v in s.changeAppearance { $0.designLayout = v ? "grid" : "cards"; $0.modernAccountGrid=v }}))
                Toggle("Щільніші відступи",isOn:Binding(get:{s.db.preferences?.modernCompactSpacing ?? true},set:{binding(\.modernCompactSpacing).wrappedValue=$0}))
                Picker("Іконки платежів",selection:Binding(get:{s.db.preferences?.modernPaymentIcons ?? "black"},set:{binding(\.modernPaymentIcons).wrappedValue=$0})) { Text("Чорні · золото").tag("black"); Text("Кольорові").tag("color") }
                Toggle("Загальна сума кредиту",isOn:Binding(get:{s.db.preferences?.modernPaymentTotal ?? true},set:{binding(\.modernPaymentTotal).wrappedValue=$0}))
                Toggle("Щомісячний платіж",isOn:Binding(get:{s.db.preferences?.modernPaymentMonthly ?? true},set:{binding(\.modernPaymentMonthly).wrappedValue=$0}))
                Toggle("Залишок боргу в платежах",isOn:Binding(get:{s.db.preferences?.modernPaymentRemaining ?? false},set:{binding(\.modernPaymentRemaining).wrappedValue=$0}))
            }
            Section("Картки та приватність") {
                Picker("Шаблон карток",selection:Binding(get:{s.db.preferences?.cardTemplate ?? "За дизайном"},set:{binding(\.cardTemplate).wrappedValue=$0})) {ForEach(FinamiCardTemplate.allCases){Text($0.rawValue).tag($0.rawValue)}}
                Toggle("Приховувати суми",isOn:Binding(get:{s.privateAmounts},set:{binding(\.hideAmounts).wrappedValue=$0}))
                Toggle("Показувати доходи",isOn:Binding(get:{s.db.preferences?.showIncome ?? false},set:{binding(\.showIncome).wrappedValue=$0}))
                Toggle("Показувати витрати",isOn:Binding(get:{s.db.preferences?.showExpenses ?? true},set:{binding(\.showExpenses).wrappedValue=$0}))
                Toggle("Без діаграм на огляді",isOn:Binding(get:{s.db.preferences?.noCharts ?? true},set:{binding(\.noCharts).wrappedValue=$0}))
            }
            Section("Акцент") { FinamiAccentPicker() }
            Picker("Режим", selection: binding(\.mode)) { Text("За дизайном").tag("preset"); Text("Системний").tag("system"); Text("Темний").tag("dark"); Text("Світлий").tag("light") }
            Picker("Шрифт", selection: binding(\.font)) { Text("За дизайном").tag("preset"); Text("Системний").tag("default"); Text("Rounded").tag("rounded"); Text("Serif").tag("serif"); Text("Monospaced").tag("monospaced") }
            Toggle("Великі іконки", isOn: binding(\.largeIcons))
            Toggle("Яскраве підсвічування", isOn: binding(\.glow))
            Toggle("Кольорові акценти", isOn: Binding(get:{s.db.preferences?.colorfulDashboard ?? true},set:{binding(\.colorfulDashboard).wrappedValue=$0}))
        }.navigationTitle("Finami Design").sheet(item:$preview) { selected in NavigationStack { VStack(spacing:18) { FinamiDesignPreview(design:selected); Text(selected.description).foregroundStyle(.secondary); Button("Застосувати дизайн") { s.changeAppearance { p in p.applyFinamiDesign(selected.rawValue) };preview=nil }.buttonStyle(.borderedProminent);Spacer() }.padding().navigationTitle(selected.rawValue).toolbar{Button("Скасувати"){preview=nil}} } }
    }
}
enum OperationSort: String, CaseIterable {
    case newest = "Спочатку нові", oldest = "Спочатку старі", largest = "Сума ↓", smallest = "Сума ↑", category = "Категорія А–Я", name = "Назва А–Я"
    func orders(_ a: Operation, _ b: Operation) -> Bool {
        switch self {
        case .newest: return a.date > b.date
        case .oldest: return a.date < b.date
        case .largest: return a.amount == b.amount ? a.date > b.date : a.amount > b.amount
        case .smallest: return a.amount == b.amount ? a.date > b.date : a.amount < b.amount
        case .category: return a.category.localizedCompare(b.category) == .orderedAscending
        case .name: return a.note.localizedCompare(b.note) == .orderedAscending
        }
    }
}
func ruleKey(_ note: String, kind: Kind) -> String { kind.rawValue + ":" + note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
func suggestedCategory(_ note: String, kind: Kind, database: Database) -> String {
    if kind == .receipt { return finamiIntelligentCategory(note, kind: kind, allowed: database.availableReceiptCategories, learned: database.merchantRules ?? [:]) }
    let hidden = kind == .income ? database.hiddenIncomeCategories ?? [] : database.hiddenExpenseCategories ?? []
    let allowed = (kind == .income ? database.incomeCategories : database.expenseCategories).filter { !hidden.contains($0) }
    return finamiIntelligentCategory(note, kind: kind, allowed: allowed, learned: database.merchantRules ?? [:])
}

enum DashboardKind: String, Codable, CaseIterable, Identifiable {
    case balance, cashflow, categories, recent, accounts, budget, obligations, subscriptions, reminders, forecast, uncategorized, goals, debt, installments, recurring, statistics, fees, savings, ownFunds, creditDebt, availableCredit, review, creditLimit, creditPortfolio, allAvailable, monthlyPayments, paymentCalendar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .balance: return "Загальний баланс"
        case .cashflow: return "Доходи та витрати"
        case .categories: return "Категорії витрат"
        case .recent: return "Останні операції"
        case .accounts: return "Рахунки"
        case .budget: return "Бюджет"
        case .obligations: return "Найближчі платежі"
        case .subscriptions: return "Підписки"
        case .reminders: return "Нагадування"
        case .forecast: return "Фінансовий прогноз"
        case .uncategorized: return "Без категорії"
        case .goals: return "Цілі"
        case .debt: return "Борги"
        case .installments: return "Розстрочки"
        case .recurring: return "Регулярні платежі"
        case .statistics: return "Статистика місяця"
        case .fees: return "Банківські комісії"
        case .savings: return "Частка заощаджень"
        case .ownFunds: return "Власні кошти"
        case .creditDebt: return "Борг за рахунками"
        case .availableCredit: return "Доступно кредиту"
        case .review: return "Потребують уточнення"
        case .creditLimit: return "Загальний кредитний ліміт"
        case .creditPortfolio: return "Кредитні кошти"
        case .allAvailable: return "Власні + доступний кредит"
        case .monthlyPayments: return "Платежі до кінця місяця"
        case .paymentCalendar: return "Календар платежів"
        }
    }
    var icon: String {
        switch self {
        case .balance,.accounts: return "wallet.pass.fill"
        case .cashflow: return "arrow.left.arrow.right"
        case .categories,.statistics: return "chart.pie.fill"
        case .recent: return "clock.arrow.circlepath"
        case .budget,.goals: return "target"
        case .obligations,.recurring: return "calendar.badge.clock"
        case .subscriptions: return "repeat"
        case .reminders: return "bell.badge.fill"
        case .forecast,.savings: return "chart.line.uptrend.xyaxis"
        case .uncategorized: return "tray.fill"
        case .debt,.installments,.fees,.creditDebt: return "creditcard.fill"
        case .ownFunds: return "banknote.fill"
        case .availableCredit: return "building.columns.fill"
        case .review: return "exclamationmark.bubble.fill"
        case .creditLimit,.creditPortfolio: return "creditcard.fill"
        case .allAvailable: return "wallet.pass.fill"
        case .monthlyPayments,.paymentCalendar: return "calendar"
        }
    }
}
extension DashboardKind {
    var tileColor: Color {
        switch self {
        case .balance: return .red
        case .ownFunds,.savings,.goals: return .green
        case .creditDebt,.fees,.debt,.review: return .orange
        case .accounts,.availableCredit,.creditLimit,.creditPortfolio,.allAvailable: return .blue
        case .subscriptions,.categories: return .purple
        case .obligations,.reminders,.recurring,.monthlyPayments,.paymentCalendar: return .cyan
        case .forecast,.statistics: return .teal
        case .cashflow,.budget: return .indigo
        case .recent,.uncategorized,.installments: return .pink
        }
    }
}
enum DashboardSize: String, Codable, CaseIterable { case small = "Компактний", medium = "Середній", large = "Великий" }
struct DashboardItem: Codable, Identifiable {
    var id: String { kind.rawValue }
    var kind: DashboardKind; var enabled: Bool; var size: DashboardSize
    var template: String? = nil
    var accentName: String? = nil
    var categorySelection: [String]? = nil
    var categoryCount: Int? = nil
    var showLimit: Bool? = nil
    var showUsed: Bool? = nil
    var showAvailable: Bool? = nil
    var showPaymentRemaining: Bool? = nil
    var showPaymentDate: Bool? = nil
    var showPaymentImage: Bool? = nil
    var showPaymentTotal: Bool? = nil
    var showPaymentNames: Bool? = nil
    var hideAmounts: Bool? = nil
    static var defaults: [Self] { DashboardKind.allCases.map { k in
        .init(kind: k, enabled: [.ownFunds,.categories,.obligations,.recent].contains(k), size: [.balance,.ownFunds,.categories,.obligations,.creditPortfolio,.recent].contains(k) ? .large : .medium)
    } }
    static func merged(_ stored: [Self]?) -> [Self] {
        guard let stored else { return defaults }
        var seen=Set<String>()
        let clean=stored.filter{seen.insert($0.id).inserted}
        return clean + defaults.filter{!seen.contains($0.id)}.map { var x=$0;x.enabled=false;return x }
    }
}
struct DashboardSettings: View {
    @EnvironmentObject var s: Store
    var items: [DashboardItem] { DashboardItem.merged(s.db.dashboard) }
    func modify(_ id: String, _ action: (inout DashboardItem)->Void) { s.change { d in var all = DashboardItem.merged(d.dashboard); if let i = all.firstIndex(where: { $0.id == id }) { action(&all[i]) }; d.dashboard = all } }
    var body: some View {
        List {
            NavigationLink("Мої конфігурації головної") { FinamiDashboardPresetsView() }
            NavigationLink("Змінити порядок видимих блоків") { FinamiOrderEditor(target: .dashboard, closeButton: false) }
            Toggle("Швидкі дії на головній", isOn: Binding(get: { s.db.preferences?.qualityQuickActions != false }, set: { value in s.changeAppearance { $0.qualityQuickActions = value } }))
            Section("Увімкни потрібні блоки. Через «Редагувати» перетягни їх у новий порядок. Компактні блоки займають менше місця; рахунки, баланси та платежі залишаються на всю ширину для читабельності.") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { items.first(where: { $0.id == item.id })?.enabled ?? false }, set: { v in modify(item.id) { $0.enabled = v } })) { Label(item.kind.title, systemImage: item.kind.icon) }
                        if item.enabled {
                            NavigationLink("Оформлення та показники") { FinamiBlockSettings(id:item.id) }
                            Picker("Розмір", selection: Binding(get: { items.first(where: { $0.id == item.id })?.size ?? .medium }, set: { v in modify(item.id) { $0.size = v } })) { ForEach(DashboardSize.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("qa.dashboard.size." + item.id)
                        }
                    }
                }.onMove { from, to in s.change { d in var all = DashboardItem.merged(d.dashboard); all.move(fromOffsets: from, toOffset: to); d.dashboard = all } }
            }
            Section("Назва вкладки") { Picker("Назва", selection: Binding(get: { s.db.preferences?.homeTitle ?? "Головна" }, set: { v in s.changeAppearance { p in p.homeTitle=v } })) { ForEach(["Головна","Огляд","Мої фінанси","Гаманець"],id:\.self){Text($0).tag($0)} } }
            Button("Повернути стандартні блоки") { s.change { $0.dashboard = DashboardItem.defaults } }
        }.navigationTitle("Блоки головної").toolbar { EditButton() }
    }
}
private struct FinamiDashboardRow: Identifiable { var items: [DashboardItem]; var id: String { items.first?.id ?? "empty" } }
struct CustomDashboard: View {
    @EnvironmentObject var s: Store
    @State private var date = Date()
    @State private var add = false
    @State private var quickDraft: Operation?
    @State private var configure = false
    @State private var reorder = false
    @State private var voice = false
    @State private var scan = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var items: [DashboardItem] {
        let enabled = DashboardItem.merged(s.db.dashboard).filter(\.enabled).map { item -> DashboardItem in
            guard s.db.preferences?.designDashboard == "analytics", [.categories,.cashflow,.forecast,.statistics].contains(item.kind) else { return item }
            var display=item;display.size = .large;return display
        }
        guard s.db.preferences?.hideEmptyDashboard == true else { return enabled }
        return enabled.filter { item in
            switch item.kind {
            case .accounts: return s.db.accounts.contains { $0.hiddenInOverview != true }
            case .budget: return s.db.budget > 0
            case .forecast: return s.db.forecast != nil
            case .goals: return s.db.obligations.contains { $0.kind == .goal && $0.remaining > 0 }
            case .reminders: return (s.db.reminders ?? []).contains { $0.enabled && $0.date > Date() }
            default: return true // never hide debts or ambiguous financial data
            }
        }
    }
    var rows: [[DashboardItem]] {
        var result: [[DashboardItem]] = []; var pair: [DashboardItem] = []
        for item in items {
            if s.db.preferences?.designDashboard != "premium" && !(s.db.preferences?.collapsedDashboard ?? []).contains(item.id) && item.size == .small && ![.balance,.ownFunds,.creditLimit,.creditPortfolio,.obligations,.allAvailable,.monthlyPayments,.accounts,.paymentCalendar].contains(item.kind) && !dynamicTypeSize.isAccessibilitySize { pair.append(item); if pair.count == 2 { result.append(pair); pair = [] } }
            else { if !pair.isEmpty { result.append(pair); pair = [] }; result.append([item]) }
        }
        if !pair.isEmpty { result.append(pair) }; return result
    }
    @ViewBuilder private var quickActions: some View {
        if s.db.preferences?.qualityQuickActions != false {
            FinamiDashboardQuickActions { kind in
                quickDraft = Operation(kind: kind, category: "Без категорії", account: s.db.accounts.first?.id ?? cash)
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            LazyVStack(spacing: (s.db.preferences ?? .init()).finamiSpacing) {
                MonthControl(date: $date, dashboardStyle: true)
                if !items.contains(where: { $0.kind == .review }) {
                    NavigationLink { FinamiReportReviewList(ids: [], account: nil, maskAmounts: true, includeInbox: true) } label: {
                        Label("Потребують уточнення: \(s.db.operations.filter { $0.needsCaptureAttention }.count + s.capturePending.count)", systemImage: "exclamationmark.bubble")
                    }
                }
                if items.isEmpty { Panel { Text("Немає видимих блоків"); Button("Налаштувати огляд") { configure = true } } }
                ForEach(rows.map { FinamiDashboardRow(items: $0) }) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entry.items) { item in DashboardTile(item: item, date: date) }
                    }
                    if entry.items.contains(where: { $0.kind == .ownFunds }) { quickActions }
                }
                if !items.contains(where: { $0.kind == .ownFunds }) { quickActions }
            }.padding()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        HStack { Button { add = true } label: { Label("Додати операцію", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5).frame(minHeight:44) }.buttonStyle(.borderedProminent); Button { voice=true } label:{Image(systemName:"mic.fill").frame(minWidth:44,minHeight:44)}.buttonStyle(.bordered).accessibilityLabel("Голосовий запис"); Button { scan = true } label: { Image(systemName: "doc.viewfinder").frame(minWidth:44,minHeight:44) }.buttonStyle(.bordered).accessibilityLabel("Імпорт зі скриншота").accessibilityIdentifier("qa.home.scan") }.padding(.horizontal).padding(.vertical,7).background(Color(uiColor:.systemGroupedBackground))
        }.background(finamiScreenBackground(s.db.preferences)).navigationTitle(s.db.preferences?.homeTitle ?? "Головна")
            .toolbar { NavigationLink { FinamiGlobalSearch() } label: { Image(systemName:"magnifyingglass") }.accessibilityLabel("Пошук Finami"); Button { s.changeAppearance { p in p.hideAmounts = !(p.hideAmounts ?? false) } } label: { Image(systemName:s.privateAmounts ? "eye.slash" : "eye") }.accessibilityLabel("Приховати або показати суми"); Button { reorder = true } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Змінити порядок блоків"); Button { configure = true } label: { Image(systemName: "slider.horizontal.3").font(.title2) }.accessibilityLabel("Налаштувати блоки") }
            .sheet(isPresented: $add) { OpEditor(original: Operation(category: "Без категорії", account: s.db.accounts.first?.id ?? cash)) }
            .sheet(item: $quickDraft) { OpEditor(original: $0) }
            .sheet(isPresented:$voice) { FinamiVoice() }
            .sheet(isPresented:$scan) { NavigationStack { FinamiScanView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { scan = false } } } } }
            .sheet(isPresented: $reorder) { NavigationStack { FinamiOrderEditor(target: .dashboard) } }
            .sheet(isPresented: $configure) { NavigationStack { DashboardSettings().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { configure = false } } } } }
    }
}
struct DashboardTile: View {
    @EnvironmentObject var s: Store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var item: DashboardItem; var date: Date
    var ops: [Operation] { s.month(date) }
    private var metrics: FinamiDashboardMetrics { s.dashboardMetrics(date) }
    var inc: Int64 { metrics.income }
    var exp: Int64 { metrics.expense }
    var balance: Int64 { s.includedAccounts.reduce(0) { $0 + s.balance($1) } }
    var small: Bool { item.size == .small && ![.balance,.ownFunds,.creditLimit,.creditPortfolio,.obligations,.allAvailable,.monthlyPayments,.accounts,.paymentCalendar].contains(item.kind) && !dynamicTypeSize.isAccessibilitySize }
    @State private var paymentDetails: FinamiPayment?
    @State private var accountSettings = false
    var masked: Bool {
        if s.privateAmounts || item.hideAmounts == true { return true }
        // A combined overview must not disclose individually hidden account amounts.
        if item.kind == .ownFunds {
            let hidden = Set(s.db.accounts.filter { $0.hideAmounts == true }.map(\.id))
            if s.includedAccounts.contains(where: { hidden.contains($0.id) }) { return true }
            if !hidden.isEmpty && ops.contains(where: { hidden.contains($0.account) || ($0.kind == .transfer && hidden.contains($0.destination)) }) { return true }
        }
        return false
    }
    func display(_ n:Int64)->String { masked ? "••••" : s.displayed(n) }
    func visible(_ n:Int64,_ code:String = "UAH")->String { masked ? "••••" : s.visibleMoney(n,code) }
    var showCharts:Bool { s.db.preferences?.noCharts == false && !masked }
    var detailed: Bool { item.size == .large }
    var compact: Bool { item.size == .small }
    var collapsed: Bool { (s.db.preferences?.collapsedDashboard ?? []).contains(item.id) }
    var tileSpacing: CGFloat { compact ? 6 : detailed ? 16 : 10 }
    var tilePadding: CGFloat { compact ? 10 : detailed ? (s.db.preferences?.modernCompactSpacing == true ? 14 : 20) : 12 }
    var tileMinHeight: CGFloat { compact ? 80 : detailed ? 154 : 108 }
    var color: Color {
        let p = s.db.preferences ?? .init()
        if let name = item.accentName, let custom = IzanamiTheme.all.first(where: {$0.name == name}) { return custom.color }
        if item.kind == .ownFunds { return finamiDesignAccent(p.designAccent) ?? (FinamiDesign(rawValue:p.design ?? "Signature") ?? .signature).tint }
        return (p.colorfulDashboard ?? true) ? item.kind.tileColor : (IzanamiTheme.all.first(where:{$0.name==p.theme})?.color ?? (FinamiDesign(rawValue:p.design ?? "Signature") ?? .signature).tint)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: tileSpacing) {
            if collapsed {
                let summary = collapsedSummary
                if item.kind == .review {
                    NavigationLink { reviewDestination } label: {
                        FinamiCollapsedDashboardCard(title:item.kind.title,summary:"\(reviewCount) · " + (reviewCount == 0 ? "Усе уточнено" : "Відкрити операції"),icon:item.kind.icon,tint:color,template:item.template)
                    }.buttonStyle(.plain).accessibilityLabel("Потребують уточнення").accessibilityValue(String(reviewCount)).accessibilityIdentifier("qa.dashboard.review.collapsed")
                } else {
                    Button { toggleCollapsed() } label: {
                        FinamiCollapsedDashboardCard(title:item.kind.title,summary:summary,icon:item.kind.icon,tint:color,template:item.template)
                    }.buttonStyle(.plain).accessibilityLabel("Розгорнути " + item.kind.title).accessibilityValue(summary).accessibilityIdentifier("qa.dashboard.collapsed." + item.id)
                }
            } else {
            if small {
                HStack {FinamiIconTile(icon:item.kind.icon,tint:color,side:32);Spacer(minLength:0);privacyButton}
                tileTitle
            } else if item.kind == .accounts {
                HStack(alignment:.center,spacing:8) {
                    FinamiIconTile(icon:item.kind.icon,tint:color,side:36)
                    tileTitle.frame(maxWidth:.infinity,alignment:.leading)
                    Button { accountSettings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:44,height:44) }.buttonStyle(.plain).accessibilityLabel("Налаштування карток рахунків").accessibilityIdentifier("qa.home.accounts.settings")
                    privacyButton
                }.padding(.horizontal, 4).padding(.vertical, 2)
            } else {
                HStack(alignment:.center,spacing:9){FinamiIconTile(icon:item.kind.icon,tint:color,side:compact ? 28 : detailed ? 44 : 36);tileTitle;Spacer(minLength:0);privacyButton}
            }
            content
            }
        }
        .frame(maxWidth: .infinity, minHeight: item.kind == .accounts || collapsed ? nil : tileMinHeight, alignment: .topLeading)
        .padding(item.kind == .accounts || collapsed ? 0 : tilePadding)
        .modifier(FinamiDashboardSurface(isAccounts: item.kind == .accounts || collapsed, tint: color, template: item.template, aurora: item.kind == .ownFunds))
        .environment(\.finamiMask, masked)
        .contextMenu { Button(collapsed ? "Розгорнути блок" : "Згорнути блок") { toggleCollapsed() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qa.dashboard.tile." + item.id)
        .sheet(item:$paymentDetails) { FinamiPaymentDetails(payment:$0).environment(\.finamiMask, masked || (s.db.preferences?.designHiddenSubscriptions ?? []).contains($0.id)) }
        .sheet(isPresented:$accountSettings) { NavigationStack { FinamiHomeAccountsSettings().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Готово") { accountSettings = false } } } } }
    }
    private var reviewOperations: [Operation] { s.db.operations.filter { $0.needsCaptureAttention } }
    private var reviewCount: Int { reviewOperations.count + s.capturePending.count }
    private var reviewDestination: some View {
        FinamiReportReviewList(ids: reviewOperations.map(\.id), account: nil, maskAmounts: masked, includeInbox: true)
    }
    private var titleLabel: some View {
        Text(item.kind == .accounts ? "Мої рахунки" : item.kind.title)
            .font(small ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(small ? Color.secondary : Color.primary)
            .fixedSize(horizontal:false,vertical:true).frame(minHeight:44,alignment:.leading)
    }
    @ViewBuilder private var tileTitle: some View {
        if item.kind == .review {
            NavigationLink { reviewDestination } label: { titleLabel }
                .buttonStyle(.plain).accessibilityIdentifier("qa.dashboard.review.title")
        } else {
            Button { toggleCollapsed() } label: { titleLabel }
                .buttonStyle(.plain).accessibilityLabel("Згорнути " + item.kind.title)
        }
    }
    private var collapsedSummary: String {
        if masked { return "Суми приховано" }
        if item.kind == .accounts {
            return FinamiDashboardPreviewPolicy.accounts(count:s.db.accounts.filter{$0.hiddenInOverview != true}.count,masked:false)
        }
        let payments: [FinamiPayment]
        switch item.kind {
        case .obligations: payments = s.upcomingPayments
        case .subscriptions: payments = s.upcomingPayments.filter(\.subscription)
        case .installments: payments = s.upcomingPayments.filter { $0.kind == ObligationKind.installment.title }
        case .recurring: payments = s.upcomingPayments.filter { $0.subscription || $0.kind == ObligationKind.recurring.title || $0.kind == ObligationKind.installment.title }
        default: return "Натисни, щоб розгорнути"
        }
        let next = payments.first
        let prefs = s.db.preferences ?? .init()
        let dateText = item.showPaymentDate == false || (item.kind == .obligations && !prefs.designShowsUpcoming("date")) ? nil : next.map { $0.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier:"uk_UA"))) }
        let amountText = item.showPaymentTotal == false || (item.kind == .obligations && !prefs.designShowsUpcoming("amount")) ? nil : next.map { (prefs.designHiddenSubscriptions ?? []).contains($0.id) ? "••••" : visible($0.amount,$0.currency) }
        return FinamiDashboardPreviewPolicy.payments(count:payments.count,nextAmount:amountText,nextDate:dateText,overdue:next?.overdue == true,masked:false)
    }
    private func toggleCollapsed() { s.changeAppearance { p in var ids = Set(p.collapsedDashboard ?? []); if ids.contains(item.id) { ids.remove(item.id) } else { ids.insert(item.id) }; p.collapsedDashboard = ids.sorted() } }
    var privacyButton: some View {
        Button { s.change { d in var all=DashboardItem.merged(d.dashboard);if let i=all.firstIndex(where:{$0.id==item.id}){all[i].hideAmounts = !(all[i].hideAmounts ?? false)};d.dashboard=all } } label:{Image(systemName:masked ? "eye.slash" : "eye").frame(minWidth:44,minHeight:44)}.buttonStyle(.plain).accessibilityLabel("Показати або приховати суми блоку").disabled(s.privateAmounts).accessibilityIdentifier("qa.dashboard.hide." + item.id)
    }
    var cardBackground: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            if item.kind == .balance {
                LinearGradient(colors: [color.opacity(0.18), color.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    func value(_ text: String) -> some View {
        Text(text).font(compact ? .title3.weight(.semibold) : detailed ? .largeTitle.weight(.bold) : .title.weight(.bold))
            .monospacedDigit().lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.68)
            .foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder func amount(_ n: Int64) -> some View {
        let pieces = display(n).components(separatedBy: " · ")
        value(pieces.first ?? money(n))
        if pieces.count > 1 {
            Text(pieces[1]).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
    func detail(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    func metric(_ title: String, _ n: Int64, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(display(n)).font(.headline).monospacedDigit().foregroundStyle(tint)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var overviewFlowMetrics: some View {
        if s.db.preferences?.showIncome == true { metric("Доходи", inc, .green) }
        if s.db.preferences?.showExpenses != false { metric("Витрати", exp, .orange) }
    }
    var cashFlow: some View {
        VStack(alignment:.leading,spacing:12) {
            if s.db.preferences?.showIncome == true { metric("Доходи",inc,.green) }
            if s.db.preferences?.showExpenses != false { metric("Витрати",exp,.orange) }
            if s.db.preferences?.showIncome != true && s.db.preferences?.showExpenses == false { detail("Показники приховано") }
        }
    }
    var categoryGroups: [(key: String, value: Int64)] {
        metrics.categories.filter { item.categorySelection?.contains($0.key) ?? true }
    }
    var categories: some View {
        let groups = categoryGroups
        let total = groups.reduce(Int64(0)) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 11) {
            if groups.isEmpty { detail("Немає витрат за період") }
            else if compact { amount(item.categorySelection == nil ? exp : total); detail("Категорій: \(groups.count)") }
            else {
                amount(item.categorySelection == nil ? exp : total)
                ForEach(Array(groups.prefix(max(1,min(30,item.categoryCount ?? (detailed ? 10 : 4)))).enumerated()), id: \.element.key) { entry in
                    DashboardCategoryLine(title: entry.element.key, amount: entry.element.value, total: total, color: categoryColor(entry.offset), showChart:showCharts)
                }
                if groups.count > (item.categoryCount ?? (detailed ? 10 : 4)) { detail("Показано найбільші категорії") }
            }
        }
    }
    func categoryColor(_ index: Int) -> Color {
        let palette: [Color] = [.purple, .teal, .blue, .orange, .pink, .green, .indigo, .cyan]
        return (s.db.preferences?.colorfulDashboard ?? true) ? palette[index % palette.count] : color
    }
    @ViewBuilder var accounts: some View {
        let shown = finamiOrderedAccounts(s.db.accounts).filter { $0.hiddenInOverview != true }
        if shown.isEmpty { detail("Немає рахунків. Додай рахунок у вкладці «Рахунки» або увімкни його в налаштуваннях блоку.") }
        if (s.db.preferences ?? .init()).finamiLayout != "cards" {
            FinamiCompactAccountsGrid(accounts:shown,mode:"all",date:date,template:item.template)
        } else {
            VStack(spacing: 10) { ForEach(shown) { a in FinamiHomeAccountCard(accountID:a.id,date:date,fallbackTint:color,dashboardSize:item.size,template:item.template) } }
        }
    }
    @ViewBuilder var content: some View {
        switch item.kind {
        case .balance: amount(balance); detail("Чистий баланс рахунків · без невикористаного кредиту")
        case .creditLimit: amount(s.totalCreditLimit);detail("Ліміт усіх включених кредитних рахунків")
        case .creditPortfolio: FinamiCreditSummary(showLimit:item.showLimit ?? true,showUsed:item.showUsed ?? true,showAvailable:item.showAvailable ?? true, dashboardSize: item.size)
        case .allAvailable: amount(s.totalOwnFunds+s.totalAvailableCredit);detail("Власні кошти разом із доступним кредитом")
        case .monthlyPayments: FinamiMonthPayments(dashboardSize: item.size)
        case .paymentCalendar: FinamiCalendarGrid(compact: compact, masked: masked)
        case .cashflow: cashFlow
        case .categories: categories
        case .recent:
            if ops.isEmpty { detail("Немає операцій") }
            else {
                let shown = Array(metrics.recent.prefix(compact ? 1 : detailed ? 5 : 2))
                ForEach(shown) { o in
                    if small { Text(visible(o.amount)).font(.subheadline.weight(.semibold)).monospacedDigit(); detail(o.note.isEmpty ? o.category : o.note) }
                    else { OperationRow(o: o) }
                    if o.id != shown.last?.id { Divider() }
                }
            }
        case .accounts: accounts
        case .budget:
            if s.db.budget > 0 {
                amount(max(0,s.db.budget-exp)); detail("Залишок бюджету · з \(visible(s.db.budget))")
                if showCharts { ProgressView(value: max(0,min(1, Double(exp)/Double(s.db.budget)))).tint(color) }
            } else { detail("Не задано") }
        case .obligations:
            FinamiUpcomingDesign(item: item, open: { paymentDetails = $0 })
        case .subscriptions: paymentSummary(s.upcomingPayments.filter(\.subscription), showRemaining: false)
        case .reminders: value(String((s.db.reminders ?? []).filter{$0.enabled && $0.date > Date()}.count)); detail("Майбутніх нагадувань")
        case .forecast:
            if let f=s.db.forecast {
                let snapshot=s.planningSnapshot(f)
                if let projection=snapshot.projection {
                    amount(projection.closing); detail("Прогнозований залишок · \(f.days) днів")
                    if snapshot.unknown > 0 { detail("Прогноз неповний: немає курсу") }
                    else { metric("Орієнтир на день",projection.safeDaily,.teal) }
                } else { detail("Перевір параметри прогнозу") }
            } else { detail("За бажанням") }
            NavigationLink("Налаштувати прогноз") { FinamiPlanningView() }
        case .uncategorized: value(String(ops.filter{$0.category == "Без категорії"}.count)); detail("Операцій без категорії")
        case .goals: obligationSummary([.goal])
        case .debt: metric("Мені винні", s.db.obligations.filter{$0.kind == .owed}.reduce(0){$0+$1.remaining}, .green); metric("Я винен", s.db.obligations.filter{$0.kind == .owe}.reduce(0){$0+$1.remaining}, .orange)
        case .installments: paymentSummary(s.upcomingPayments.filter { $0.kind == ObligationKind.installment.title }, showRemaining: true)
        case .recurring: paymentSummary(s.upcomingPayments.filter { $0.subscription || $0.kind == ObligationKind.recurring.title || $0.kind == ObligationKind.installment.title }, showRemaining: false)
        case .statistics: value(String(ops.count)); detail("Операцій · потік \(visible(inc-exp))")
        case .fees: amount(ops.filter{$0.kind == .expense && $0.category == "🏦 Комісії"}.reduce(0){$0+$1.amount})
        case .ownFunds:
            amount(s.totalOwnFunds); detail("Без кредитних коштів")
            if s.db.preferences?.showIncome == true || s.db.preferences?.showExpenses != false {
                Divider().padding(.vertical, 2)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) { overviewFlowMetrics }
                } else {
                    HStack(alignment: .top, spacing: 12) { overviewFlowMetrics }
                }
            }
        case .creditDebt: amount(s.totalAccountDebt); detail("Використані кредитні кошти")
        case .availableCredit: amount(s.totalAvailableCredit); detail("Не є власними коштами")
        case .review:
            NavigationLink { reviewDestination } label: {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        value(String(reviewCount))
                        detail(reviewCount == 0 ? "Усе уточнено" : "Необхідна увага · відкрити")
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Уточнити операції").accessibilityValue(String(reviewCount)).accessibilityIdentifier("qa.dashboard.review.open")
        case .savings: value(masked ? "••••" : inc > 0 ? ((Double(inc-exp)/Double(inc)).formatted(.percent.precision(.fractionLength(1)))) : "—"); detail("Частка доходу після витрат")
        }
    }
    @ViewBuilder func paymentSummary(_ payments: [FinamiPayment], showRemaining: Bool) -> some View {
        if payments.isEmpty { detail("Немає активних платежів") }
        else {
            let remainingMode = showRemaining && item.showPaymentRemaining != false
            let interval = Calendar.current.dateInterval(of: .month, for: date)
            let ids = Set(payments.map(\.id))
            let planned = interval.map { s.calendarEvents(interval:$0).filter { event in !event.paid && ids.contains(event.paymentID) } } ?? []
            if item.showPaymentTotal != false {
                ForEach(Array(Set(payments.map(\.currency))).sorted(), id: \.self) { code in
                    let total = remainingMode ? payments.filter { $0.currency == code }.reduce(Int64(0)) { $0 + ($1.remaining ?? $1.amount) } : planned.filter { $0.currency == code }.reduce(Int64(0)) { $0 + $1.amount }
                    Text(payments.contains { (s.db.preferences?.designHiddenSubscriptions ?? []).contains($0.id) && $0.currency == code } ? "••••" : visible(total, code)).font(.title2.bold()).monospacedDigit()
                }
                detail(remainingMode ? "Залишок боргу" : "Неоплачене за графіком · " + monthName(date))
            }
            if item.showPaymentNames != false {
                ForEach(Array(payments.prefix(max(1, min(20, item.categoryCount ?? (compact ? 1 : detailed ? 6 : 3)))))) { p in
                    Button { paymentDetails = p } label: {
                        let loan = s.db.obligations.first { $0.id == p.id }
                        FinamiModernPaymentRow(name:p.name,kind:p.kind,date:p.date,currency:p.currency,due:p.amount,total:loan?.target,monthly:loan?.monthly,remaining:p.remaining,status:p.overdue ? "Прострочено" : "Очікує оплати",showDate:item.showPaymentDate != false,showImage:item.showPaymentImage != false,showRemaining:remainingMode,masked:masked || (s.db.preferences?.designHiddenSubscriptions ?? []).contains(p.id))
                    }.buttonStyle(.plain)
                }

            }
            FinamiAllPaymentsLink(count: payments.count, filter: item.kind == .installments ? "installments" : item.kind == .subscriptions ? "subscriptions" : "recurring", masked: masked)
            if item.showPaymentTotal == false && item.showPaymentNames == false { detail("Показники приховано") }
        }
    }
    @ViewBuilder func obligationSummary(_ kinds: [ObligationKind]) -> some View {
        let matching = s.db.obligations.filter { kinds.contains($0.kind) }
        amount(matching.reduce(0){$0+$1.remaining}); detail("\(matching.count) записів")
    }
}
struct DashboardCategoryLine: View {
    @EnvironmentObject var s:Store
    @Environment(\.finamiMask) private var masked
    var title: String; var amount: Int64; var total: Int64; var color: Color; var showChart: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.subheadline).lineLimit(2)
                Spacer(minLength: 3)
                Text(masked ? "••••" : s.visibleMoney(amount)).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            if showChart && !s.privateAmounts && !masked { ProgressView(value: total > 0 ? min(1, max(0, Double(amount)/Double(total))) : 0).tint(color).accessibilityLabel(title).accessibilityValue(money(amount)) }
        }
    }
}

struct ForecastPreferences: Codable { var expected: Int64 = 0; var planned: Int64 = 0; var reserve: Int64 = 0; var days: Int = 30; var daily: Int64? = nil; var incomeDate: Date? = nil; var includeSchedule: Bool? = nil }
struct ForecastView: View { var body: some View { FinamiPlanningView() } }
enum ReminderRepeat: String, Codable, CaseIterable { case once = "Один раз", daily = "Щодня", weekly = "Щотижня", monthly = "Щомісяця", yearly = "Щороку" }
struct PersonalReminder: Codable, Identifiable {
    var id = UUID().uuidString
    var title = ""; var date = Date(); var linkedID: String? = nil; var enabled = true; var recurrence: ReminderRepeat = .once; var hideDetails = false
    var requestID: String { "izanami.reminder." + id }
}
@MainActor enum ReminderScheduler {
    static func cancel(_ r: PersonalReminder) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [r.requestID]); UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [r.requestID]) }
    static func schedule(_ r: PersonalReminder) async throws {
        let center = UNUserNotificationCenter.current()
        if !r.enabled { cancel(r); return }
        guard try await center.requestAuthorization(options: [.alert,.sound,.badge]) else { throw ReminderFailure.denied }
        guard r.recurrence != .once || r.date > Date() else { throw ReminderFailure.past }
        let cal = Calendar.current
        let fields: Set<Calendar.Component>
        switch r.recurrence { case .once: fields = [.year,.month,.day,.hour,.minute]; case .daily: fields = [.hour,.minute]; case .weekly: fields = [.weekday,.hour,.minute]; case .monthly: fields = [.day,.hour,.minute]; case .yearly: fields = [.month,.day,.hour,.minute] }
        // A calendar recurrence starts at its next matching occurrence, not necessarily at the selected future date.
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents(fields, from: r.date), repeats: r.recurrence != .once)
        guard trigger.nextTriggerDate() != nil else { throw ReminderFailure.past }
        let c = UNMutableNotificationContent(); c.title = "Finami · Нагадування"; c.body = r.hideDetails ? "Відкрий застосунок, щоб переглянути платіж." : r.title; c.sound = .default
        try await center.add(UNNotificationRequest(identifier: r.requestID, content: c, trigger: trigger))
    }
    enum ReminderFailure: LocalizedError { case denied,past; var errorDescription: String? { self == .denied ? "Дозволь сповіщення Finami в налаштуваннях iPhone." : "Вибери майбутню дату й час." } }
}
struct ReminderList: View {
    @EnvironmentObject var s: Store
    var body: some View {
        List {
            ForEach((s.db.reminders ?? []).sorted{$0.date < $1.date}) { r in
                NavigationLink { ReminderEditor(original: r) } label: { VStack(alignment: .leading) { IzanamiLabel(title: r.title, icon: r.enabled ? "bell.fill" : "bell.slash", color: .red); Text(r.date.formatted(date:.abbreviated,time:.shortened) + " · " + r.recurrence.rawValue).font(.caption).foregroundStyle(.secondary) } }
            }.onDelete { offsets in let sorted = (s.db.reminders ?? []).sorted{$0.date < $1.date}; let selected = offsets.map{sorted[$0]}; if s.change({d in d.reminders = (d.reminders ?? []).filter{r in !selected.contains{$0.id == r.id}} }) { selected.forEach{ReminderScheduler.cancel($0)} } }
            NavigationLink { ReminderEditor(original: PersonalReminder(date: Date().addingTimeInterval(3600))) } label: { Label("Нове нагадування", systemImage: "plus.circle.fill") }
            Text("Нагадування локальні. Після відновлення бази на іншому пристрої відкрий та збережи їх повторно.").font(.caption)
        }.navigationTitle("Нагадування")
    }
}
struct ReminderEditor: View {
    @EnvironmentObject var s: Store; @Environment(\.dismiss) var dismiss
    @State var r: PersonalReminder; @State private var busy = false
    init(original: PersonalReminder) { _r = State(initialValue: original) }
    var body: some View {
        Form {
            TextField("Назва", text: $r.title)
            Toggle("Увімкнено", isOn: $r.enabled)
            DatePicker("Дата та час", selection: $r.date, displayedComponents: [.date,.hourAndMinute])
            Picker("Повторення", selection: $r.recurrence) { ForEach(ReminderRepeat.allCases, id: \.self){Text($0.rawValue).tag($0)} }
            if r.recurrence != .once { Text("Повторення починається з найближчого відповідного дня й часу; для конкретної майбутньої дати обери «Один раз».").font(.caption) }
            Toggle("Приховувати деталі", isOn: $r.hideDetails)
            Button("Зберегти нагадування") {
                busy = true
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        try await ReminderScheduler.schedule(r)
                        if s.change({d in var all = d.reminders ?? []; all.removeAll{$0.id == r.id}; all.append(r); d.reminders = all}) { dismiss() } else { ReminderScheduler.cancel(r) }
                    } catch { s.error = error.localizedDescription }
                }
            }.disabled(busy || r.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }.navigationTitle("Нагадування")
    }
}
enum SubscriptionPeriod: String, Codable, CaseIterable { case week = "Тиждень", month = "Місяць", year = "Рік"; var component: Calendar.Component { self == .week ? .day : self == .month ? .month : .year }; var step: Int { self == .week ? 7 : 1 } }
struct SubscriptionPayment: Codable, Identifiable { var id = UUID().uuidString; var date: Date; var amount: Int64; var currency: String; var through: Date }
struct SubscriptionRecord: Codable, Identifiable {
    var id = UUID().uuidString; var name = ""; var amount: Int64 = 0; var currency = "UAH"; var period: SubscriptionPeriod = .month; var next = Date(); var active = true; var automatic = false; var notes = ""; var payments: [SubscriptionPayment] = []
}
func currencyMoney(_ amount: Int64, _ currency: String) -> String { (Double(amount)/100).formatted(.currency(code: currency).locale(Locale(identifier:"uk_UA"))) }
struct SubscriptionsView: View {
    @EnvironmentObject var s: Store; @State private var edit: SubscriptionRecord?
    @State private var subscriptionFilter = "all"
    var list: [SubscriptionRecord] { (s.db.subscriptions ?? []).sorted{$0.next < $1.next} }
    var body: some View {
        List {
            Section { NavigationLink("Виявити підписки за операціями") { FinamiRecurringSuggestionsView() } }
            Section("Активні") { ForEach(["UAH","USD"], id: \.self) { currency in let active = list.filter{$0.active && $0.currency == currency}; if !active.isEmpty { let total = active.reduce(0.0) { n,r in n + Double(r.amount) * (r.period == .week ? 52.0/12 : r.period == .year ? 1.0/12 : 1) }; LabeledContent("Місячна оцінка \(currency)", value: (s.db.preferences?.designHiddenSubscriptions ?? []).isEmpty ? s.visibleMoney(FinamiDesignPolicy.safeMinor(total),currency) : "••••") } } }
            if s.db.preferences?.designStyle(for: "subscriptions") == "subscriptionPro" {
                Section("Річна оцінка") { ForEach(["UAH", "USD"], id: \.self) { code in
                    let active = list.filter { $0.active && $0.currency == code }
                    if !active.isEmpty { LabeledContent(code, value: active.contains { (s.db.preferences?.designHiddenSubscriptions ?? []).contains($0.id) } ? "••••" : s.visibleMoney(FinamiDesignPolicy.safeMinor(active.reduce(0.0) { $0 + Double($1.amount) * FinamiDesignPolicy.annualFactor($1.period.rawValue) }),code)) }
                } }
            }
            Picker("Стан", selection: $subscriptionFilter) { Text("Усі").tag("all"); Text("Активні").tag("active"); Text("На паузі").tag("paused") }.pickerStyle(.segmented)
            ForEach(list.filter { subscriptionFilter == "all" || (subscriptionFilter == "active" ? $0.active : !$0.active) }) { r in
                let collapsed = s.db.preferences?.isDesignCardCollapsed(r.id, subscription: true) ?? false
                HStack(spacing: 4) {
                    Button { edit = r } label: {
                        FinamiSubscriptionDesign(record: r, collapsed: collapsed)
                    }.buttonStyle(.plain)
                    Button { s.changeAppearance { p in var ids = Set(p.designHiddenSubscriptions ?? []); if ids.contains(r.id) { ids.remove(r.id) } else { ids.insert(r.id) }; p.designHiddenSubscriptions = ids.sorted() } } label: { Image(systemName: (s.db.preferences?.designHiddenSubscriptions ?? []).contains(r.id) ? "eye.slash" : "eye").frame(minWidth:44,minHeight:44) }.buttonStyle(.borderless).accessibilityLabel("Видимість суми підписки")
                    Button { s.changeAppearance { $0.toggleDesignCard(r.id, subscription: true) } } label: {
                        Image(systemName:collapsed ? "chevron.down" : "chevron.up").frame(minWidth:44,minHeight:44)
                    }.buttonStyle(.borderless).accessibilityLabel(collapsed ? "Розгорнути підписку" : "Згорнути підписку").accessibilityIdentifier("qa.subscription.collapse." + r.id)
                }
            }
        }.navigationTitle("Підписки").toolbar { Button { edit = SubscriptionRecord() } label: { Image(systemName:"plus.circle.fill").font(.title2) } }.sheet(item:$edit){ SubscriptionEditor(original:$0) }
    }
}
struct SubscriptionEditor: View {
    @EnvironmentObject var s: Store; @Environment(\.dismiss) var dismiss
    @State var r: SubscriptionRecord; @State var amount: String; @State private var payment = ""; @State private var paidDate = Date(); @State private var confirm = false
    init(original: SubscriptionRecord) { _r = State(initialValue:original); _amount = State(initialValue:amountText(original.amount)) }
    var valid: Bool { !r.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && (cents(amount) ?? 0)>0 }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Назва сервісу",text:$r.name)
                FinamiField("Тариф", text: $amount, keyboard: .decimalPad)
                Picker("Валюта",selection:$r.currency){Text("UAH").tag("UAH");Text("USD").tag("USD")}
                Picker("Період",selection:$r.period){ForEach(SubscriptionPeriod.allCases,id:\.self){Text($0.rawValue).tag($0)}}
                DatePicker("Наступна оплата",selection:$r.next,displayedComponents:.date)
                Toggle("Активна",isOn:$r.active); Toggle("Автосписання в сервісі",isOn:$r.automatic)
                TextField("Примітка",text:$r.notes)
                Section("Оформлення") {
                    Picker("Іконка", selection: Binding(get: { s.db.preferences?.designSubscriptionIcons?[r.id] ?? "auto" }, set: { v in s.changeAppearance { p in var values = p.designSubscriptionIcons ?? [:]; values[r.id] = v; p.designSubscriptionIcons = values } })) {
                        Text("Автоматично").tag("auto")
                        ForEach(["repeat", "tv", "music.note", "cloud", "play.rectangle", "gamecontroller", "book", "star"], id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                    Picker("Колір", selection: Binding(get: { s.db.preferences?.designSubscriptionColors?[r.id] ?? "auto" }, set: { v in s.changeAppearance { p in var values = p.designSubscriptionColors ?? [:]; values[r.id] = v; p.designSubscriptionColors = values } })) {
                        Text("Автоматично").tag("auto")
                        ForEach(FinamiDesignPolicy.accents, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Історія оплат") {
                    ForEach(r.payments.sorted{$0.date > $1.date}) { p in VStack(alignment:.leading){Text(s.visibleMoney(p.amount,p.currency)).bold();Text("Сплачено: \(p.date.formatted(date:.abbreviated,time:.omitted)) · До: \(p.through.formatted(date:.abbreviated,time:.omitted))").font(.caption)} }
                    DatePicker("Дата фактичної оплати",selection:$paidDate,displayedComponents:.date)
                    FinamiField("Фактична сума (необов’язково)", text: $payment, keyboard: .decimalPad)
                    Button("Записати оплату") { guard let n = cents(payment.isEmpty ? amount : payment), n > 0 else { return }; let base = max(r.next,paidDate); let end = Calendar.current.date(byAdding:r.period.component,value:r.period.step,to:base) ?? base; r.payments.append(.init(date:paidDate,amount:n,currency:r.currency,through:end));r.next=end;payment="" }.disabled(!valid || (!payment.isEmpty && (cents(payment) ?? 0)<=0))
                    Text("Історія підписки не додає витрати в рахунок автоматично, щоб не подвоїти банківську операцію.").font(.caption)
                }
                if s.db.subscriptions?.contains(where:{$0.id == r.id}) == true {
                    NavigationLink("Додати нагадування") { ReminderEditor(original:.init(title:r.name,date:r.next,linkedID:r.id)) }
                    Button("Видалити підписку",role:.destructive){confirm=true}
                }
            }.navigationTitle("Підписка").toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Зберегти"){guard let n=cents(amount),valid else{return};r.amount=n;if s.change({d in var all=d.subscriptions ?? [];all.removeAll{$0.id == r.id};all.append(r);d.subscriptions=all}){dismiss()}}.disabled(!valid)}
            }.confirmationDialog("Видалити підписку?",isPresented:$confirm){Button("Видалити",role:.destructive){let linked=(s.db.reminders ?? []).filter{$0.linkedID == r.id};if s.change({d in d.subscriptions?.removeAll{$0.id == r.id};d.reminders?.removeAll{$0.linkedID == r.id}}){linked.forEach{ReminderScheduler.cancel($0)};dismiss()}}}
        }
    }
}

extension URL {
    var resourceValuesDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}
struct SnapshotView: View {
    @EnvironmentObject var s: Store
    @State private var selected: URL?; @State private var confirm = false
    var body: some View {
        List {
            Text("До 12 попередніх версій фінансової бази зберігаються перед фінансовими змінами. Оформлення зберігається окремо до наступного запису бази. Вони не захищають від видалення застосунку. Для цього експортуй JSON у «Файли».").font(.caption)
            ForEach(s.snapshotURLs(), id: \.self) { u in
                Button { selected = u; confirm = true } label: { Text((u.resourceValuesDate ?? Date.distantPast).formatted(date:.abbreviated,time:.standard)) }
            }
        }.navigationTitle("Локальні копії").confirmationDialog("Замінити поточні дані попередньою копією?",isPresented:$confirm){Button("Відновити",role:.destructive){if let selected { do { s.restore(try Data(contentsOf:selected)) } catch { s.error=error.localizedDescription } } };Button("Скасувати",role:.cancel){} }
    }
}
struct CurrencyCalculator: View {
    @State private var amount = ""; @AppStorage("izanami.converter.rate") private var rate = ""; @State private var usd = true
    var result: Double? { guard let a = cents(amount), a >= 0, let r = Double(rate.replacingOccurrences(of:",",with:".")), r.isFinite, r > 0 else { return nil }; let value = usd ? Double(a)/100*r : Double(a)/100/r; return value.isFinite ? value : nil }
    var body: some View {
        Form {
            Picker("Напрямок",selection:$usd){Text("USD → UAH").tag(true);Text("UAH → USD").tag(false)}.pickerStyle(.segmented)
            FinamiField("Сума", text: $amount, keyboard: .decimalPad)
            FinamiField("Власний курс: грн за 1 USD", text: $rate, keyboard: .decimalPad)
            if let result { Text(result.formatted(.currency(code:usd ? "UAH" : "USD").locale(Locale(identifier:"uk_UA")))).font(.largeTitle.bold()) }
            Text("Довідковий калькулятор. Не створює валютної операції та не змінює баланс.").font(.caption)
        }.navigationTitle("Конвертер валют")
    }
}

struct CurrencySettings: View {
    @EnvironmentObject var s:Store
    @State private var rate=""; @State private var display="dual"
    var body:some View {
        Form {
            Section("Поточний курс") { FinamiField("UAH за 1 USD", text: $rate, keyboard: .decimalPad);Text("Використовується для оцінки залишків і довідкового відображення. Старі операції зберігають власний курс.").font(.caption) }
            Picker("Відображення огляду",selection:$display){Text("Гривня").tag("UAH");Text("Долар (еквівалент)").tag("USD");Text("Обидві").tag("dual")}
            Button("Зберегти"){s.change{$0.currencyPreferences=CurrencyPreferences(usdRate:rate,display:display)}}.disabled(fxRate(rate)==nil)
            Section("Операції цього місяця за оригінальною валютою") {ForEach(["UAH","USD"],id:\.self){code in let ops=s.month(Date()).filter{($0.originalCurrency ?? "UAH")==code}; LabeledContent("Дохід \(code)",value:s.visibleMoney(ops.filter{$0.countsAsIncome}.reduce(0){$0+($1.originalAmount ?? $1.amount)},code)); LabeledContent("Витрати \(code)",value:s.visibleMoney(ops.filter{$0.kind == .expense}.reduce(0){$0+($1.originalAmount ?? $1.amount)},code))}}
            Section("Окремі залишки") {ForEach(["UAH","USD"],id:\.self){code in LabeledContent(code,value:s.visibleMoney(s.db.accounts.filter{$0.code==code}.reduce(0){$0+s.nativeBalance($1)},code))}}
            Text("Щоб записати доларовий дохід, створи рахунок USD або вибери USD при введенні операції на рахунку UAH. Для обміну обери переказ між рахунками різних валют і фактичний курс.").font(.caption)
        }.navigationTitle("Валюти та курси").onAppear {rate=s.db.currencyPreferences?.usdRate ?? "";display=s.db.currencyPreferences?.display ?? "dual"}
    }
}
