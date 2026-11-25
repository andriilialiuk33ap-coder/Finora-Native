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
    var menuCompact: Bool? = nil
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
    var preset: FinamiDesign { FinamiDesign(rawValue: p.design ?? "Signature") ?? .signature }
    var accent: Color { p.design != nil && p.theme == "Preset" ? preset.tint : IzanamiTheme.all.first(where: { $0.name == p.theme })?.color ?? preset.tint }
    var scheme: ColorScheme? { p.mode == "dark" ? .dark : p.mode == "light" ? .light : p.mode == "preset" ? preset.scheme : nil }
    var design: Font.Design { p.font == "rounded" ? .rounded : p.font == "serif" ? .serif : p.font == "monospaced" ? .monospaced : p.font == "preset" ? preset.font : .default }
    var body: some View {
        Root().tint(accent).preferredColorScheme(scheme).environment(\.font, .system(.body, design: design))
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
            FinamiArt(icon: icon, tint: tint, size: p.menuCompact == true ? 36 : 56)
            Text(title).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }.frame(minHeight: 46, alignment: .leading).padding(.vertical, 2)
    }
}
struct AppearanceView: View {
    @EnvironmentObject var s: Store
    func binding<T>(_ key: WritableKeyPath<AppearancePreferences,T>) -> Binding<T> {
        Binding(get: { (s.db.preferences ?? .init())[keyPath: key] }, set: { value in
            s.change { d in var p = d.preferences ?? .init(); p[keyPath: key] = value; d.preferences = p }
        })
    }
    @State private var preview: FinamiDesign?
    var body: some View {
        Form {
            Section("Десять дизайнів · натисни для перегляду") {
                ForEach(FinamiDesign.allCases) { preset in Button { preview=preset } label: { VStack(alignment:.leading,spacing:8) { FinamiDesignPreview(design:preset); Text(preset.rawValue).font(.headline);Text(preset.description).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain) }
            }
            Section("Картки та приватність") {
                Picker("Шаблон карток",selection:Binding(get:{s.db.preferences?.cardTemplate ?? "За дизайном"},set:{binding(\.cardTemplate).wrappedValue=$0})) {ForEach(FinamiCardTemplate.allCases){Text($0.rawValue).tag($0.rawValue)}}
                Toggle("Приховувати суми",isOn:Binding(get:{s.privateAmounts},set:{binding(\.hideAmounts).wrappedValue=$0}))
                Toggle("Показувати доходи",isOn:Binding(get:{s.db.preferences?.showIncome ?? false},set:{binding(\.showIncome).wrappedValue=$0}))
                Toggle("Показувати витрати",isOn:Binding(get:{s.db.preferences?.showExpenses ?? true},set:{binding(\.showExpenses).wrappedValue=$0}))
                Toggle("Без діаграм на огляді",isOn:Binding(get:{s.db.preferences?.noCharts ?? true},set:{binding(\.noCharts).wrappedValue=$0}))
            }
            Section("Акцент") {
                ForEach(IzanamiTheme.all) { theme in
                    Button { binding(\.theme).wrappedValue = theme.name } label: {
                        HStack { Circle().fill(theme.color).frame(width: 28, height: 28); Text(theme.name); Spacer(); if (s.db.preferences ?? .init()).theme == theme.name { Image(systemName: "checkmark.circle.fill") } }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()).buttonStyle(.plain)
                }
            }
            Picker("Режим", selection: binding(\.mode)) { Text("За дизайном").tag("preset"); Text("Системний").tag("system"); Text("Темний").tag("dark"); Text("Світлий").tag("light") }
            Picker("Шрифт", selection: binding(\.font)) { Text("За дизайном").tag("preset"); Text("Системний").tag("default"); Text("Rounded").tag("rounded"); Text("Serif").tag("serif"); Text("Monospaced").tag("monospaced") }
            Toggle("Великі іконки", isOn: binding(\.largeIcons))
            Toggle("Яскраве підсвічування", isOn: binding(\.glow))
            Toggle("Кольорові акценти", isOn: Binding(get:{s.db.preferences?.colorfulDashboard ?? true},set:{binding(\.colorfulDashboard).wrappedValue=$0}))
        }.navigationTitle("Студія дизайну").sheet(item:$preview) { selected in NavigationStack { VStack(spacing:18) { FinamiDesignPreview(design:selected); Text(selected.description).foregroundStyle(.secondary); Button("Застосувати дизайн") { s.change { d in var p=d.preferences ?? .init();p.design=selected.rawValue;p.theme="Preset";p.mode="preset";p.font="preset";d.preferences=p };preview=nil }.buttonStyle(.borderedProminent);Spacer() }.padding().navigationTitle(selected.rawValue).toolbar{Button("Скасувати"){preview=nil}} } }
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
    let hidden = kind == .income ? database.hiddenIncomeCategories ?? [] : database.hiddenExpenseCategories ?? []
    let allowed = (kind == .income ? database.incomeCategories : database.expenseCategories).filter { !hidden.contains($0) }
    if let learned = database.merchantRules?[ruleKey(note, kind: kind)], allowed.contains(learned) { return learned }
    guard kind == .expense else { return "Без категорії" }
    let n = note.lowercased()
    let rules: [(String,String)] = [("uklon","🚕 Таксі"),("bolt.eu","🚕 Таксі"),("1taxi","🚕 Таксі"),("thrash","🛒 Продукти"),("torba","🛒 Продукти"),("атб","🛒 Продукти"),("atb","🛒 Продукти"),("atб","🛒 Продукти"),("apteka","💊 Здоров’я"),("lifecell","📱 Зв’язок"),("utility","🧾 Комунальні"),("kavy ta chaiu","☕ Кава"),("netflix","📺 Підписки"),("spotify","📺 Підписки")]
    return rules.first(where: { n.contains($0.0) && allowed.contains($0.1) })?.1 ?? "Без категорії"
}

enum DashboardKind: String, Codable, CaseIterable, Identifiable {
    case balance, cashflow, categories, recent, accounts, budget, obligations, subscriptions, reminders, forecast, uncategorized, goals, debt, installments, recurring, statistics, fees, savings, ownFunds, creditDebt, availableCredit, review, creditLimit, creditPortfolio, allAvailable, monthlyPayments
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
        case .monthlyPayments: return "calendar"
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
        case .obligations,.reminders,.recurring,.monthlyPayments: return .cyan
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
            Section("Увімкни потрібні блоки. Через «Редагувати» перетягни їх у новий порядок. Великі фінансові блоки завжди на всю ширину.") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(get: { items.first(where: { $0.id == item.id })?.enabled ?? false }, set: { v in modify(item.id) { $0.enabled = v } })) { Label(item.kind.title, systemImage: item.kind.icon) }
                        if item.enabled {
                            NavigationLink("Оформлення та показники") { FinamiBlockSettings(id:item.id) }
                            Picker("Розмір", selection: Binding(get: { items.first(where: { $0.id == item.id })?.size ?? .medium }, set: { v in modify(item.id) { $0.size = v } })) { ForEach(DashboardSize.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        }
                    }
                }.onMove { from, to in s.change { d in var all = DashboardItem.merged(d.dashboard); all.move(fromOffsets: from, toOffset: to); d.dashboard = all } }
            }
            Section("Назва вкладки") { Picker("Назва", selection: Binding(get: { s.db.preferences?.homeTitle ?? "Головна" }, set: { v in s.change { d in var p=d.preferences ?? .init();p.homeTitle=v;d.preferences=p } })) { ForEach(["Головна","Огляд","Мої фінанси","Гаманець"],id:\.self){Text($0).tag($0)} } }
            Button("Повернути стандартні блоки") { s.change { $0.dashboard = DashboardItem.defaults } }
        }.navigationTitle("Блоки головної").toolbar { EditButton() }
    }
}
struct CustomDashboard: View {
    @EnvironmentObject var s: Store
    @State private var date = Date()
    @State private var add = false
    @State private var configure = false
    @State private var voice = false
    @State private var scan = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var items: [DashboardItem] { (DashboardItem.merged(s.db.dashboard)).filter(\.enabled) }
    var rows: [[DashboardItem]] {
        var result: [[DashboardItem]] = []; var pair: [DashboardItem] = []
        for item in items {
            if item.size == .small && ![.balance,.ownFunds,.creditLimit,.creditPortfolio,.obligations,.allAvailable,.monthlyPayments,.accounts].contains(item.kind) && !dynamicTypeSize.isAccessibilitySize { pair.append(item); if pair.count == 2 { result.append(pair); pair = [] } }
            else { if !pair.isEmpty { result.append(pair); pair = [] }; result.append([item]) }
        }
        if !pair.isEmpty { result.append(pair) }; return result
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MonthControl(date: $date)
                if items.isEmpty { Panel { Text("Немає видимих блоків"); Button("Налаштувати огляд") { configure = true } } }
                ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entry.element) { item in DashboardTile(item: item, date: date) }
                    }
                }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(s.db.preferences?.homeTitle ?? "Головна")
            .toolbar { Button { s.change { d in var p=d.preferences ?? .init();p.hideAmounts = !(p.hideAmounts ?? false);d.preferences=p } } label: { Image(systemName:s.privateAmounts ? "eye.slash" : "eye") }.accessibilityLabel("Приховати або показати суми"); Button { configure = true } label: { Image(systemName: "slider.horizontal.3").font(.title2) }.accessibilityLabel("Налаштувати блоки") }
            .safeAreaInset(edge: .bottom) {
                HStack { Button { add = true } label: { Label("Додати операцію", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.borderedProminent); Button { voice=true } label:{Image(systemName:"mic.fill").frame(minWidth:44,minHeight:34)}.buttonStyle(.bordered).accessibilityLabel("Голосовий запис"); Button { scan = true } label: { Image(systemName: "doc.viewfinder").frame(minWidth:44,minHeight:34) }.buttonStyle(.bordered).accessibilityLabel("Імпорт зі скриншота") }.padding(.horizontal).padding(.vertical,5).background(.regularMaterial)
            }.sheet(isPresented: $add) { OpEditor(original: Operation(category: "Без категорії", account: s.db.accounts.first?.id ?? cash)) }
            .sheet(isPresented:$voice) { FinamiVoice() }
            .sheet(isPresented:$scan) { NavigationStack { FinamiScanView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { scan = false } } } } }
            .sheet(isPresented: $configure) { NavigationStack { DashboardSettings().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { configure = false } } } } }
    }
}
struct DashboardTile: View {
    @EnvironmentObject var s: Store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var item: DashboardItem; var date: Date
    var ops: [Operation] { s.month(date) }
    var inc: Int64 { s.totals(ops,.income) }
    var exp: Int64 { s.totals(ops,.expense) }
    var balance: Int64 { s.includedAccounts.reduce(0) { $0 + s.balance($1) } }
    var small: Bool { item.size == .small && ![.balance,.ownFunds,.creditLimit,.creditPortfolio,.obligations,.allAvailable,.monthlyPayments,.accounts].contains(item.kind) && !dynamicTypeSize.isAccessibilitySize }
    @State private var paymentDetails: FinamiPayment?
    @State private var accountSettings = false
    var masked: Bool { s.privateAmounts || item.hideAmounts == true }
    func display(_ n:Int64)->String { masked ? "••••" : s.displayed(n) }
    func visible(_ n:Int64,_ code:String = "UAH")->String { masked ? "••••" : s.visibleMoney(n,code) }
    var showCharts:Bool { s.db.preferences?.noCharts == false && !masked }
    var detailed: Bool { item.size == .large }
    var color: Color {
        let p = s.db.preferences ?? .init()
        if let name = item.accentName, let custom = IzanamiTheme.all.first(where: {$0.name == name}) { return custom.color }
        return (p.colorfulDashboard ?? true) ? item.kind.tileColor : (IzanamiTheme.all.first(where:{$0.name==p.theme})?.color ?? (FinamiDesign(rawValue:p.design ?? "Signature") ?? .signature).tint)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if small {
                HStack {FinamiArt(icon:item.kind.icon,tint:color,size:34);Spacer(minLength:0);privacyButton}
                Text(item.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
                HStack(alignment:.center,spacing:9){FinamiArt(icon:item.kind.icon,tint:color,size:50);Text(item.kind == .accounts ? "Мої рахунки" : item.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Spacer(minLength:0);if item.kind == .accounts { Button { accountSettings = true } label: { Image(systemName:"slider.horizontal.3").frame(minWidth:44,minHeight:44) }.buttonStyle(.plain).accessibilityLabel("Налаштування карток рахунків") };privacyButton}
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: small ? 94 : nil, alignment: .topLeading)
        .padding(small ? 12 : 16)
        .modifier(FinamiCardStyle(tint:color,template:item.template))
        .environment(\.finamiMask, masked)
        .sheet(item:$paymentDetails) { FinamiPaymentDetails(payment:$0) }
        .sheet(isPresented:$accountSettings) { NavigationStack { FinamiHomeAccountsSettings().toolbar { ToolbarItem(placement:.cancellationAction) { Button("Готово") { accountSettings = false } } } } }
    }
    var privacyButton: some View {
        Button { s.change { d in var all=DashboardItem.merged(d.dashboard);if let i=all.firstIndex(where:{$0.id==item.id}){all[i].hideAmounts = !(all[i].hideAmounts ?? false)};d.dashboard=all } } label:{Image(systemName:masked ? "eye.slash" : "eye").frame(minWidth:44,minHeight:44)}.buttonStyle(.plain).accessibilityLabel("Показати або приховати суми блоку").disabled(s.privateAmounts)
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
        Text(text).font(small ? .title3.weight(.semibold) : .title.weight(.bold))
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
    var cashFlow: some View {
        VStack(alignment:.leading,spacing:12) {
            if s.db.preferences?.showIncome == true { metric("Доходи",inc,.green) }
            if s.db.preferences?.showExpenses != false { metric("Витрати",exp,.orange) }
            if s.db.preferences?.showIncome != true && s.db.preferences?.showExpenses == false { detail("Показники приховано") }
        }
    }
    var categoryGroups: [(key: String, value: Int64)] {
        Dictionary(grouping: ops.filter { $0.expenseValue != 0 }, by: { $0.expenseGroup })
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.expenseValue } }
            .filter { $0.value > 0 && (item.categorySelection?.contains($0.key) ?? true) }.sorted { $0.value > $1.value }
    }
    var categories: some View {
        let groups = categoryGroups
        let total = groups.reduce(Int64(0)) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 11) {
            if groups.isEmpty { detail("Немає витрат за період") }
            else if small { value("\(groups.count)"); detail("Категорій з витратами") }
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
        ForEach(shown) { a in
            FinamiHomeAccountCard(accountID: a.id, date: date, fallbackTint: color)
        }
    }
    @ViewBuilder var content: some View {
        switch item.kind {
        case .balance: amount(balance); detail("Чистий баланс рахунків · без невикористаного кредиту")
        case .creditLimit: amount(s.totalCreditLimit);detail("Ліміт усіх включених кредитних рахунків")
        case .creditPortfolio: FinamiCreditSummary(showLimit:item.showLimit ?? true,showUsed:item.showUsed ?? true,showAvailable:item.showAvailable ?? true)
        case .allAvailable: amount(s.totalOwnFunds+s.totalAvailableCredit);detail("Власні кошти разом із доступним кредитом")
        case .monthlyPayments: FinamiMonthPayments()
        case .cashflow: cashFlow
        case .categories: categories
        case .recent:
            if ops.isEmpty { detail("Немає операцій") }
            else {
                let shown = Array(ops.sorted{$0.date > $1.date}.prefix(detailed ? 5 : 2))
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
            if let next=s.upcomingPayments.first { Button { paymentDetails=next } label:{FinamiPaymentCard(payment:next,showRemaining:item.showPaymentRemaining ?? true,showDate:item.showPaymentDate ?? true,showImage:item.showPaymentImage ?? true)}.buttonStyle(.plain) }
            else {detail("Немає запланованих платежів")}
        case .subscriptions:
            value(String((s.db.subscriptions ?? []).filter{$0.active}.count)); detail("Активних підписок")
            if let next = (s.db.subscriptions ?? []).filter({$0.active}).sorted(by: {$0.next < $1.next}).first { Text(next.name).font(.subheadline.weight(.medium)); detail(next.next.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))) }
        case .reminders: value(String((s.db.reminders ?? []).filter{$0.enabled && $0.date > Date()}.count)); detail("Майбутніх нагадувань")
        case .forecast: if let f = s.db.forecast { amount(s.totalOwnFunds + f.expected - f.reserve - f.planned); detail("Прогнозований залишок") } else { detail("За бажанням") }
        case .uncategorized: value(String(ops.filter{$0.category == "Без категорії"}.count)); detail("Операцій без категорії")
        case .goals: obligationSummary([.goal])
        case .debt: metric("Мені винні", s.db.obligations.filter{$0.kind == .owed}.reduce(0){$0+$1.remaining}, .green); metric("Я винен", s.db.obligations.filter{$0.kind == .owe}.reduce(0){$0+$1.remaining}, .orange)
        case .installments: obligationSummary([.installment])
        case .recurring: obligationSummary([.recurring])
        case .statistics: value(String(ops.count)); detail("Операцій · потік \(visible(inc-exp))")
        case .fees: amount(ops.filter{$0.kind == .expense && $0.category == "🏦 Комісії"}.reduce(0){$0+$1.amount})
        case .ownFunds:
            amount(s.totalOwnFunds); detail("Без кредитних коштів")
            if s.db.preferences?.showIncome == true { metric("Доходи",inc,.green) }
            if s.db.preferences?.showExpenses != false { metric("Витрати",exp,.orange) }
        case .creditDebt: amount(s.totalAccountDebt); detail("Використані кредитні кошти")
        case .availableCredit: amount(s.totalAvailableCredit); detail("Не є власними коштами")
        case .review: value(String(ops.filter{$0.kind.needsReview}.count)); detail("Потребують перевірки")
        case .savings: value(masked ? "••••" : inc > 0 ? ((Double(inc-exp)/Double(inc)).formatted(.percent.precision(.fractionLength(1)))) : "—"); detail("Частка доходу після витрат")
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

struct ForecastPreferences: Codable { var expected: Int64 = 0; var planned: Int64 = 0; var reserve: Int64 = 0; var days: Int = 30 }
struct ForecastView: View {
    @EnvironmentObject var s: Store
    @State private var expected = ""; @State private var planned = ""; @State private var reserve = ""; @State private var days = 30
    var total: Int64 { s.totalOwnFunds }
    var available: Int64 { total + (cents(expected) ?? 0) - (cents(planned) ?? 0) - (cents(reserve) ?? 0) }
    var valid: Bool { [expected,planned,reserve].allSatisfy { $0.isEmpty || (cents($0) ?? -1) >= 0 } }
    var body: some View {
        Form {
            Section("Необов’язково") {
                Text("Заповни тільки потрібні поля. Прогноз не створює фактичних операцій.").font(.caption)
                FinamiField("Очікуваний дохід, ₴", text: $expected, keyboard: .decimalPad)
                FinamiField("Майбутні платежі, ₴", text: $planned, keyboard: .decimalPad)
                FinamiField("Недоторканний резерв, ₴", text: $reserve, keyboard: .decimalPad)
                Stepper("Горизонт: \(days) днів", value: $days, in: 1...365)
            }
            Section("Прогноз") {
                LabeledContent("Поточний баланс", value: s.visibleMoney(total))
                LabeledContent("Вільний залишок", value: s.visibleMoney(available))
                LabeledContent("Бюджет на день", value: s.visibleMoney(max(0,available)/Int64(days)))
                Text("Оцінка залежить від введених майбутніх доходів та витрат.").font(.caption)
            }
            Button("Зберегти прогноз") { s.change { $0.forecast = .init(expected: cents(expected) ?? 0, planned: cents(planned) ?? 0, reserve: cents(reserve) ?? 0, days: days) } }.disabled(!valid)
            Button("Очистити прогноз", role: .destructive) { s.change { $0.forecast = nil }; expected = ""; planned = ""; reserve = ""; days = 30 }
        }.navigationTitle("Фінансовий прогноз").onAppear { if let f = s.db.forecast { expected = amountText(f.expected); planned = amountText(f.planned); reserve = amountText(f.reserve); days = f.days } }
    }
}
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
    var list: [SubscriptionRecord] { (s.db.subscriptions ?? []).sorted{$0.next < $1.next} }
    var body: some View {
        List {
            Section("Активні") { ForEach(["UAH","USD"], id: \.self) { currency in let active = list.filter{$0.active && $0.currency == currency}; if !active.isEmpty { let total = active.reduce(0.0) { n,r in n + Double(r.amount) * (r.period == .week ? 52.0/12 : r.period == .year ? 1.0/12 : 1) }; LabeledContent("Місячна оцінка \(currency)", value: s.visibleMoney(Int64(total.rounded()),currency)) } } }
            ForEach(list) { r in
                Button { edit = r } label: { HStack { IzanamiLabel(title: r.name,icon:"repeat",color:.purple); Spacer(); VStack(alignment:.trailing){Text(s.visibleMoney(r.amount,r.currency)).bold(); Text(r.active ? r.next.formatted(date:.abbreviated,time:.omitted) : "Призупинено").font(.caption)} } }.buttonStyle(.plain)
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
            Text("До 12 попередніх версій бази зберігаються на телефоні перед змінами. Вони не захищають від видалення застосунку. Для цього експортуй JSON у «Файли».").font(.caption)
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
            Section("Операції цього місяця за оригінальною валютою") {ForEach(["UAH","USD"],id:\.self){code in let ops=s.month(Date()).filter{($0.originalCurrency ?? "UAH")==code}; LabeledContent("Дохід \(code)",value:s.visibleMoney(ops.filter{$0.kind == .income}.reduce(0){$0+($1.originalAmount ?? $1.amount)},code)); LabeledContent("Витрати \(code)",value:s.visibleMoney(ops.filter{$0.kind == .expense}.reduce(0){$0+($1.originalAmount ?? $1.amount)},code))}}
            Section("Окремі залишки") {ForEach(["UAH","USD"],id:\.self){code in LabeledContent(code,value:s.visibleMoney(s.db.accounts.filter{$0.code==code}.reduce(0){$0+s.nativeBalance($1)},code))}}
            Text("Щоб записати доларовий дохід, створи рахунок USD або вибери USD при введенні операції на рахунку UAH. Для обміну обери переказ між рахунками різних валют і фактичний курс.").font(.caption)
        }.navigationTitle("Валюти та курси").onAppear {rate=s.db.currencyPreferences?.usdRate ?? "";display=s.db.currencyPreferences?.display ?? "dual"}
    }
}
