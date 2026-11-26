import Foundation

// Conservative merchant normalization. Never infer a transfer or income from a vendor name.
func finamiMerchantKey(_ raw: String) -> String {
    var text = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA")).lowercased()
    text = text.replacingOccurrences(of: #"\b(?:kyiv|kiev|київ|vinnytsia|vinnytsya|vinnitsa|вінниця|ukraine|україна|uaua|ua|tallinn|eeee)\b"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\bbolt[ ._/]*eu[ ._/]*o?[ ._/]*[0-9]+\b"#, with: "bolt", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\bplaton[0-9]* +uklon(?: +[mv])?\b"#, with: "uklon", options: .regularExpression)
    let tokens = text.split(separator: " ").map(String.init)
    let canonical = tokens.filter { !["easypay", "purchase", "оплата", "купівля"].contains($0) }
    let key = canonical.joined(separator: " ")
    let variants = ["бадді":"baddi","бадди":"baddi","чил тайм":"chill time","чіл тайм":"chill time","чіл таим":"chill time","чил таим":"chill time","для своїх":"dlyasvoyih","для своіх":"dlyasvoyih","dlya svoyih":"dlyasvoyih","dlia svoikh":"dlyasvoyih","окраса":"okrasa","наше пиво":"nashe pivo","bolt eu":"bolt","уклон":"uklon"]
    return variants[key] ?? key
}
func finamiIntelligentCategory(_ note: String, kind: Kind, allowed: [String], learned: [String: String]) -> String {
    let prefix = kind.rawValue + ":"
    let key = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let exact = learned[prefix + key], allowed.contains(exact) { return exact }
    let normalized = finamiMerchantKey(note)
    guard !normalized.isEmpty else { return "Без категорії" }
    let matching = Set(learned.compactMap { pair -> String? in
        guard pair.key.hasPrefix(prefix), allowed.contains(pair.value), finamiMerchantKey(String(pair.key.dropFirst(prefix.count))) == normalized else { return nil }
        return pair.value
    })
    if matching.count == 1, let match = matching.first { return match }
    if matching.count > 1 { return "Без категорії" }
    let tokens = Set(normalized.split(separator: " ").map(String.init))
    let rules: [([String], String)]
    if kind == .income {
        rules = [(["зарплата", "заробітна плата", "salary"], "💼 Зарплата"), (["кешбек", "cashback", "нагороди з пумб", "виплата винагороди"], "💵 Кешбек"), (["відсотки", "interest"], "📈 Відсотки")]
    } else if kind == .expense {
        rules = [(["uklon", "bolt", "1taxi"], "🚕 Таксі"), (["atb", "атб", "atб", "silpo", "сільпо", "thrash", "torba", "novus", "varus", "фора"], "🛒 Продукти"), (["lifecell", "київстар", "kyivstar", "vodafone"], "📱 Зв’язок"), (["apteka", "аптека", "tabletki"], "💊 Здоров’я"), (["netflix", "spotify", "youtube premium", "apple music", "icloud"], "📺 Підписки"), (["utility", "комунальні"], "🧾 Комунальні"), (["kavy ta chaiu", "coffee", "кава"], "☕ Кава"), (["wog", "okko", "upg"], "⛽ Паливо"), (["нова пошта", "nova poshta", "ukrposhta", "укрпошта"], "📦 Доставка"), (["barnomertri", "bar bulvar", "smachna pica z soboiu", "dyadya doner", "catcafe", "kafelvivskikruasani"], "🍽️ Ресторани"), (["avrora"], "🏠 Дім"), (["zoosalon", "limpopo"], "🐾 Тварини"), (["vinntravel"], "🚗 Транспорт"), (["roshen", "magazinprodukti", "mahazyn tor"], "🛒 Продукти")]
    } else { return "Без категорії" }
    let found = Set(rules.filter { aliases, category in
        allowed.contains(category) && aliases.contains { alias in
            alias.contains(" ") ? (" " + normalized + " ").contains(" " + alias + " ") : tokens.contains(alias)
        }
    }.map { $0.1 })
    return found.count == 1 ? found.first! : "Без категорії"
}

struct FinamiRecurringCandidate: Identifiable, Equatable {
    let id: String
    let merchant: String
    let account: String
    let currency: String
    let amount: Int64
    let previousAmount: Int64
    let next: Date
    let count: Int
    let cadence: String
    let operationIDs: [String]
    var changedPrice: Bool { previousAmount > 0 && amount > previousAmount && Double(amount - previousAmount) / Double(previousAmount) >= 0.05 }
}

// Only a suggestion: no ledger changes or automatic subscription creation.
func finamiRecurringCandidates(operations: [Operation], accounts: [Account], now: Date = Date(), calendar: Calendar = .current) -> [FinamiRecurringCandidate] {
    let codes = Dictionary(accounts.map { ($0.id, $0.code) }, uniquingKeysWith: { a, _ in a })
    let cutoff = calendar.date(byAdding: .month, value: -14, to: now) ?? now
    let rows = operations.filter { $0.kind == .expense && $0.date <= now && $0.date >= cutoff && $0.amount > 0 && codes[$0.account] != nil }
    let groups = Dictionary(grouping: rows) { o in o.account + "|" + (codes[o.account] ?? "") + "|" + finamiMerchantKey(o.note) }
    return groups.compactMap { key, values in
        let sorted = values.sorted { $0.date < $1.date }
        guard sorted.count >= 3, let last = sorted.last, let currency = codes[last.account] else { return nil }
        let merchant = finamiMerchantKey(last.note)
        guard merchant.count >= 3, !["apple com bill", "google", "google play", "покупка", "переказ", "інше"].contains(merchant), currency == "UAH" || sorted.allSatisfy({$0.sourceMinor != nil && $0.entryCurrency == currency}) else { return nil }
        // Last three charges must be regularly spaced. Daily shopping does not qualify.
        let recent = Array(sorted.suffix(3))
        let days = zip(recent, recent.dropFirst()).map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: calendar.startOfDay(for: $1.date)).day ?? 0 }
        let monthly = days.allSatisfy { (25...35).contains($0) }
        let weekly = recent.allSatisfy { $0.category.localizedCaseInsensitiveContains("Підписки") } && days.allSatisfy { (6...8).contains($0) }
        guard monthly || weekly else { return nil }
        guard recent.allSatisfy({ $0.category == "Без категорії" || $0.category == "Інше" || $0.category.localizedCaseInsensitiveContains("Підписки") || $0.category.localizedCaseInsensitiveContains("Зв’язок") || $0.category.localizedCaseInsensitiveContains("Комунальні") }) else { return nil }
        let previous = recent[1].sourceMinor ?? recent[1].amount
        let first = recent[0].sourceMinor ?? recent[0].amount
        let amount = last.sourceMinor ?? last.amount
        guard first > 0, previous > 0, amount > 0, abs(Double(first)-Double(previous)) / Double(previous) <= 0.05, abs(Double(amount)-Double(previous)) / Double(previous) <= 0.30 else { return nil }
        guard let next = calendar.date(byAdding: monthly ? .month : .day, value: monthly ? 1 : 7, to: last.date), let grace = calendar.date(byAdding: .day, value: monthly ? 14 : 4, to: next), grace >= now else { return nil }
        return FinamiRecurringCandidate(id: key, merchant: last.note, account: last.account, currency: currency, amount: amount, previousAmount: previous, next: next, count: sorted.count, cadence: monthly ? "month" : "week", operationIDs: recent.map(\.id))
    }.sorted { $0.next == $1.next ? $0.id < $1.id : $0.next < $1.next }
}

