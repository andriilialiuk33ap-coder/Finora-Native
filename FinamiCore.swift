import Foundation

// Forecast scheduled payments without treating them as actual transactions.
func finamiScheduledAmounts(start: Date, amount: Int64, remaining: Int64?, subsequentAmount: Int64? = nil, component: Calendar.Component, step: Int, from: Date, until: Date, calendar: Calendar = .current) -> [Int64] {
    guard amount > 0, step > 0, until > from else { return [] }
    // Do not silently assume overdue installments were paid. An overdue entry stays in the calendar separately.
    guard start >= from else { return [] }
    var date = start, left = remaining, result: [Int64] = []
    while date < until && result.count < 366 {
        let planned = result.isEmpty ? amount : (subsequentAmount ?? amount)
        let charge = min(planned, left ?? planned)
        guard charge > 0 else { break }
        result.append(charge)
        if let balance = left { left = balance - charge }
        guard let next = calendar.date(byAdding: component, value: step, to: date), next > date else { break }
        date = next
    }
    return result
}

// Use only an unambiguous numeric amount; users confirm all voice drafts.
func finamiVoiceAmount(_ text: String) -> Int64? {
    let pattern = #"(?<![\d.,])\d+(?:[ \u00a0\u202f]\d{3})*(?:[,.]\d{1,2})?(?![\d.,])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard matches.count == 1, let range = Range(matches[0].range, in: text) else { return nil }
    let raw = text[range].filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
    guard let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), amount > 0, amount <= 10_000_000_000 else { return nil }
    return NSDecimalNumber(decimal: amount * 100).int64Value
}
