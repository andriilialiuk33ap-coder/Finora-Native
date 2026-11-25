import Foundation

// Foundation-only recognition heuristics. All extracted values remain drafts.
struct ScanMoney: Equatable {
    var minor: Int64
    var currency: String?
    var signed: Bool
}
struct ScanLineDraft: Identifiable {
    var id: String
    var note: String
    var money: ScanMoney?
    var date: Date?
}
struct ScanBalanceDraft {
    var own: ScanMoney?
    var used: ScanMoney?
    var net: ScanMoney?
    var limit: ScanMoney?
}
struct ScanInstallmentDraft {
    var name = ""
    var total: Int64?
    var remaining: Int64?
    var monthly: Int64?
    var due: Date?
    var foreignCurrency = false
}
enum FinamiScanParser {
    static let number = #"[+−-]?\s*(?:\d{1,3}(?:[ \u00A0\u202F]\d{3})+|\d+)(?:[,.]\d{1,2})?"#
    static let currency = #"(?:₴|грн\.?|UAH|USD|\$)"#
    static let datePattern = #"(?<!\d)(?:\d{2}\.\d{2}\.\d{4}|\d{4}-\d{2}-\d{2})(?:[ T]\d{2}:\d{2}(?::\d{2})?)?(?!\d)"#
    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
    static func date(_ text: String) -> Date? {
        let dates = matches(datePattern, in: text)
        guard dates.count == 1 else { return nil }
        return bankDate(dates[0].replacingOccurrences(of: "T", with: " "))
    }
    static func hasUnsupportedCurrency(_ text: String) -> Bool {
        !matches(#"(?i)(?:€|£|\b(?:EUR|PLN|GBP|CHF|CZK|CAD|AUD|JPY|RUB)\b|злот(?:их|ий|і)|євро)"#, in: text).isEmpty
    }
    static func money(_ text: String, allowBare: Bool = false) -> ScanMoney? {
        guard !hasUnsupportedCurrency(text) else { return nil }
        let line = text.replacingOccurrences(of: datePattern, with: " ", options: .regularExpression)
        let pattern = "(?<![\\d.,])(?:" + number + "\\s*" + currency + "|" + currency + "\\s*" + number + ")(?!\\d)"
        let marked = matches(pattern, in: line)
        let raw: String
        let code: String?
        if marked.count == 1 {
            raw = marked[0].replacingOccurrences(of: currency, with: "", options: [.regularExpression, .caseInsensitive])
            let token = marked[0].lowercased()
            code = token.contains("$") || token.contains("usd") ? "USD" : "UAH"
        } else if marked.isEmpty && allowBare {
            let nums = matches("(?<![\\d.,])" + number + "(?![\\d.,])", in: line)
            guard nums.count == 1, !line.contains("%"), !line.contains(":"), !line.contains("€") else { return nil }
            raw = nums[0]; code = nil
        } else { return nil }
        let clean = raw.filter { !$0.isWhitespace }.replacingOccurrences(of: "−", with: "-")
        guard let minor = bankMinor(clean) else { return nil }
        return ScanMoney(minor: minor, currency: code, signed: clean.hasPrefix("+") || clean.hasPrefix("-"))
    }
    static func bank(_ text: String) -> String? {
        let t = text.lowercased()
        let candidates: [(String,[String])] = [("monobank",["monobank","монобанк"]),("ПУМБ",["пумб","pumb"]),("А-БАНК",["а-банк","а-банку","a-bank","abank"]),("ПриватБанк",["приватбанк","приват24","privatbank"]),("ОТП",["отп банк","otp bank","otpbank"]),("Sense Bank",["sense bank","сенс банк"]),("Райффайзен",["райффайзен","raiffeisen"])]
        let found = candidates.filter { $0.1.contains(where: {t.contains($0)}) }
        return found.count == 1 ? found[0].0 : nil
    }
    static func transactions(_ lines: [String]) -> [ScanLineDraft] {
        var result: [ScanLineDraft] = []
        var lastDate: Date? = nil
        var previous = ""
        for (i, line) in lines.enumerated() {
            let low = line.lowercased()
            let excluded = ["баланс", "залишок", "ліміт", "доступно", "всього", "усього", "підсумок", "кредитний ліміт", "комісія", "кешбек за", "total", "balance"].contains { low.contains($0) }
            if let d = date(line) { lastDate = d }
            defer { previous = line }
            if excluded { continue }
            let prevLow = previous.lowercased()
            let pureAmount = line.range(of: #"^\s*[+−-]?[\d\s,.₴$]+(?:грн\.?|UAH|USD)?\s*$"#, options: [.regularExpression,.caseInsensitive]) != nil
            if pureAmount && ["баланс", "залишок", "ліміт", "доступно", "всього", "усього", "підсумок", "комісія", "total", "balance"].contains(where: { prevLow.contains($0) }) { continue }
            let labels = ["сума операції", "сума платежу", "списано", "зараховано", "оплата", "покупка"]
            let labelled = labels.contains { low.contains($0) }
            guard let m = money(line, allowBare: labelled), m.minor != 0 else { continue }
            // Unsigned currency values are candidates only; the user selects direction.
            var note = line.replacingOccurrences(of: datePattern, with: "", options: .regularExpression)
            note = note.replacingOccurrences(of: "(?i)" + number + "\\s*" + currency, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if note.isEmpty || money(note) != nil { note = previous }
            if date(note) != nil || money(note) != nil { note = "" }
            result.append(ScanLineDraft(id: String(i), note: bankRedact(note), money: m, date: date(line) ?? lastDate))
            if result.count >= 100 { break }
        }
        return result
    }
    static func installment(_ lines: [String]) -> ScanInstallmentDraft {
        var draft = ScanInstallmentDraft()
        draft.foreignCurrency = lines.contains(where: hasUnsupportedCurrency)
        var totals: [Int64] = [], remains: [Int64] = [], monthly: [Int64] = [], dates: [Date] = []
        let totalLabels = ["загальний кредит", "сума кредиту", "сума договору", "загальна сума", "початкова сума", "вартість покупки", "сума розстрочки"]
        let remainingLabels = ["залишок боргу", "поточний залишок", "залишок розстрочки", "залишилося сплатити", "залишок заборгованості", "залишок до сплати", "залишок кредиту"]
        let monthlyLabels = ["щомісячний платіж", "регулярний платіж", "сума наступного платежу", "сума платежу", "платіж на місяць"]
        let dueLabels = ["наступний платіж", "дата платежу", "дата наступного платежу", "сплатити до", "наступне списання"]
        for (i, line) in lines.enumerated() {
            let low = line.lowercased()
            let next = i + 1 < lines.count ? lines[i+1] : ""
            let nextIsValue = next.range(of: #"^\s*[+−-]?[\d\s,.₴$]+(?:грн\.?|UAH|USD)?\s*$"#, options:[.regularExpression,.caseInsensitive]) != nil
            if let m = money(line, allowBare: true) ?? (nextIsValue ? money(next, allowBare: true) : nil) {
                if totalLabels.contains(where: {low.contains($0)}) { if m.currency == "USD" { draft.foreignCurrency = true } else if m.minor > 0 { totals.append(m.minor) } }
                else if remainingLabels.contains(where: {low.contains($0)}) { if m.currency == "USD" { draft.foreignCurrency = true } else if m.minor >= 0 { remains.append(m.minor) } }
                else if monthlyLabels.contains(where: {low.contains($0)}) { if m.currency == "USD" { draft.foreignCurrency = true } else if m.minor > 0 { monthly.append(m.minor) } }
            }
            if dueLabels.contains(where: {low.contains($0)}), let d = date(line) ?? date(next) { dates.append(d) }
            if draft.name.isEmpty && ["назва:","товар:","покупка:"].contains(where: {low.hasPrefix($0)}) {
                draft.name = bankRedact(String(line.split(separator: ":", maxSplits: 1).dropFirst().joined(separator: ":")))
            }
        }
        if Set(totals).count == 1 { draft.total = totals.first }
        if Set(remains).count == 1 { draft.remaining = remains.first }
        if Set(monthly).count == 1 { draft.monthly = monthly.first }
        if Set(dates).count == 1 { draft.due = dates.first }
        return draft
    }
    static func balance(_ lines: [String]) -> ScanBalanceDraft {
        var result = ScanBalanceDraft()
        var own: [ScanMoney] = [], used: [ScanMoney] = [], net: [ScanMoney] = [], limit: [ScanMoney] = []
        for (i, line) in lines.enumerated() {
            let low = line.lowercased()
            let next = i+1 < lines.count ? lines[i+1] : ""
            let nextIsValue = next.range(of: #"^\s*[+−-]?[\d\s,.₴$]+(?:грн\.?|UAH|USD)?\s*$"#, options: [.regularExpression,.caseInsensitive]) != nil
            guard let amount = money(line, allowBare: true) ?? (nextIsValue ? money(next, allowBare: true) : nil) else { continue }
            if ["власні кошти", "власний залишок"].contains(where: { low.contains($0) }) { own.append(amount) }
            else if ["використано кредит", "кредитна заборгованість", "використаний кредит"].contains(where: { low.contains($0) }) { used.append(amount) }
            else if ["кредитний ліміт", "ліміт кредиту"].contains(where: { low.contains($0) }) && !low.contains("доступн") { limit.append(amount) }
            else if ["чистий баланс", "фактичний баланс", "чистий залишок"].contains(where: { low.contains($0) }) { net.append(amount) }
        }
        func unique(_ values: [ScanMoney]) -> ScanMoney? { guard let first = values.first, values.allSatisfy({$0 == first}) else {return nil};return first }
        result.own = unique(own); result.used = unique(used); result.net = unique(net); result.limit = unique(limit)
        return result
    }
    static func validInstallment(total: Int64, remaining: Int64, monthly: Int64) -> Bool {
        total > 0 && remaining >= 0 && remaining <= total && monthly >= 0 && (remaining == 0 || monthly > 0)
    }
    static func samePayment(account: String, signed: Int64, date: Date, otherAccount: String, otherSigned: Int64, otherDate: Date, calendar: Calendar = .current) -> Bool {
        account == otherAccount && signed == otherSigned && calendar.isDate(date, inSameDayAs: otherDate)
    }
}
