import Foundation

// Presentation only. Never reads or mutates the ledger.
enum FinamiDesignPolicy {
    static let layouts = ["grid", "list", "cards"]
    static let dashboards = ["compact", "premium", "analytics"]
    static let accents = ["gold", "blue", "emerald", "rose", "violet", "silver"]
    static func radius(_ value: Int) -> Int { min(30, max(0, value)) }
    static func layout(_ value: String?, legacyGrid: Bool?) -> String {
        if let value, layouts.contains(value) { return value }
        return legacyGrid == true ? "grid" : "cards"
    }
    static func primaryField(fields: Set<String>, credit: Bool, mode: String) -> String? {
        let candidates = credit && mode != "own" ? ["available", "own", "used", "limit"] : ["own"]
        return candidates.first { fields.contains($0) && ($0 != "own" || mode != "credit") }
    }
    static func profile(_ name: String) -> (layout: String, dashboard: String, lowEffects: Bool, template: String, charts: Bool)? {
        switch name {
        case "Black Titanium": return ("grid", "compact", true, "За дизайном", false)
        case "Digital Bank": return ("cards", "premium", false, "Bank", false)
        case "Compact Pro": return ("list", "compact", true, "Compact", false)
        case "Liquid Glass": return ("grid", "premium", true, "За дизайном", false)
        case "Emerald Analytics": return ("grid", "analytics", true, "За дизайном", true)
        case "White Studio": return ("grid", "compact", true, "За дизайном", false)
        default: return nil
        }
    }
}

extension AppearancePreferences {
    var finamiLayout: String { FinamiDesignPolicy.layout(designLayout, legacyGrid: modernAccountGrid) }
    var finamiSpacing: CGFloat { designDashboard == "premium" ? 16 : modernCompactSpacing == false ? 16 : 10 }
    mutating func applyFinamiDesign(_ name: String) {
        design = name; theme = "Preset"; mode = "preset"; font = "preset"
        designAccent = nil; designRadius = nil
        if let profile = FinamiDesignPolicy.profile(name) {
            designLayout = profile.layout; modernAccountGrid = profile.layout == "grid"
            designDashboard = profile.dashboard; designLowEffects = profile.lowEffects
            cardTemplate = profile.template; modernCompactSpacing = profile.dashboard != "premium"
            noCharts = !profile.charts
            if name == "Digital Bank" { homeAccountLayout = "physical" }
        }
    }
    // Only appearance. Never restore privacy, filters or account visibility from a style preset.
    var finamiStyleSnapshot: [String: String] {
        var result = ["design": design ?? "Dark Classic", "theme": theme, "mode": mode, "font": font,
                      "layout": finamiLayout, "dashboard": designDashboard ?? "compact",
                      "effects": designLowEffects == true ? "off" : "on", "template": cardTemplate ?? "За дизайном",
                      "spacing": modernCompactSpacing == false ? "loose" : "compact", "charts": noCharts == false ? "on" : "off",
                      "icons": modernPaymentIcons ?? "black", "largeIcons": largeIcons ? "on" : "off",
                      "glow": glow ? "on" : "off", "colorful": colorfulDashboard == false ? "off" : "on"]
        if let homeAccountLayout { result["cardLayout"] = homeAccountLayout }
        if let homeAccountRight { result["cardRight"] = homeAccountRight }
        if let designAccent { result["accent"] = designAccent }
        if let designRadius { result["radius"] = String(FinamiDesignPolicy.radius(designRadius)) }
        return result
    }
    mutating func restoreFinamiStyle(_ values: [String: String]) {
        if let name = values["design"] { design = name }
        if let value = values["theme"] { theme = value }
        if let value = values["mode"], ["preset","system","light","dark"].contains(value) { mode = value }
        if let value = values["font"], ["preset","default","rounded","serif","monospaced"].contains(value) { font = value }
        if let value = values["layout"], FinamiDesignPolicy.layouts.contains(value) { designLayout = value; modernAccountGrid = value == "grid" }
        if let value = values["dashboard"], FinamiDesignPolicy.dashboards.contains(value) { designDashboard = value }
        if let value = values["template"] { cardTemplate = value }
        designAccent = values["accent"].flatMap { FinamiDesignPolicy.accents.contains($0) ? $0 : nil }
        designRadius = values["radius"].flatMap(Int.init).map(FinamiDesignPolicy.radius)
        if let value = values["effects"] { designLowEffects = value == "off" }
        if let value = values["spacing"] { modernCompactSpacing = value == "compact" }
        if let value = values["charts"] { noCharts = value != "on" }
        if let value = values["icons"], ["black","color"].contains(value) { modernPaymentIcons = value }
        if let value = values["largeIcons"] { largeIcons = value == "on" }
        if let value = values["glow"] { glow = value == "on" }
        if let value = values["colorful"] { colorfulDashboard = value == "on" }
        homeAccountLayout = values["cardLayout"].flatMap { ["premium","detailed","compact","physical"].contains($0) ? $0 : nil }
        homeAccountRight = values["cardRight"].flatMap { ["art","photo","expenses","credit","actions","last","count","none"].contains($0) ? $0 : nil }
    }
}

