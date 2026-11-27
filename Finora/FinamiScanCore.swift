import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

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
// Normalized Vision coordinates (origin at bottom left). Foundation-only for tests.
struct ScanTextRegion {
    let text: String
    let bounds: CGRect
}
struct ScanInstallmentDraft {
    var name = ""
    var total: Int64?
    var remaining: Int64?
    var monthly: Int64?
    var due: Date?
    var foreignCurrency = false
    var pumbParts = false
    var paymentCount: Int?
    var paidCount: Int?
    var nextAmount: Int64?
    var bankNextDue: Date?
    var finalDue: Date?
    var opened: Date?
    var monthlyEstimated = false
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
        ["загальний кредит", "загальна сума кредиту", "сума кредиту", "сума договору", "загальна сума", "початкова сума", "вартість покупки", "сума покупки", "сума розстрочки", "повна вартість", "сума фінансування", "тіло кредиту початкове", "початкова сума кредиту", "сума розстрочки за договором", "розстрочка на", "повна сума кредиту", "загальна вартість покупки", "загальна сума розстрочки", "початкова сума розстрочки", "вартість товару"],
        ["залишок боргу", "поточний залишок", "залишок розстрочки", "залишилося сплатити", "залишилось сплатити", "залишок заборгованості", "залишок до сплати", "залишок кредиту", "залишок суми кредиту", "залишок основного боргу", "непогашена сума", "сума до повного погашення", "залишок до погашення", "залишилось погасити", "залишилося погасити", "залишок за договором", "залишок до повного погашення", "залишок до кінця розстрочки", "залишок тіла кредиту", "залишилось виплатити", "залишилося виплатити", "залишок платежів у гривнях", "сума залишку", "залишок за розстрочкою"],
        ["щомісячний платіж", "регулярний платіж", "сума наступного платежу", "сума платежу", "платіж на місяць", "платіж щомісяця", "щомісячна оплата", "розмір платежу", "наступний платіж", "черговий платіж", "обов'язковий платіж", "щомісячний внесок", "платіж на місяць", "сума щомісячного платежу", "розмір щомісячного платежу", "щомісячна сума", "сума регулярного платежу", "щомісячний платіж за розстрочкою", "сума щомісячної оплати", "платіж за місяць"],
        ["наступний платіж", "дата платежу", "дата наступного платежу", "сплатити до", "наступне списання", "дата списання", "дата чергового платежу", "черговий платіж", "наступна оплата", "дата оплати", "дата щомісячного платежу", "дата внесення платежу"],
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
        // A marked currency can coexist with a date; bare numbers require a money
        // label or a pure numeric row. Never treat card masks, time or counters as money.
        if let marked = money(line) { return marked }
        guard matches(currency, in: line).isEmpty,
              matches(#"(?<!\d)\d{1,2}:\d{2}(?!\d)|[•●*]{1,}\s*\d|\b(?:картк[аиуиі]|рахунк[ау]|договір|договору)\s*(?:№|#)\s*\d"#, in: line).isEmpty else { return nil }
        let lower = line.lowercased()
        let labelled = installmentLabels.enumerated().contains { index, labels in index != 3 && labels.contains { lower.contains($0) } }
        let pure = line.range(of: #"^\s*[+−-]?[\d\s,.]+\s*$"#, options: .regularExpression) != nil
        guard labelled || pure else { return nil }
        return money(line.replacingOccurrences(of: ":", with: " "), allowBare: true)
    }
    static func installmentCandidates(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        let expanded = lines.flatMap { line -> [String] in
            let amounts = matches("(?<![\\d.,])(?:" + number + "\\s*" + currency + ")(?!\\d)", in: line)
            let dateTokens = matches(datePattern, in: line)
            if amounts.count > 1 || dateTokens.count > 1 { return amounts + dateTokens }
            return [line]
        }
        return expanded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { line in
            !line.isEmpty && seen.insert(line).inserted && (installmentAmount(line) != nil || installmentDate(line) != nil)
        }
    }
    static func installmentCandidateAmount(_ text: String) -> Int64? {
        guard let m = installmentAmount(text), m.currency != "USD", m.minor >= 0 else { return nil }; return m.minor
    }
    // PUMB "Сплачуйте частинами": the large unlabelled contract amount is
    // followed by the issue date and progress, then a two-column payment card.
    // A zero upcoming charge is NOT the regular instalment.
    static func pumbParts(_ lines: [String], regions: [ScanTextRegion] = []) -> ScanInstallmentDraft? {
        let rows = lines.map(bankClean).filter { !$0.isEmpty }
        let low = rows.map { $0.lowercased() }
        let joined = low.joined(separator: "\n")
        let title = joined.contains("сплачуйте частинами")
        let progressPattern = #"(?i)(?:внесено|сплачено)\s+(\d{1,3})\s+(?:з|із|їз|из|of)\s+(\d{1,3})\s+(?:щомісячних\s+)?платеж"#
        guard title || (joined.contains("оформлено") && joined.contains("наступний платіж") && (joined.contains("залишилося") || joined.contains("залишилось")) && !matches(progressPattern, in: joined).isEmpty) else { return nil }
        var d = ScanInstallmentDraft()
        d.pumbParts = true
        d.name = "ПУМБ · Сплачуйте частинами"
        d.foreignCurrency = rows.contains { hasUnsupportedCurrency($0) || !matches(#"(?i)(?:\bUSD\b|\$)"#, in: $0).isEmpty }
        let markedPattern = "(?<![\\d.,])(?:" + number + "\\s*" + currency + ")(?!\\d)"
        func amounts(_ text: String) -> [Int64] {
            matches(markedPattern, in: text).compactMap { token in
                guard let m = money(token), m.currency == "UAH", m.minor >= 0 else { return nil }; return m.minor
            }
        }
        func dates(_ text: String) -> [Date] { matches(datePattern, in: text).compactMap { bankDate($0) } }
        func single<T: Hashable>(_ values: [T]) -> T? { Set(values).count == 1 ? values.first : nil }
        let progressRows = rows.indices.filter { !matches(progressPattern, in: rows[$0]).isEmpty }
        if let index = progressRows.first, progressRows.count == 1 {
            let fragment = matches(progressPattern, in: rows[index]).first ?? ""
            let counts = matches(#"\d{1,3}"#, in: fragment).compactMap(Int.init)
            if counts.count == 2, counts[1] > 0, counts[0] <= counts[1] {
                d.paidCount = counts[0]; d.paymentCount = counts[1]
            }
            // Only the header above the progress belongs to the contract total.
            // A competing amount in this area invalidates the assumption.
            d.total = single(rows[..<index].flatMap(amounts).filter { $0 > 0 })
        }
        if let issue = low.firstIndex(where: { $0.contains("оформлено") }) {
            d.opened = single(dates(rows[issue]))
            if progressRows.isEmpty, d.total == nil, issue > 0, let value = single(amounts(rows[issue-1])), value > 0 { d.total = value }
        }
        let nextLabels = low.indices.filter { low[$0].contains("наступний платіж") }
        let restLabels = low.indices.filter { low[$0].contains("залишилося") || low[$0].contains("залишилось") }
        if nextLabels.count == 1, restLabels.count == 1, let l = nextLabels.first, let r = restLabels.first {
            if l == r, let nextRange = low[l].range(of: "наступний платіж"), let restRange = low[l].range(of: "залишил"), nextRange.lowerBound < restRange.lowerBound {
                // Vision often merges each pair of cells into one line.
                let stop = min(rows.count, l + 5)
                let card = rows[l..<stop].prefix { !$0.lowercased().contains("внести платіж") && !$0.lowercased().contains("сплатити повністю") && !$0.lowercased().contains("самостійно") }
                let values = card.flatMap(amounts)
                let datesFound = card.flatMap(dates)
                if values.count == 2 { d.nextAmount = values[0]; d.remaining = values[1] }
                if datesFound.count == 2 { d.bankNextDue = datesFound[0]; d.finalDue = datesFound[1] }
            } else if l != r {
                func cell(_ index: Int, other: Int) -> ([Int64], [Date]) {
                    let end = min(rows.count, index + 3, other > index ? other : rows.count)
                    let cell = rows[index..<end].prefix { !$0.lowercased().contains("внести платіж") && !$0.lowercased().contains("сплатити повністю") }
                    return (cell.flatMap(amounts), cell.flatMap(dates))
                }
                let a = cell(l, other: r), b = cell(r, other: l)
                d.nextAmount = single(a.0); d.remaining = single(b.0)
                d.bankNextDue = single(a.1); d.finalDue = single(b.1)
            }
        }
        // Use column alignment if the text rows were emitted in an unexpected order.
        func spatialCell(_ predicate: (String) -> Bool) -> (Int64?, Date?) {
            let labels = regions.filter { predicate($0.text.lowercased()) }
            guard labels.count == 1, let label = labels.first else { return (nil, nil) }
            let below = regions.filter { candidate in
                let overlap = min(label.bounds.maxX, candidate.bounds.maxX) - max(label.bounds.minX, candidate.bounds.minX)
                return candidate.bounds.midY < label.bounds.midY && label.bounds.midY - candidate.bounds.midY <= 0.10 && overlap >= min(label.bounds.width, candidate.bounds.width) * 0.25
            }
            return (single(below.flatMap { amounts($0.text) }), single(below.flatMap { dates($0.text) }))
        }
        let a = spatialCell { $0.trimmingCharacters(in: .whitespaces) == "наступний платіж" }
        let b = spatialCell { ["залишилося", "залишилось"].contains($0.trimmingCharacters(in: .whitespaces)) }
        func reconcile<T: Equatable>(_ x: T?, _ y: T?) -> T? { if let x, let y, x != y { return nil }; return x ?? y }
        d.nextAmount = reconcile(d.nextAmount, a.0); d.remaining = reconcile(d.remaining, b.0)
        d.bankNextDue = reconcile(d.bankNextDue, a.1); d.finalDue = reconcile(d.finalDue, b.1)
        if let total = d.total, let remaining = d.remaining, remaining > total { d.remaining = nil }
        // Exact equal-payment inference only if the independently read remaining
        // balance and progress agree. No rounding or arbitrary interest assumptions.
        if let total = d.total, let remaining = d.remaining, let count = d.paymentCount, let paid = d.paidCount, total > 0,
           total % Int64(count) == 0, total / Int64(count) * Int64(count - paid) == remaining {
            d.monthly = total / Int64(count)
            d.monthlyEstimated = true
        }
        // The existing ledger's due means the first *nonzero* charge. Do not
        // schedule a fictitious payment on a zero-charge date.
        if let amount = d.nextAmount, let remaining = d.remaining {
            if amount > 0 && amount <= remaining { d.due = d.bankNextDue }
            else if amount == 0, remaining > 0, let paid = d.paidCount, let count = d.paymentCount, count - paid == 1,
                    let next = d.bankNextDue, let final = d.finalDue, final > next { d.due = final }
            else if remaining == 0 { d.due = d.finalDue ?? d.bankNextDue }
        }
        return d
    }
    static func installment(_ input: [String], reference: Date = Date(), regions: [ScanTextRegion] = []) -> ScanInstallmentDraft {
        let lines = input.map(bankClean).filter { !$0.isEmpty }
        if let pumb = pumbParts(lines, regions: regions) { return pumb }
        let plan = purchasePlan(lines, reference: reference)
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
            if groups(line).isEmpty && (amountOnly(line) != nil || (nextPaymentDate(line, reference: reference) != nil && installmentAmount(line) == nil)) { return .value }
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
        if let plan {
            if draft.name.isEmpty { draft.name = plan.name }
            if values[0].isEmpty { draft.total = plan.total }
            if values[1].isEmpty && draft.remaining == nil { draft.remaining = plan.remaining }
            if values[2].isEmpty { draft.monthly = plan.monthly }
            if dates.isEmpty { draft.due = plan.due }
            draft.foreignCurrency = draft.foreignCurrency || plan.foreignCurrency
        }
        if !regions.isEmpty {
            let layout = installmentLayout(regions, reference: reference)
            // Spatial evidence supplements missing fields, never overwrites a
            // result or resolves explicitly contradictory text values.
            if draft.total == nil && values[0].isEmpty { draft.total = layout.total }
            if draft.remaining == nil && values[1].isEmpty { draft.remaining = layout.remaining }
            if draft.monthly == nil && values[2].isEmpty { draft.monthly = layout.monthly }
            if draft.due == nil && dates.isEmpty { draft.due = layout.due }
            draft.foreignCurrency = draft.foreignCurrency || layout.foreignCurrency
            if let total = draft.total, let remaining = draft.remaining, remaining > total {
                draft.total = nil; draft.remaining = nil
            }
        }
        return draft
    }
    // Vision sometimes returns two columns as a single text observation.
    // Request per-substring bounding boxes for multi-value or multi-label rows.
    static func installmentSubregionRanges(_ text: String) -> [Range<String.Index>] {
        func ranges(_ pattern: String) -> [Range<String.Index>] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
        }
        let amountRanges = ranges("(?<![\\d.,])(?:" + number + "\\s*" + currency + "|" + currency + "\\s*" + number + ")(?!\\d)")
        var fields: [(Int, Range<String.Index>)] = []
        if !text.lowercased().contains("дата") {
            for k in 0..<3 {
                var labels = installmentLabels[k]
                if k == 1 { labels += ["залишилось", "залишилося", "залишок"] }
                for label in labels.sorted(by: { $0.count > $1.count }) {
                    let pattern = "(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: label) + "(?![\\p{L}])"
                    for range in ranges(pattern) where !fields.contains(where: { $0.1.overlaps(range) }) {
                        fields.append((k, range))
                    }
                }
            }
        }
        guard amountRanges.count > 1 || Set(fields.map { $0.0 }).count > 1 else { return [] }
        return (fields.map { $0.1 } + amountRanges).sorted { $0.lowerBound < $1.lowerBound }
    }
    // Separate labels and numbers in different columns or stacked cards. Only
    // use a uniquely associated amount, never a count, date, or free-floating integer.
    static func installmentLayout(_ regions: [ScanTextRegion], reference: Date = Date()) -> ScanInstallmentDraft {
        var draft = ScanInstallmentDraft()
        let clean = regions.map { ScanTextRegion(text: bankClean($0.text), bounds: $0.bounds) }
        draft.foreignCurrency = clean.contains { hasUnsupportedCurrency($0.text) || money($0.text)?.currency == "USD" }
        func kind(_ text: String) -> Int? {
            let low = text.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            if low.contains("дата") || low.contains("час") || low.contains("графік") { return nil }
            if ["залишилось", "залишилося", "залишок", "до сплати залишилось"].contains(low) { return 1 }
            let kinds = (0..<3).filter { i in installmentLabels[i].contains { low.contains($0) } }
            return kinds.count == 1 ? kinds.first : nil
        }
        func isolatedAmount(_ text: String) -> Int64? {
            // A split currency observation or a decimal amount is acceptable,
            // but an isolated integer could be a payment count or card suffix.
            guard text.range(of: #"^\s*[+−-]?(?:₴\s*)?[\d\s,.]+(?:₴|грн\.?|UAH)?\s*$"#, options: [.regularExpression,.caseInsensitive]) != nil,
                  !matches(currency, in: text).isEmpty || text.range(of: #"[,.]\d{2}\s*$"#, options: .regularExpression) != nil else { return nil }
            if matches(currency, in: text).isEmpty && text.range(of: #"^\s*(?:0?[1-9]|[12]\d|3[01])\.(?:0[1-9]|1[0-2])\s*$"#, options: .regularExpression) != nil { return nil }
            return installmentCandidateAmount(text)
        }
        let labels = clean.indices.filter { kind(clean[$0].text) != nil && installmentAmount(clean[$0].text) == nil && nextPaymentDate(clean[$0].text, reference: reference) == nil }
        let amounts = clean.indices.filter { isolatedAmount(clean[$0].text) != nil }
        func distance(_ label: CGRect, _ amount: CGRect) -> Double? {
            let h: CGFloat = max(label.height, amount.height, 0.012)
            let overlap: CGFloat = min(label.maxX, amount.maxX) - max(label.minX, amount.minX)
            let gapY: CGFloat = max(0, max(label.minY, amount.minY) - min(label.maxY, amount.maxY))
            let gapX: CGFloat = max(0, max(label.minX, amount.minX) - min(label.maxX, amount.maxX))
            let centerGapY = abs(label.midY - amount.midY)
            let centerGapX = abs(label.midX - amount.midX)
            let leftGap = abs(label.minX - amount.minX)
            let minimumOverlap = min(label.width, amount.width) * 0.35
            if centerGapY <= h * 0.45 && gapX <= 0.55 {
                return Double(gapX * 0.25 + centerGapY)
            }
            if (overlap >= minimumOverlap || leftGap < 0.035), gapY <= min(0.065, h * 2.0) {
                return Double(gapY + centerGapX * 0.12 + 0.015)
            }
            return nil
        }
        var proposals: [(label: Int, amount: Int)] = []
        for l in labels {
            let ranked = amounts.compactMap { a in distance(clean[l].bounds, clean[a].bounds).map { (a, $0) } }.sorted { $0.1 < $1.1 }
            guard let best = ranked.first, ranked.count == 1 || ranked[1].1 - best.1 > 0.012 else { continue }
            // A closer label in a different field owns this number instead.
            let competitors = labels.filter { $0 != l && kind(clean[$0].text) != kind(clean[l].text) }.compactMap { distance(clean[$0].bounds, clean[best.0].bounds) }
            guard !competitors.contains(where: { $0 <= best.1 + 0.012 }) else { continue }
            proposals.append((l, best.0))
        }
        var values = Array(repeating: Set<Int64>(), count: 3)
        for pair in proposals {
            if let k = kind(clean[pair.label].text), let a = isolatedAmount(clean[pair.amount].text) { values[k].insert(a) }
        }
        draft.total = values[0].count == 1 ? values[0].first : nil
        draft.remaining = values[1].count == 1 ? values[1].first : nil
        draft.monthly = values[2].count == 1 ? values[2].first : nil
        let dateLabels = clean.indices.filter { i in
            let low = clean[i].text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            return installmentLabels[3].contains(low) && nextPaymentDate(low, reference: reference) == nil
        }
        let dateValues = clean.indices.filter { i in
            let text = clean[i].text
            return nextPaymentDate(text, reference: reference) != nil && installmentAmount(text) == nil && !text.lowercased().contains("дата")
        }
        var foundDates = Set<Date>()
        for label in dateLabels {
            let ranked = dateValues.compactMap { i in distance(clean[label].bounds, clean[i].bounds).map { (i, $0) } }.sorted { $0.1 < $1.1 }
            if let first = ranked.first, ranked.count == 1 || ranked[1].1 - first.1 > 0.012, let date = nextPaymentDate(clean[first.0].text, reference: reference) { foundDates.insert(date) }
        }
        if foundDates.count == 1 { draft.due = foundDates.first }
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
    result.pumbParts = drafts.contains { $0.pumbParts }
    result.paymentCount = unique(drafts.compactMap(\.paymentCount), "Кількість платежів")
    result.paidCount = unique(drafts.compactMap(\.paidCount), "Сплачено платежів")
    result.nextAmount = unique(drafts.compactMap(\.nextAmount), "Найближчий внесок")
    result.bankNextDue = unique(drafts.compactMap(\.bankNextDue), "Найближча дата банку")
    result.finalDue = unique(drafts.compactMap(\.finalDue), "Кінцева дата")
    result.opened = unique(drafts.compactMap(\.opened), "Дата оформлення")
    result.monthlyEstimated = drafts.contains { $0.monthlyEstimated } && result.monthly != nil
    if result.pumbParts && (!conflicts.isEmpty && (result.nextAmount == nil || result.bankNextDue == nil || result.finalDue == nil)) { result.due = nil }
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

// Bank-specific candidate label vocabulary. These are conservative text aliases,
// not verified bank screenshots or positional templates. Matching requires a
// known bank and an exact normalized label; no amounts are stored in rules.
enum FinamiOCRField: String, CaseIterable, Codable {
    case total, remaining, monthly
    var canonical: String {
        switch self { case .total: return "Загальна сума розстрочки"; case .remaining: return "Поточний залишок"; case .monthly: return "Щомісячний платіж" }
    }
}
enum FinamiOCRProfiles {
    static let banks = ["ПУМБ", "monobank", "ПриватБанк", "А-БАНК", "ОТП", "Sense Bank", "Райффайзен"]
    static let storageKey = "finami.ocr.labelRules.v1"
    static func label(_ raw: String) -> String? {
        let text = bankClean(raw.lowercased().replacingOccurrences(of: "’", with: "'"))
        // Only an explicit label followed by a single amount, or a label-only row.
        let amountPattern = "\\s*[:–—-]?\\s*" + FinamiScanParser.number + "\\s*" + FinamiScanParser.currency + "\\s*$"
        let stripped = text.replacingOccurrences(of: amountPattern, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: CharacterSet(charactersIn: " :–—-"))
        guard stripped.count >= 5, stripped.count <= 70, stripped.range(of: #"^[\p{L}\s'’-]+$"#, options: .regularExpression) != nil,
              ["сума", "залиш", "платіж", "платеж", "внесок", "борг", "кредит", "вартість", "погаш", "розстроч"].contains(where: { stripped.contains($0) }),
              !["дата", "час", "комісі", "відсот", "ліміт", "сплачено", "погашено", "картк", "номер", "кількіст", "простроч", "штраф", "графік"].contains(where: { stripped.contains($0) }) else { return nil }
        return stripped
    }
    static func builtIn(_ bank: String) -> [String: FinamiOCRField] {
        switch bank {
        case "ПУМБ": return ["сума оформленої розстрочки": .total, "залишок за тілом кредиту": .remaining, "щомісячний внесок за розстрочкою": .monthly]
        case "monobank": return ["сума покупки частинами": .total, "залишок за покупкою частинами": .remaining, "платіж частинами щомісяця": .monthly]
        case "ПриватБанк": return ["сума оплати частинами": .total, "залишок за оплатою частинами": .remaining, "щомісячний внесок за договором": .monthly]
        case "А-БАНК": return ["загальна сума платежу частинами": .total, "залишок за платежем частинами": .remaining, "щомісячний платіж за договором": .monthly]
        case "ОТП", "Sense Bank", "Райффайзен": return ["початковий розмір кредиту": .total, "непогашений основний борг": .remaining, "плановий щомісячний внесок": .monthly]
        default: return [:]
        }
    }
    static func rewrite(_ text: String, rules: [String: FinamiOCRField]) -> String {
        guard !FinamiScanParser.hasUnsupportedCurrency(text), let key = label(text), let field = rules[key] else { return text }
        if let amount = FinamiScanParser.money(text), amount.currency == "UAH", amount.minor >= 0 {
            return field.canonical + ": " + String(amount.minor / 100) + "," + String(format: "%02lld", amount.minor % 100) + " ₴"
        }
        guard text.range(of: #"\d"#, options: .regularExpression) == nil else { return text }
        return field.canonical
    }
    static func learned(_ bank: String, defaults: UserDefaults = .standard) -> [String: FinamiOCRField] {
        guard banks.contains(bank), let data = defaults.data(forKey: storageKey), let rules = try? JSONDecoder().decode([String: [String: FinamiOCRField]].self, from: data) else { return [:] }
        return rules[bank] ?? [:]
    }
    static func rules(_ bank: String?, defaults: UserDefaults = .standard) -> [String: FinamiOCRField] {
        guard let bank, banks.contains(bank) else { return [:] }
        return builtIn(bank).merging(learned(bank, defaults: defaults)) { _, personal in personal }
    }
    static func learn(bank: String, raw: String, field: FinamiOCRField, defaults: UserDefaults = .standard) {
        guard banks.contains(bank), let key = label(raw), let amount = FinamiScanParser.money(raw), amount.currency == "UAH", amount.minor >= 0 else { return }
        if let builtIn = builtIn(bank)[key], builtIn != field { return }
        // Learning is intentionally conservative: do not remap a known field.
        for other in FinamiOCRField.allCases where other != field {
            let probe = FinamiScanParser.installment([raw])
            if (other == .total && probe.total != nil) || (other == .remaining && probe.remaining != nil) || (other == .monthly && probe.monthly != nil) { return }
        }
        var all = defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode([String: [String: FinamiOCRField]].self, from: $0) } ?? [:]
        var rules = all[bank] ?? [:]
        guard rules.count < 64 || rules[key] != nil else { return }
        if let prior = rules[key], prior != field { return }
        rules[key] = field; all[bank] = rules
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: storageKey) }
    }
}
