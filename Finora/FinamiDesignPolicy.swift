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