// Stable storage keys; no financial values or navigation style in this registry.
extension FinamiDesignPolicy {
    static let componentOptions: [String: [String]] = [
        "operations": ["classicPremium", "compactLedger", "merchantCards", "dailyJournal"],
        "accounts": ["original", "bankingSplit", "creditRing", "auroraCard"],
        "installments": ["paymentTimeline", "timelineProgressPro"],
        "upcoming": ["original", "paymentTimeline", "paymentFocus", "bankingPro"],
        "subscriptions": ["original", "compactList", "premiumCards", "billingCycle", "subscriptionPro"],
        "calendar": ["original", "calendarPro", "agendaTimeline", "cashFlow", "heatmap"],
        "editor": ["original", "quickEntry", "bankingPro", "minimal", "smartEntry"],
        "reports": ["original", "financePro", "analyticsBento", "minimalReports", "smartInsights", "bankingPremium"]
    ]
    static func styleTitle(_ key: String) -> String {
        switch key {
        case "classicPremium": return "Classic Premium"
        case "compactLedger": return "Compact Ledger"
        case "merchantCards": return "Merchant Cards · Preview"
        case "dailyJournal": return "Daily Journal · Preview"
        case "original": return "Original"
        case "bankingSplit": return "Banking Split"
        case "creditRing": return "Credit Ring"
        case "auroraCard": return "Aurora Card"
        case "paymentTimeline": return "Payment Timeline"
        case "timelineProgressPro": return "Timeline Progress Pro"
        case "paymentFocus": return "Payment Focus"
        case "bankingPro": return "Banking Pro"
        case "compactList": return "Compact List"
        case "premiumCards": return "Premium Cards"
        case "billingCycle": return "Billing Cycle"
        case "subscriptionPro": return "Subscription Pro"
        case "calendarPro": return "Calendar Pro"
        case "agendaTimeline": return "Agenda Timeline"
        case "cashFlow": return "Cash Flow"
        case "quickEntry": return "Quick Entry"
        case "smartEntry": return "Smart Entry"
        case "financePro": return "Finance Pro"
        case "analyticsBento": return "Analytics Bento"
        case "minimalReports": return "Minimal Reports"
        case "smartInsights": return "Smart Insights"
        case "bankingPremium": return "Banking Premium"
        default: return key.capitalized
        }
    }
    // A masked or unavailable metric has no graphical representation either.
    static func creditFraction(used: Int64, limit: Int64, masked: Bool) -> Double? {
        guard !masked, limit > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(limit)))
    }
    static let componentSizes = ["S", "M", "L"]
    static func validatedStyle(_ value: String?, component: String) -> String? {
        guard let value, componentOptions[component]?.contains(value) == true else { return nil }
        return value
    }
}
extension AppearancePreferences {
    func designStyle(for component: String) -> String? {
        FinamiDesignPolicy.validatedStyle(componentStyles?[component], component: component)
    }
    mutating func setDesignStyle(_ value: String?, for component: String) {
        guard FinamiDesignPolicy.componentOptions[component] != nil else { return }
        if let value, FinamiDesignPolicy.validatedStyle(value, component: component) == nil { return }
        var styles = componentStyles ?? [:]; styles[component] = value; componentStyles = styles
    }
    func designSize(for key: String) -> String {
        let size = componentSizes?[key] ?? "M"
        return FinamiDesignPolicy.componentSizes.contains(size) ? size : "M"
    }
    mutating func setDesignSize(_ value: String, for key: String) {
        guard FinamiDesignPolicy.componentSizes.contains(value), !key.isEmpty else { return }
        var sizes = componentSizes ?? [:]; sizes[key] = value; componentSizes = sizes
    }
    func designAccountStyle(for id: String) -> String? {
        FinamiDesignPolicy.validatedStyle(individualCardStyles?[id], component: "accounts") ?? designStyle(for: "accounts")
    }
    mutating func setDesignAccountStyle(_ value: String?, for id: String) {
        guard !id.isEmpty else { return }
        if let value, FinamiDesignPolicy.validatedStyle(value, component: "accounts") == nil { return }
        var styles = individualCardStyles ?? [:]; styles[id] = value; individualCardStyles = styles
    }
    func isDesignCardCollapsed(_ id: String, subscription: Bool) -> Bool {
        (subscription ? collapsedSubscriptions : collapsedInstallments)?.contains(id) == true
    }
    mutating func toggleDesignCard(_ id: String, subscription: Bool) {
        var ids = Set((subscription ? collapsedSubscriptions : collapsedInstallments) ?? [])
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        if subscription { collapsedSubscriptions = ids.sorted() } else { collapsedInstallments = ids.sorted() }
    }
}

