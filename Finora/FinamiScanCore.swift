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
        // A bank transaction detail screen contains balances as well as one signed payment.
        if let detail = transactionDetail(lines) { return [detail] }
        var result: [ScanLineDraft] = []
        var lastDate: Date? = nil
        var previous = ""
        for (i, line) in lines.enumerated() {
            let low = line.lowercased()
            let excluded = ["власні кошти", "баланс", "залишок", "ліміт", "доступно", "всього", "усього", "підсумок", "кредитний ліміт", "комісія", "кешбек за", "total", "balance"].contains { low.contains($0) }
            if let d = date(line) { lastDate = d }
            defer { previous = line }
            if excluded { continue }
            let prevLow = previous.lowercased()
            let pureAmount = line.range(of: #"^\s*[+−-]?[\d\s,.₴$]+(?:грн\.?|UAH|USD)?\s*$"#, options: [.regularExpression,.caseInsensitive]) != nil
            if pureAmount && ["власні кошти", "баланс", "залишок", "ліміт", "доступно", "всього", "усього", "підсумок", "комісія", "total", "balance"].contains(where: { prevLow.contains($0) }) { continue }
            let labels = ["сума операції", "сума платежу", "списано", "зараховано", "оплата", "покупка"]
            let labelled = labels.contains { low.contains($0) }
            // A standalone signed amount may omit its currency. Keep it as an unconfirmed draft.
            let signedBare = pureAmount && line.trimmingCharacters(in: .whitespacesAndNewlines).range(of: #"^[+−-]\s*\d"#, options: .regularExpression) != nil
            guard let m = money(line, allowBare: labelled || signedBare), m.minor != 0 else { continue }
            // Unsigned currency values are candidates only; the user selects direction.
            var note = line.replacingOccurrences(of: datePattern, with: "", options: .regularExpression)
            note = note.replacingOccurrences(of: "(?i)" + number + "\\s*" + currency, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if note.isEmpty || pureAmount || money(note) != nil { note = previous }
            if date(note) != nil || money(note) != nil { note = "" }
            result.append(ScanLineDraft(id: String(i), note: bankRedact(note), money: m, date: date(line) ?? lastDate))
            if result.count >= 100 { break }
        }
        return result
    }
    private static func transactionDetail(_ lines: [String]) -> ScanLineDraft? {
        let clean = lines.map(bankClean)
        guard let balanceIndex = clean.firstIndex(where: { $0.lowercased().contains("баланс після") }),
              clean.contains(where: { $0.lowercased().contains("дата транзакції") }) else { return nil }
        let candidates = clean.indices.filter { $0 < balanceIndex && money(clean[$0])?.signed == true }
        guard candidates.count == 1, let i = candidates.first, let amount = money(clean[i]) else { return nil }
        let merchant = i > 0 ? bankRedact(clean[i-1]) : ""
        let dates = clean.compactMap(date)
        return ScanLineDraft(id: String(i), note: merchant, money: amount, date: Set(dates).count == 1 ? dates.first : nil)
    }
    // Short dates on a future payment screen omit the year. Infer the next occurrence
    // relative to import time; the review must still explicitly confirm the date.
    static func nextPaymentDate(_ text: String, reference: Date = Date()) -> Date? {
        if let full = installmentDate(text) { return full }
        let months = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]
        let found = matches(#"(?<!\d)\d{1,2}\s+(?:січня|лютого|березня|квітня|травня|червня|липня|серпня|вересня|жовтня|листопада|грудня)(?![\p{L}\d])"#, in: text.lowercased())
        guard found.count == 1 else { return nil }
        let parts = found[0].split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let day = Int(parts[0]), let month = months.firstIndex(of: String(parts[1])) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        let year = cal.component(.year, from: reference)
        for y in [year, year+1] {
            if let d = bankDate(String(format: "%02d.%02d.%04d", day, month+1, y)), d >= cal.startOfDay(for: reference) { return d }
        }
        return nil
    }
    // Layout shown in the supplied installment screenshots: title, total, two-column
    // paid-count / remaining card, then next date + amount above its label.
    private static func purchasePlan(_ lines: [String], reference: Date) -> ScanInstallmentDraft? {
        guard let totalIndex = lines.firstIndex(where: { $0.lowercased().contains("розстрочка на") }),
              let total = money(lines[totalIndex]), total.currency == "UAH", total.minor > 0,
              let remainingIndex = lines.firstIndex(where: { $0.lowercased().contains("залишилось") || $0.lowercased().contains("залишилося") }),
              let nextIndex = lines.firstIndex(where: { $0.lowercased().contains("наступний платіж") }),
              totalIndex < remainingIndex, remainingIndex < nextIndex else { return nil }
        var draft = ScanInstallmentDraft(); draft.total = total.minor
        let title = lines[..<totalIndex].map { $0.replacingOccurrences(of: #"\s*\d+(?:[.,]\d+)?%"#, with: "", options: .regularExpression) }.filter { line in
            line.contains(where: \.isLetter) && money(line) == nil && nextPaymentDate(line, reference: reference) == nil && !line.contains("%") && !line.lowercased().contains("lifecell")
        }.suffix(2).joined(separator: " ")
        draft.name = bankRedact(title)
        // Require a single marked amount in the remaining label or its immediately preceding row.
        func remainingMoney(_ line: String) -> ScanMoney? {
            let stripped = line.replacingOccurrences(of: #"(?i)\d+\s+(?:із|з|из|of)\s+\d+"#, with: " ", options: .regularExpression)
            return money(stripped)
        }
        let remainingRows = lines[max(totalIndex+1, remainingIndex-3)...remainingIndex]
        let remainingAmounts = Set(remainingRows.compactMap(remainingMoney).filter { $0.currency == "UAH" && $0.minor >= 0 && $0.minor <= total.minor }.map(\.minor))
        if remainingAmounts.count == 1 { draft.remaining = remainingAmounts.first }
        // Search only inside the next-payment card, after the schedule/remaining section.
        let start = max(remainingIndex+1, nextIndex-5)
        if start <= nextIndex {
            let rawSection = Array(lines[start...nextIndex])
            let section = rawSection.lastIndex(where: { $0.lowercased().contains("графік платежів") }).map { Array(rawSection.dropFirst($0+1)) } ?? rawSection
            let amounts = Set(section.compactMap { money($0) }.filter { $0.currency == "UAH" && $0.minor > 0 }.map(\.minor))
            if amounts.count == 1 { draft.monthly = amounts.first }
            let dates = Set(section.compactMap { nextPaymentDate($0, reference: reference) })
            if dates.count == 1 { draft.due = dates.first }
        }
        draft.foreignCurrency = lines.contains(where: hasUnsupportedCurrency)
        return draft
    }
    // Only explicitly labelled, unambiguous amounts are filled automatically.
    private static let installmentLabels: [[String]] = [
        ["загальний кредит", "загальна сума кредиту", "сума кредиту", "сума договору", "загальна сума", "початкова сума", "вартість покупки", "сума покупки", "сума розстрочки", "повна вартість", "сума фінансування", "тіло кредиту початкове"],
        ["залишок боргу", "поточний залишок", "залишок розстрочки", "залишилося сплатити", "залишилось сплатити", "залишок заборгованості", "залишок до сплати", "залишок кредиту", "залишок суми кредиту", "залишок основного боргу", "непогашена сума", "сума до повного погашення", "залишок до погашення", "залишилось погасити", "залишилося погасити"],
        ["щомісячний платіж", "регулярний платіж", "сума наступного платежу", "сума платежу", "платіж на місяць", "платіж щомісяця", "щомісячна оплата", "розмір платежу", "наступний платіж", "черговий платіж", "обов'язковий платіж", "щомісячний внесок"],
        ["наступний платіж", "дата платежу", "дата наступного платежу", "сплатити до", "наступне списання", "дата списання", "дата чергового платежу", "черговий платіж", "наступна оплата", "дата оплати"],
        ["вже сплачено", "вже погашено", "сплачено всього", "погашено всього", "сума погашеного основного боргу", "погашено основного боргу"]
    ]
    static func installmentDate(_ text: String) -> Date? {
        if let d = date(text) { return d }
        let tokens = matches(#"(?<!\d)\d{1,2}[./]\d{1,2}[./]\d{4}(?!\d)"#, in: text)
        if tokens.count == 1 {
            let parts = tokens[0].split(whereSeparator: { $0 == "." || $0 == "/" }).compactMap { Int($0) }
            if parts.count == 3 { return bankDate(String(format: "%02d.%02d.%04d", parts[0], parts[1], parts[2])) }
        }
        let months = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]
        let words = matches(#"(?<!\d)\d{1,2}\s+(?:січня|лютого|березня|квітня|травня|червня|липня|серпня|вересня|жовтня|листопада|грудня)\s+\d{4}(?!\d)"#, in: text.lowercased())
        if words.count == 1 {
            let p = words[0].split(whereSeparator: \.isWhitespace)
            if p.count == 3, let day = Int(p[0]), let month = months.firstIndex(of: String(p[1])), let year = Int(p[2]) { return bankDate(String(format: "%02d.%02d.%04d", day, month+1, year)) }
        }
        return nil
    }
    private static func installmentAmount(_ text: String) -> ScanMoney? {
        if nextPaymentDate(text) != nil && matches(currency, in: text).isEmpty { return nil }
        // Remove only explicit dates before parsing amounts; a date alone is not money.
        var line = text.replacingOccurrences(of: #"(?<!\d)\d{1,2}[./]\d{1,2}[./]\d{4}(?!\d)"#, with: " ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"(?i)\d{1,2}\s+(?:січня|лютого|березня|квітня|травня|червня|липня|серпня|вересня|жовтня|листопада|грудня)\s+\d{4}"#, with: " ", options: .regularExpression)
        return money(line.replacingOccurrences(of: ":", with: " "), allowBare: true)
    }
    static func installmentCandidates(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { line in
            !line.isEmpty && seen.insert(line).inserted && (installmentAmount(line) != nil || installmentDate(line) != nil)
        }
    }
    static func installmentCandidateAmount(_ text: String) -> Int64? {
        guard let m = installmentAmount(text), m.currency != "USD", m.minor >= 0 else { return nil }; return m.minor
    }
    static func installment(_ input: [String], reference: Date = Date()) -> ScanInstallmentDraft {
        let lines = input.map(bankClean).filter { !$0.isEmpty }
        if let plan = purchasePlan(lines, reference: reference) { return plan }
        var draft = ScanInstallmentDraft()
        draft.foreignCurrency = lines.contains(where: hasUnsupportedCurrency)
        var values = Array(repeating: [Int64](), count: 5), dates: [Date] = []
        func groups(_ line: String) -> [Int] {
            let low = line.lowercased().replacingOccurrences(of: "’", with: "'")
            return installmentLabels.indices.filter { i in installmentLabels[i].contains { low.contains($0) } }
        }
        func amountOnly(_ line: String) -> ScanMoney? {
            guard line.range(of: #"^\s*[+−-]?[\d\s,.₴$]+(?:грн\.?|UAH|USD)?\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil, installmentDate(line) == nil else { return nil }
            return installmentAmount(line)
        }
        // Resolve adjacent standalone labels/values as complete alternating runs.
        // A value above its label must never be assigned to the preceding label.
        // If a run has an unmatched endpoint or mixed order, keep it for manual review.
        enum Token { case label, value }
        func token(_ line: String) -> Token? {
            if !groups(line).isEmpty && installmentAmount(line) == nil && installmentDate(line) == nil { return .label }
            if groups(line).isEmpty && (amountOnly(line) != nil || (installmentDate(line) != nil && installmentAmount(line) == nil)) { return .value }
            return nil
        }
        func isLabel(_ index: Int) -> Bool { if case .label? = token(lines[index]) { return true }; return false }
        var adjacent: [Int: String] = [:]
        var index = 0
        while index < lines.count {
            guard token(lines[index]) != nil else { index += 1; continue }
            let start = index
            while index < lines.count && token(lines[index]) != nil { index += 1 }
            let count = index - start
            guard count >= 2, count.isMultiple(of: 2), (start+1..<index).allSatisfy({ isLabel($0) != isLabel($0-1) }) else { continue }
            for i in stride(from: start, to: index, by: 2) {
                let label = isLabel(i) ? i : i+1
                let value = isLabel(i) ? i+1 : i
                adjacent[label] = lines[value]
            }
        }
        for (i, line) in lines.enumerated() {
            let low = line.lowercased(), kinds = groups(line)
            let next = i+1 < lines.count ? lines[i+1] : ""
            // Do not assign an amount from a row with more than one distinct money label.
            let moneyKinds = kinds.filter { $0 != 3 }
            if moneyKinds.count == 1, let kind = moneyKinds.first {
                // A short date without a year (01.12) is ambiguous and must not become a payment.
                let looksLikeShortDate = kinds.contains(3) && !matches(#"(?<!\d)\d{1,2}[./]\d{1,2}(?![\d./])"#, in: line).isEmpty && matches(currency, in: line).isEmpty
                let m = looksLikeShortDate ? nil : (installmentAmount(line) ?? adjacent[i].flatMap(amountOnly))
                if let m = m { if m.currency == "USD" { draft.foreignCurrency = true } else if m.minor >= 0 { values[kind].append(m.minor) } }
            }
            if kinds.contains(3), let d = nextPaymentDate(line, reference: reference) ?? adjacent[i].flatMap({ nextPaymentDate($0, reference: reference) }) { dates.append(d) }
            if draft.name.isEmpty {
                if ["назва", "товар", "назва товару", "предмет договору"].contains(low.trimmingCharacters(in: CharacterSet(charactersIn: ": "))), groups(next).isEmpty, installmentAmount(next) == nil, installmentDate(next) == nil, !next.isEmpty { draft.name = bankRedact(next) }
                for prefix in ["назва:", "товар:", "покупка:", "назва товару:", "предмет договору:"] where low.hasPrefix(prefix) {
                    let value = bankRedact(String(line.dropFirst(prefix.count))); if !value.isEmpty { draft.name = value }
                }
            }
        }
        func unique(_ a: [Int64]) -> Int64? { Set(a).count == 1 ? a.first : nil }
        draft.total = unique(values[0]); draft.remaining = unique(values[1]); draft.monthly = unique(values[2])
        // Only derive remaining from explicitly labelled principal paid, never generic payments with fees.
        if draft.remaining == nil, values[1].isEmpty, let t = draft.total {
            let principal = lines.filter { $0.lowercased().contains("погашено основного боргу") || $0.lowercased().contains("погашеного основного боргу") }
            if principal.count == 1, let paid = installmentCandidateAmount(principal[0]), paid <= t { draft.remaining = t-paid }
        }
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

// Merge independent screenshot drafts only when all supplied values agree.
// Do not concatenate unrelated screens into a single inferred contract.
struct FinamiInstallmentMerge {
    var draft: ScanInstallmentDraft
    var conflicts: [String]
}
func finamiMergeInstallments(_ drafts: [ScanInstallmentDraft]) -> FinamiInstallmentMerge {
    var result = ScanInstallmentDraft(); var conflicts: [String] = []
    func unique<T: Hashable>(_ values: [T], _ label: String) -> T? {
        let set = Set(values)
        if set.count > 1 { conflicts.append(label); return nil }
        return set.first
    }
    result.name = unique(drafts.map(\.name).filter { !$0.isEmpty }, "Назва") ?? ""
    result.total = unique(drafts.compactMap(\.total), "Загальний кредит")
    result.remaining = unique(drafts.compactMap(\.remaining), "Залишок")
    result.monthly = unique(drafts.compactMap(\.monthly), "Наступний платіж")
    result.due = unique(drafts.compactMap(\.due), "Дата")
    result.foreignCurrency = drafts.contains { $0.foreignCurrency }
    return FinamiInstallmentMerge(draft: result, conflicts: conflicts)
}
struct FinamiScheduleRow: Codable, Identifiable, Hashable {
    var date: Date
    var amount: Int64
    var id: String { String(date.timeIntervalSince1970) + ":" + String(amount) }
}
// Only explicit date + currency amount on the same row. Do not infer status,
// or fabricate a full schedule from a single upcoming payment.
func finamiScheduleRows(_ lines: [String], reference: Date = Date()) -> [FinamiScheduleRow] {
    var candidates: [FinamiScheduleRow] = []
    for line in lines {
        let lower = line.lowercased()
        guard !["залиш", "баланс", "всього", "ліміт", "розстрочка на", "сплачено платежів", "погашено"].contains(where: { lower.contains($0) }),
              let date = FinamiScanParser.nextPaymentDate(line, reference: reference),
              let amount = FinamiScanParser.money(line), amount.currency == "UAH", amount.minor > 0 else { continue }
        candidates.append(.init(date: date, amount: amount.minor))
    }
    return Dictionary(grouping: candidates, by: \.date).values.compactMap { group in
        let set = Set(group); return set.count == 1 ? set.first : nil
    }.sorted { $0.date < $1.date }
}
