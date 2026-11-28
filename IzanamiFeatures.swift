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
struct ForecastPreferences: Codable { var expected: Int64 = 0; var planned: Int64 = 0; var reserve: Int64 = 0; var days: Int = 30; var daily: Int64? = nil; var incomeDate: Date? = nil; var includeSchedule: Bool? = nil }
struct ForecastView: View { var body: some View { FinamiPlanningView() } }
enum ReminderRepeat: String, Codable, CaseIterable { case once = "Один раз", daily = "Щодня", weekly = "Щотижня", monthly = "Щомісяця", yearly = "Щороку" }
struct PersonalReminder: Codable, Identifiable {
    var id = UUID().uuidString
    var title = ""; var date = Date(); var linkedID: String? = nil; var enabled = true; var recurrence: ReminderRepeat = .once; var hideDetails = false
    var requestID: String { "izanami.reminder." + id }
}
enum SubscriptionPeriod: String, Codable, CaseIterable { case week = "Тиждень", month = "Місяць", year = "Рік"; var component: Calendar.Component { self == .week ? .day : self == .month ? .month : .year }; var step: Int { self == .week ? 7 : 1 } }
struct SubscriptionPayment: Codable, Identifiable { var id = UUID().uuidString; var date: Date; var amount: Int64; var currency: String; var through: Date }
struct SubscriptionRecord: Codable, Identifiable {
    var id = UUID().uuidString; var name = ""; var amount: Int64 = 0; var currency = "UAH"; var period: SubscriptionPeriod = .month; var next = Date(); var active = true; var automatic = false; var notes = ""; var payments: [SubscriptionPayment] = []
}
func currencyMoney(_ amount: Int64, _ currency: String) -> String { (Decimal(amount)/100).formatted(.currency(code: currency).locale(Locale(identifier:"uk_UA"))) }
extension URL {
    var resourceValuesDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}
struct SnapshotView: View {
    @EnvironmentObject var s: Store
    @State private var selected: URL?; @State private var confirm = false
    var body: some View {
        List {
            Text("Зберігаються до 12 останніх, щоденні за 14 днів, щотижневі за 4 календарні тижні та до 8 захищених точок перед важливими змінами. Частина копій збігається. Оформлення зберігається окремо до наступного запису бази. Вони не захищають від видалення застосунку. Для цього експортуй JSON у «Файли».").font(.caption)
            ForEach(s.snapshotURLs(), id: \.self) { u in
                Button { selected = u; confirm = true } label: { Text((u.resourceValuesDate ?? Date.distantPast).formatted(date:.abbreviated,time:.standard)) }
            }
        }.navigationTitle("Локальні копії").confirmationDialog("Замінити поточні дані попередньою копією?",isPresented:$confirm){Button("Відновити",role:.destructive){if let selected { s.restoreSnapshot(selected) } };Button("Скасувати",role:.cancel){} }
    }
}
struct CurrencyCalculator: View {
    @State private var amount = ""; @AppStorage("izanami.converter.rate") private var rate = ""; @State private var usd = true
    var result: Int64? { guard let a = cents(amount), a >= 0, let r = fxRate(rate) else { return nil }; return fxMinor(a, rate: r, divide: !usd) }
    var body: some View {
        Form {
            Picker("Напрямок",selection:$usd){Text("USD → UAH").tag(true);Text("UAH → USD").tag(false)}.pickerStyle(.segmented)
            FinamiField("Сума", text: $amount, keyboard: .decimalPad)
            FinamiField("Власний курс: грн за 1 USD", text: $rate, keyboard: .decimalPad)
            if let result { Text(currencyMoney(result, usd ? "UAH" : "USD")).font(.largeTitle.bold()) }
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
