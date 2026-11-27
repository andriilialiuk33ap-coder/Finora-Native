import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Learns a field's position only on a screen with recognizable structural
// anchors. Layout memory produces suggestions, never a saved contract.
struct FinamiOCRSlot: Codable, Equatable {
    let x: Int
    let y: Int
    init(_ bounds: CGRect) {
        x = Int((bounds.midX * 100).rounded())
        y = Int((bounds.midY * 100).rounded())
    }
    func near(_ other: FinamiOCRSlot) -> Bool { abs(x - other.x) <= 2 && abs(y - other.y) <= 2 }
}
enum FinamiOCRLayoutMemory {
    static let storageKey = "finami.ocr.geometry.v1"
    typealias Layouts = [String: [String: FinamiOCRSlot]]
    static func signature(bank: String, regions: [ScanTextRegion]) -> String? {
        guard FinamiOCRProfiles.banks.contains(bank) else { return nil }
        let anchors: Set<String> = ["загальна сума", "загальна сума розстрочки", "загальний кредит", "сума кредиту", "поточний залишок", "залишок боргу", "залишилось", "залишилося", "залишок", "щомісячний платіж", "наступний платіж", "дата наступного платежу", "дата платежу", "графік платежів", "розстрочка", "покупка частинами", "оплата частинами", "платежів сплачено"]
        let profile = FinamiOCRProfiles.builtIn(bank)
        var found: [String: FinamiOCRSlot] = [:]
        for region in regions {
            let raw = bankClean(region.text.lowercased()).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            // Only a known, label-only anchor. No merchant, name, amount or card data.
            let name = profile[raw]?.canonical.lowercased() ?? raw
            guard anchors.contains(name) else { continue }
            let pos = FinamiOCRSlot(region.bounds)
            if found[name] != nil { return nil }
            found[name] = pos
        }
        guard found.count >= 2 else { return nil }
        let keys = found.keys.sorted().compactMap { name -> String? in
            guard let p = found[name] else { return nil }
            return name + ":" + String((Double(p.x)/5).rounded()) + ":" + String((Double(p.y)/5).rounded())
        }
        return bank + "|" + keys.joined(separator: "|")
    }
    static func amount(_ region: ScanTextRegion) -> Int64? {
        guard region.text.range(of: #"^\s*[+−-]?[\d\s,.]+\s*(?:₴|грн\.?|UAH)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let m = FinamiScanParser.money(region.text), m.currency == "UAH", m.minor >= 0 else { return nil }
        return m.minor
    }
    static func read(defaults: UserDefaults = .standard) -> Layouts {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(Layouts.self, from: $0) } ?? [:]
    }
    static func learn(bank: String, regions: [ScanTextRegion], chosen: ScanTextRegion, field: FinamiOCRField, defaults: UserDefaults = .standard) {
        guard let key = signature(bank: bank, regions: regions), amount(chosen) != nil else { return }
        let slot = FinamiOCRSlot(chosen.bounds)
        // A position must identify one isolated marked amount in this screenshot.
        let candidates = regions.filter { amount($0) != nil && FinamiOCRSlot($0.bounds).near(slot) }
        guard candidates.count == 1, candidates.first?.text == chosen.text else { return }
        var layouts = read(defaults: defaults)
        guard layouts.count < 48 || layouts[key] != nil else { return }
        var fields = layouts[key] ?? [:]
        // Never allow one position to teach two different financial fields.
        guard !fields.contains(where: { $0.key != field.rawValue && $0.value.near(slot) }) else { return }
        if let prior = fields[field.rawValue], !prior.near(slot) { return }
        fields[field.rawValue] = slot
        layouts[key] = fields
        if let data = try? JSONEncoder().encode(layouts) { defaults.set(data, forKey: storageKey) }
    }
    static func suggestions(bank: String?, regions: [ScanTextRegion], defaults: UserDefaults = .standard) -> [FinamiOCRField: Int64] {
        guard let bank, let key = signature(bank: bank, regions: regions), let fields = read(defaults: defaults)[key],
              !regions.contains(where: { FinamiScanParser.hasUnsupportedCurrency($0.text) || FinamiScanParser.money($0.text)?.currency == "USD" }) else { return [:] }
        var result: [FinamiOCRField: Int64] = [:]
        for field in FinamiOCRField.allCases {
            guard let slot = fields[field.rawValue] else { continue }
            let candidates = regions.filter { amount($0) != nil && FinamiOCRSlot($0.bounds).near(slot) }
            if candidates.count == 1, let region = candidates.first, let value = amount(region) { result[field] = value }
        }
        return result
    }
}
