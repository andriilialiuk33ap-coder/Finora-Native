import SwiftUI

func finamiDesignAccent(_ key: String?) -> Color? {
    switch key {
    case "gold": return Color(red:0.82,green:0.68,blue:0.44)
    case "blue": return .blue
    case "emerald": return .teal
    case "rose": return .pink
    case "violet": return .purple
    case "silver": return .gray
    default: return nil
    }
}
func finamiDesignSurface(_ design: FinamiDesign, scheme: ColorScheme) -> Color {
    guard scheme == .dark else {
        switch design {
        case .warmSand: return Color(red:0.99,green:0.96,blue:0.91)
        case .nordicWhite: return .white
        default: return Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
    switch design {
    case .midnightBlue: return Color(red:0.09,green:0.15,blue:0.25)
    case .amethyst: return Color(red:0.16,green:0.12,blue:0.21)
    case .carbonRed: return Color(red:0.125,green:0.12,blue:0.13)
    case .blackTitanium,.compactPro,.darkClassic,.obsidian,.graphite: return Color(red:0.105,green:0.105,blue:0.115)
    case .liquidGlass: return Color(red:0.14,green:0.20,blue:0.29)
    case .digitalBank: return Color(red:0.12,green:0.15,blue:0.21)
    case .emeraldAnalytics: return Color(red:0.10,green:0.19,blue:0.15)
    default: return Color(uiColor:.secondarySystemGroupedBackground)
    }
}
struct FinamiScreenBackground: View {
    @Environment(\.colorScheme) private var scheme
    var preferences: AppearancePreferences?
    var body: some View {
        let theme = FinamiDesign(rawValue:preferences?.design ?? "Dark Classic") ?? .darkClassic
        if scheme == .dark {
            switch theme {
            case .midnightBlue: Color(red:0.035,green:0.055,blue:0.105)
            case .amethyst: Color(red:0.065,green:0.04,blue:0.10)
            case .carbonRed,.blackTitanium,.compactPro: Color.black
            case .liquidGlass,.digitalBank: Color(red:0.055,green:0.08,blue:0.12)
            case .emeraldAnalytics: Color(red:0.04,green:0.09,blue:0.07)
            default: Color(uiColor:.systemGroupedBackground)
            }
        } else {
            switch theme {
            case .warmSand: Color(red:0.92,green:0.89,blue:0.84)
            case .nordicWhite: Color(red:0.94,green:0.95,blue:0.97)
            default: Color(uiColor:.systemGroupedBackground)
            }
        }
    }
}
func finamiScreenBackground(_ preferences: AppearancePreferences?) -> some View { FinamiScreenBackground(preferences:preferences) }

// Reusable picker; all writes are appearance-only.
struct FinamiComponentStylePicker: View {
    @EnvironmentObject private var s: Store
    var component: String
    var title: String
    var accountID: String? = nil
    private var p: AppearancePreferences { s.db.preferences ?? .init() }
    var body: some View {
        Picker(title, selection: Binding(get: {
            if let id = accountID { return FinamiDesignPolicy.validatedStyle(p.individualCardStyles?[id], component: component) ?? "" }
            return p.designStyle(for: component) ?? (FinamiDesignPolicy.componentOptions[component]?.first ?? "")
        }, set: { value in
            s.changeAppearance { prefs in
                if let id = accountID { prefs.setDesignAccountStyle(value.isEmpty ? nil : value, for: id) }
                else { prefs.setDesignStyle(value.isEmpty ? nil : value, for: component) }
            }
        })) {
            if accountID != nil { Text("Загальний стиль").tag("") }
            ForEach(FinamiDesignPolicy.componentOptions[component] ?? [], id: \.self) { key in
                Text(FinamiDesignPolicy.styleTitle(key)).tag(key)
            }
        }.accessibilityIdentifier("qa.design.style." + component + (accountID.map { "." + $0 } ?? ""))
    }
}
struct FinamiDesignLab: View {
    @EnvironmentObject private var s: Store
    @State private var presetName = ""
    @State private var pendingDelete: String?
    private var p: AppearancePreferences { s.db.preferences ?? .init() }
    private func binding<T>(_ key: WritableKeyPath<AppearancePreferences,T?>, _ fallback:T) -> Binding<T> {
        Binding(get:{p[keyPath:key] ?? fallback},set:{v in s.changeAppearance { $0[keyPath:key]=v }})
    }
    private var design: FinamiDesign { FinamiDesign(rawValue:p.design ?? "Dark Classic") ?? .darkClassic }
    private var preview: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Мої рахунки").font(.headline)
            if p.finamiLayout == "grid" {
                HStack(alignment:.top,spacing:8) { sampleCard("Кредит","Доступно"); sampleCard("Дебет","Власні кошти") }
            } else {
                sampleCard("Кредит","Доступно");sampleCard("Дебет","Власні кошти")
            }
            Label("Найближчі платежі",systemImage:"calendar").font(.subheadline)
        }.padding(12).background { finamiScreenBackground(p).clipShape(RoundedRectangle(cornerRadius:16)) }
    }
    private func sampleCard(_ name:String,_ label:String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            FinamiIconTile(icon:"creditcard.fill",tint:finamiDesignAccent(p.designAccent) ?? design.tint,side:30)
            Text(name).font(.subheadline.weight(.medium)); Text(label).font(.caption).foregroundStyle(.secondary)
            Text("••••").font(.title3.bold()).monospacedDigit()
        }.frame(maxWidth:.infinity,alignment:.leading).padding(10).modifier(FinamiCardStyle(tint:design.tint))
    }
    var body: some View {
        Form {
            Section("Попередній перегляд · демонстрація") { preview }
            Section("Компонування") {
                Picker("Рахунки",selection:Binding(get:{p.finamiLayout},set:{v in s.changeAppearance { $0.designLayout=v;$0.modernAccountGrid=v == "grid" }})) { Text("Сітка").tag("grid");Text("Список").tag("list");Text("Картки").tag("cards") }
                Picker("Головна",selection:binding(\.designDashboard,"compact")) { Text("Compact").tag("compact"); Text("Premium").tag("premium");Text("Analytics").tag("analytics") }
                Toggle("Приховувати порожні блоки",isOn:binding(\.hideEmptyDashboard,false))
                Button("Розгорнути всі блоки головної") { s.changeAppearance { $0.collapsedDashboard=[] } }
                Button("Розгорнути всі групи меню") { s.changeAppearance { $0.collapsedMenu=[] } }
                Button("Розгорнути всі розділи звітів") { s.changeAppearance { $0.collapsedReports=[] } }
                Button("Розгорнути всі розстрочки") { s.changeAppearance { $0.collapsedInstallments=[] } }
                Button("Розгорнути всі підписки") { s.changeAppearance { $0.collapsedSubscriptions=[] } }
            }
            Section("Design 3.0 · Компоненти") {
                FinamiComponentStylePicker(component: "operations", title: "Операції")
                FinamiComponentStylePicker(component: "accounts", title: "Картки рахунків")
                Picker("Розмір операцій", selection: Binding(get: { p.designSize(for: "operations") }, set: { value in s.changeAppearance { $0.setDesignSize(value, for: "operations") } })) {
                    ForEach(FinamiDesignPolicy.componentSizes, id: \.self) { Text($0).tag($0) }
                }
                ForEach(["installments", "upcoming", "subscriptions", "calendar", "editor", "reports"], id: \.self) { key in
                    FinamiComponentStylePicker(component: key, title: FinamiDesignPolicy.componentTitle(key))
                    if key != "editor" { FinamiDesignSizePicker(component: key) }
                }
                Picker("Кількість найближчих платежів", selection: binding(\.designUpcomingCount, 3)) { ForEach([1,3,5,10], id: \.self) { Text(String($0)).tag($0) } }
                ForEach(FinamiDesignPolicy.upcomingFields, id: \.self) { key in
                    Toggle(FinamiDesignPolicy.upcomingTitle(key), isOn: Binding(get: { p.designShowsUpcoming(key) }, set: { v in s.changeAppearance { $0.setDesignUpcoming(key, visible: v) } }))
                }
                Toggle("Finami Keyboard", isOn: binding(\.designEditorKeyboard, false))
                Toggle("Вібровідгук Finami Keyboard", isOn: binding(\.designEditorHaptics, true))
                Toggle("Підтвердження перед збереженням", isOn: binding(\.designEditorConfirm, false))
                Toggle("Останній рахунок для нової ручної операції", isOn: binding(\.designEditorLastAccountEnabled, false))
                ForEach(["categories", "periods", "flow"], id: \.self) { key in
                    Picker("Діаграма · " + FinamiDesignPolicy.chartBlockTitle(key), selection: Binding(get: { p.designChart(key) }, set: { v in s.changeAppearance { $0.setDesignChart(v, block: key) } })) {
                        ForEach(FinamiDesignPolicy.chartOptions[key] ?? [], id: \.self) { Text($0).tag($0) }
                    }
                }
                Text("Індивідуальний стиль рахунку можна вибрати в меню його картки. Два нові стилі операцій позначено Preview.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Кольори та картки") {
                Picker("Акцент",selection:Binding(get:{p.designAccent ?? "preset"},set:{v in s.changeAppearance { $0.designAccent=v == "preset" ? nil : v }})) {
                    Text("За стилем").tag("preset")
                    ForEach(FinamiDesignPolicy.accents,id:\.self) { key in Label(key,systemImage:"circle.fill").foregroundStyle(finamiDesignAccent(key) ?? .primary).tag(key) }
                }
                HStack { Text("Радіус карток");Spacer();Text("\(p.designRadius ?? Int(design.corner)) pt").monospacedDigit() }
                Slider(value:Binding(get:{Double(FinamiDesignPolicy.radius(p.designRadius ?? Int(design.corner)))},set:{v in s.changeAppearance { $0.designRadius=Int(v) }}),in:0...30,step:2)
                Button("Радіус за стилем") { s.changeAppearance { $0.designRadius=nil } }
                Toggle("Економний режим ефектів",isOn:binding(\.designLowEffects,false))
                Toggle("Щільні відступи",isOn:binding(\.modernCompactSpacing,true))
                Toggle("Діаграми на огляді",isOn:Binding(get:{p.noCharts == false},set:{v in s.changeAppearance { $0.noCharts = !v }}))
                Picker("Іконки платежів",selection:binding(\.modernPaymentIcons,"black")) { Text("Чорні · золото").tag("black");Text("Кольорові").tag("color") }
            }
            Section("Мої пресети") {
                TextField("Назва пресета",text:$presetName)
                Button("Зберегти поточний стиль") {
                    let name=String(presetName.trimmingCharacters(in:.whitespacesAndNewlines).prefix(60))
                    guard !name.isEmpty else { return }
                    s.changeAppearance { prefs in var saved=prefs.designPresets ?? [:];saved[name]=prefs.finamiStyleSnapshot;prefs.designPresets=saved };presetName=""
                }.disabled(presetName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                ForEach((p.designPresets ?? [:]).keys.sorted(),id:\.self) { name in
                    HStack {
                        Button(name) { if let values=p.designPresets?[name] { s.changeAppearance { $0.restoreFinamiStyle(values) } } }.buttonStyle(.borderless)
                        Spacer();Button(role:.destructive) { pendingDelete=name } label:{Image(systemName:"trash").frame(width:44,height:44)}.buttonStyle(.borderless).accessibilityLabel("Видалити пресет " + name)
                    }
                }
                Text("Пресети змінюють лише вигляд. Суми, приватність, порядок рахунків та операції не змінюються.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Design Lab 3.0")
        .confirmationDialog("Видалити пресет?",isPresented:Binding(get:{pendingDelete != nil},set:{if !$0 { pendingDelete=nil }}),titleVisibility:.visible) {
            Button("Видалити",role:.destructive) { if let name=pendingDelete { s.changeAppearance { $0.designPresets?.removeValue(forKey:name) } };pendingDelete=nil }
            Button("Скасувати",role:.cancel) { pendingDelete=nil }
        }
    }
}