struct FinamiReconciliationResult: Equatable {
    let computedAtObservation: Int64
    let reported: Int64
    let laterOperations: Int
    let possibleUnclassified: Int
    var difference: Int64 { reported - computedAtObservation }
}
// Compare the bank amount with the ledger at the same timestamp, not today's balance.
func finamiReconcile(account: Account, operations: [Operation], observedAt: Date, reported: Int64) -> FinamiReconciliationResult {
    let relevant = operations.filter { $0.account == account.id || ($0.kind == .transfer && $0.destination == account.id) }
    let historical = relevant.filter { $0.date <= observedAt }
    let available = CardPosition(net: FinamiLedgerIndex(operations: relevant).balanceAt(account,date:observedAt), limit: account.limit).available
    return .init(computedAtObservation: available, reported: reported, laterOperations: relevant.count - historical.count, possibleUnclassified: historical.filter { $0.kind.needsReview }.count)
}

struct FinamiPlannedOccurrence: Identifiable, Equatable {
    let id: String
    let paymentID: String
    let date: Date
    let amount: Int64
    let projected: Bool
}
func finamiPlannedOccurrences(id: String, start: Date, amount: Int64, remaining: Int64?, subsequentAmount: Int64? = nil, component: Calendar.Component, step: Int, interval: DateInterval, calendar: Calendar = .current) -> [FinamiPlannedOccurrence] {
    guard amount > 0, step > 0 else { return [] }
    var result: [FinamiPlannedOccurrence] = [], date = start, left = remaining
    // Bounded loop protects against malformed legacy dates and infinite schedules.
    for index in 0..<2400 {
        guard date < interval.end else { break }
        let planned = index == 0 ? amount : (subsequentAmount ?? amount)
        let charge = min(planned, left ?? planned)
        guard charge > 0 else { break }
        if date >= interval.start { result.append(.init(id: id + "|" + String(date.timeIntervalSinceReferenceDate), paymentID: id, date: date, amount: charge, projected: index > 0)) }
        if let value = left { left = value - charge }
        guard let next = calendar.date(byAdding: component, value: step, to: date), next > date else { break }
        date = next
    }
    return result
}

// Display only. Raw statement text stays intact for matching and audit.
func finamiMerchantDisplay(_ raw:String) -> String {
    let key=finamiMerchantKey(raw)
    let aliases:[String:String] = ["bolt":"Bolt","uklon":"Uklon","platon uklon":"Uklon","1taxi838":"1Taxi","lifecell":"lifecell","thrash":"THRASH!","torba":"TORBA","avrora":"Аврора","roshen":"ROSHEN","baddi":"Baddi","okrasa":"Okrasa","chill time":"Chill Time","dlyasvoyih":"Для Своїх","nashe pivo":"Наше пиво","barnomertri":"Бар №3","bar bulvar":"Bar Bulvar","smachna pica z soboiu":"Смачна піца з собою","dyadya doner":"Дядя Донер","zoosalon limpopo":"Зоосалон Лімпопо"]
    if let value=aliases[key] {return value}
    return raw
}
