import Foundation

// Search does not change stored category or operation identity.
enum FinamiSearchPolicy {
    static func normalized(_ text: String) -> String {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"uk_UA"))
            .replacingOccurrences(of:"’",with:"'")
    }
    static func matches(_ query:String,text:String)->Bool {
        let tokens=normalized(query).split(whereSeparator:{$0.isWhitespace})
        let target=normalized(text)
        return tokens.allSatisfy { target.contains($0) }
    }
    static func categoryName(_ name:String,icon:String)->String {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        let remaining=trimmed.drop(while:{$0.unicodeScalars.contains(where:{$0.properties.isEmojiPresentation || $0.value == 0xFE0F}) || $0.isWhitespace})
        let title=String(remaining)
        return title.isEmpty ? icon : icon+" "+title
    }
}

// Compact previews are presentation-only. The caller supplies existing payment amounts
// and dates; no totals are inferred across currencies or across overlapping sections.
enum FinamiDashboardPreviewPolicy {
    static func payments(count: Int, nextAmount: String?, nextDate: String?, overdue: Bool, masked: Bool) -> String {
        if masked { return "Суми приховано" }
        guard count > 0 else { return "Немає активних платежів" }
        var parts = ["Активні: \(count)"]
        if let nextDate { parts.append((overdue ? "Прострочено: " : "Наступний: ") + nextDate) }
        if let nextAmount { parts.append((nextDate == nil ? "До сплати: " : "") + nextAmount) }
        return parts.joined(separator: " · ")
    }
    static func accounts(count: Int, masked: Bool) -> String {
        if masked { return "Суми приховано" }
        return count == 0 ? "Немає видимих рахунків" : "В огляді: \(count)"
    }
}