extension FinamiDesignPolicy {
    static func componentTitle(_ key: String) -> String {
        ["installments":"Розстрочки", "upcoming":"Найближчі платежі", "subscriptions":"Підписки", "calendar":"Календар", "editor":"Редактор операцій", "reports":"Звіти"][key] ?? key
    }
    static let chartOptions = ["categories": ["None", "Donut", "Horizontal Bars", "Treemap"], "periods": ["None", "Bar Chart", "Area Chart", "Heatmap", "Income vs Expense"], "flow": ["None", "Cash Flow Waterfall"]]
    static func chartBlockTitle(_ key: String) -> String { ["categories":"Категорії", "periods":"Періоди", "flow":"Потік"][key] ?? key }
    static func safeMinor(_ value: Double) -> Int64 { guard value.isFinite else { return 0 }; return Int64(min(Double(Int64.max).nextDown, max(Double(Int64.min), value.rounded()))) }
    static func annualFactor(_ period: String) -> Double { period == "Тиждень" ? 52 : period == "Рік" ? 1 : 12 }
    static func fraction(_ paid: Int64, _ total: Int64, masked: Bool) -> Double? { guard !masked, total > 0 else { return nil }; return max(0, min(1, Double(paid)/Double(total))) }
}
extension AppearancePreferences {
    func designChart(_ block: String) -> String { let value = designReportCharts?[block] ?? "None"; return FinamiDesignPolicy.chartOptions[block]?.contains(value) == true ? value : "None" }
    mutating func setDesignChart(_ value: String, block: String) { guard FinamiDesignPolicy.chartOptions[block]?.contains(value) == true else { return }; var charts = designReportCharts ?? [:]; charts[block] = value; designReportCharts = charts }
}

extension FinamiDesignPolicy {
    static let upcomingFields = ["date", "name", "amount", "kind", "days", "overdue", "month", "image"]
    static func upcomingTitle(_ key: String) -> String { ["date":"Дата платежу", "name":"Назва", "amount":"Сума", "kind":"Тип", "days":"Днів до оплати", "overdue":"Прострочення", "month":"Підсумок місяця", "image":"Зображення"][key] ?? key }
}
extension AppearancePreferences {
    func designShowsUpcoming(_ key: String) -> Bool { (designUpcomingFields ?? FinamiDesignPolicy.upcomingFields).contains(key) }
    mutating func setDesignUpcoming(_ key: String, visible: Bool) { guard FinamiDesignPolicy.upcomingFields.contains(key) else { return }; var fields = Set(designUpcomingFields ?? FinamiDesignPolicy.upcomingFields); if visible { fields.insert(key) } else { fields.remove(key) }; designUpcomingFields = fields.sorted() }
}

extension FinamiDesignPolicy {
    // A calculator only prepares the amount text; the existing editor validates and saves it.
    static func calculate(_ left: String, _ right: String, operation: String) -> String? {
        let locale = Locale(identifier: "en_US_POSIX")
        func number(_ raw: String) -> Decimal? {
            let normalized = raw.replacingOccurrences(of: ",", with: ".")
            guard !normalized.isEmpty, normalized.count <= 18, normalized.allSatisfy({ $0.isNumber || $0 == "." }), normalized.filter({ $0 == "." }).count <= 1 else { return nil }
            return Decimal(string: normalized, locale: locale)
        }
        guard let a = number(left), let b = number(right) else { return nil }
        var result: Decimal
        switch operation { case "+": result = a+b; case "−": result = a-b; case "×": result = a*b; case "÷": guard b != 0 else { return nil }; result = a/b; default: return nil }
        guard !result.isNaN, result > 0, result < Decimal(1_000_000_000_000) else { return nil }
        var rounded = Decimal(); NSDecimalRound(&rounded, &result, 2, .plain)
        guard rounded > 0 else { return nil }
        return NSDecimalNumber(decimal: rounded).stringValue.replacingOccurrences(of: ".", with: ",")
    }
    static let reportBlocks = ["flow", "comparison", "chart", "categories", "accounts", "months", "review"]
    static func reportBlockTitle(_ key: String) -> String { ["flow":"Підсумок", "comparison":"Порівняння", "chart":"Динаміка", "categories":"Категорії", "accounts":"Рахунки", "months":"Періоди", "review":"Якість обліку"][key] ?? key }
}
extension AppearancePreferences {
    var designOrderedReportBlocks: [String] {
        var seen = Set<String>(); return ((designReportOrder ?? []) + FinamiDesignPolicy.reportBlocks).filter { FinamiDesignPolicy.reportBlocks.contains($0) && seen.insert($0).inserted }
    }
    func designReportStyle(_ block: String) -> String { FinamiDesignPolicy.validatedStyle(designReportBlockStyles?[block], component: "reports") ?? designStyle(for: "reports") ?? "original" }
    mutating func setDesignReportStyle(_ style: String?, block: String) {
        guard FinamiDesignPolicy.reportBlocks.contains(block) else { return }; if let style, FinamiDesignPolicy.validatedStyle(style, component: "reports") == nil { return }
        var styles = designReportBlockStyles ?? [:]; styles[block] = style; designReportBlockStyles = styles
    }
}
