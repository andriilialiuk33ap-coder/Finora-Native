import Foundation

// Geometry adapter: y is the normalized line midpoint measured from the top of an A4 page.
// Separating numeric columns prevents transaction currency, account amount and fee from mixing.
struct FinamiPrivatLine: Codable {
    let y: Double
    let text: String
}
struct FinamiPrivatPage: Codable {
    let columns: [[FinamiPrivatLine]]
}
struct FinamiPrivatParsedRow {
    let row: BankRow
    let balance: Int64
}
private func privatMatches(_ value:String,_ pattern:String)->Bool { value.range(of:pattern,options:.regularExpression) != nil }
private func privatCapture(_ text:String,_ pattern:String)->String? {
    guard let re=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),m.numberOfRanges>1,let r=Range(m.range(at:1),in:text) else{return nil}
    return String(text[r])
}
func privatStatementIBAN(_ text:String)->String? { privatCapture(bankClean(text),#"рахунок\s+IBAN\s*:?\s*(UA(?:[ ]*[0-9]){27})(?![0-9])"#).flatMap(bankNormalizedIBAN) }
func privatStatementMask(_ text:String)->String? { privatCapture(bankClean(text),#"інформація\s+по\s+картці\s*:?\s*([0-9]{6}[*xX•]{6}[0-9]{4})(?![0-9])"#).flatMap(bankRowMask) }
private let privatCategories:[(String,String)] = [
    ("супермаркети та продукти","🛒 Продукти"),("ресторани, кафе, бари","🍽️ Ресторани"),("таксі","🚕 Таксі"),("транспорт","🚗 Транспорт"),("тварини","🐾 Тварини"),("аптеки","💊 Здоров’я"),("комунальні","🧾 Комунальні"),("зв’язок","📱 Зв’язок"),("зв'язок","📱 Зв’язок"),("одяг","👕 Одяг"),("цифрові товари",""),("послуги","")
]
private func privatDescription(_ text:String,signed:Int64)->(note:String,type:String,hint:String?) {
    let clean=bankClean(text), lower=clean.lowercased()
    if signed < 0 && (lower.contains("оплати частинами") || lower.contains("оплата частинами")) { return ("Оплата частинами", "Погашення кредиту",nil) }
    if signed < 0 && lower.contains("списання відсотків") {return ("Відсотки за кредитом","Покупка","🏦 Комісії")}
    if lower.contains("повернення") && signed > 0 {return ("Повернення коштів","Повернення коштів",nil)}
    if signed > 0 {return (lower.contains("зарахування переказу") ? "Зарахування переказу" : "Зарахування", "Надходження",nil)}
    if lower.contains("переказ") || lower.contains("зняття готівки") {return (lower.contains("зняття готівки") ? "Зняття готівки" : "Переказ", "Списання",nil)}
    let category=privatCategories.first{lower.hasPrefix($0.0)}
    let merchant=privatCapture(clean,#"отримувач\s+(.{1,100}?),\s*банк"#)
    if let category {return (bankRedact(merchant ?? String(clean.prefix(category.0.count))),"Покупка",category.1.isEmpty ? nil : category.1)}
    if let merchant {return (bankRedact(merchant),"Покупка",nil)}
    // Never infer that an unknown debit is a purchase, nor persist unfiltered counterparty data.
    return ("Списання · уточнити", "Списання",nil)
}
func privatParsePage(_ page:FinamiPrivatPage,mask:String) -> (rows:[FinamiPrivatParsedRow],rejected:Int) {
    guard page.columns.count==7 else{return ([],1)}
    let cols=page.columns.map { $0.map{FinamiPrivatLine(y:$0.y,text:bankClean($0.text))}.sorted{$0.y<$1.y} }
    let dates=cols[0].filter{privatMatches($0.text,#"^\d{2}\.\d{2}\.\d{4}$"#)}
    let number=#"^[+−-]?\d+(?:[ ]\d{3})*[.,]\d{2}$"#
    var groups:[[FinamiPrivatLine]]=[]
    for line in cols[1] where line.y>200 {
        if let last=groups.last?.last,line.y-last.y<=10 {groups[groups.count-1].append(line)} else {groups.append([line])}
    }
    func at(_ index:Int,_ y:Double,_ pattern:String)->String? {
        let matches=cols[index].filter{abs($0.y-y)<3 && privatMatches($0.text,pattern)}
        return matches.count==1 ? matches[0].text:nil
    }
    var parsed:[FinamiPrivatParsedRow]=[],rejected=0
    for anchor in dates {
        let y=anchor.y
        let descriptions=groups.filter{ group in guard let first=group.first,let last=group.last else{return false};return first.y-5<=y+4 && last.y+5>=y+4 }
        guard descriptions.count==1,
              let time=at(0,y+8,#"^\d{2}:\d{2}$"#),let date=bankDate(anchor.text+" "+time),
              let originalText=at(2,y,number),let original=bankMinor(originalText),let currency=at(2,y+8,#"^[A-Z]{3}$"#),
              let amountText=at(3,y+4,number),let signed=bankMinor(amountText),signed != 0,
              let feeText=at(4,y+4,number),let fee=bankMinor(feeText),
              let balanceText=at(6,y+4,number),let balance=bankMinor(balanceText) else {rejected+=1;continue}
        let raw=descriptions[0].map(\.text).joined(separator:" ")
        let info=privatDescription(raw,signed:signed)
        var row=BankRow(source:"ПриватБанк",date:date,signed:signed,note:info.note,original:abs(original),currency:currency,fee:abs(fee),operationType:info.type,cardLastFour:mask)
        row.categoryHint=info.hint
        // Running balance distinguishes identical purchases at the same minute, without retaining identifiers from the PDF.
        row.reference=[mask,String(Int64(date.timeIntervalSince1970)),String(signed),String(balance)].joined(separator:"|")
        parsed.append(.init(row:row,balance:balance))
    }
    return (parsed,rejected)
}
func privatStatementBatch(header:String,pages:[FinamiPrivatPage]) throws -> BankBatch {
    let clean=bankClean(header)
    guard clean.localizedCaseInsensitiveContains("Виписка по картці"),clean.localizedCaseInsensitiveContains("ПриватБанк"),clean.localizedCaseInsensitiveContains("Валюта рахунку: UAH"),let iban=privatStatementIBAN(clean),let mask=privatStatementMask(clean),let opening=bankSummary(clean,label:"Баланс на початок періоду"),let closing=bankSummary(clean,label:"Баланс на кінець періоду"),let debit=bankSummary(clean,label:"Усього витрат"),let credit=bankSummary(clean,label:"Усього надходжень") else{throw BankFailure.format}
    var entries:[FinamiPrivatParsedRow]=[],rejected=0
    for page in pages {let p=privatParsePage(page,mask:mask);entries += p.rows;rejected += p.rejected}
    guard !entries.isEmpty else{throw BankFailure.empty}
    // Statement is in reverse chronological order; do not sort by minutes (ties retain PDF order).
    // Fail closed rather than importing a partial or misaligned statement.
    var running=opening,spent:Decimal=0,incoming:Decimal=0
    for entry in entries.reversed() {
        let (next,overflow)=running.addingReportingOverflow(entry.row.signed)
        guard !overflow,next==entry.balance else{throw BankFailure.statementMismatch}
        running=next
        if entry.row.signed<0 {spent -= Decimal(entry.row.signed)} else {incoming += Decimal(entry.row.signed)}
    }
    guard running==closing,spent==Decimal(abs(debit)),incoming==Decimal(abs(credit)),rejected==0,Set(entries.map{$0.row.key}).count==entries.count else{throw BankFailure.statementMismatch}
    return BankBatch(rows:entries.reversed().map(\.row),rejected:0,reconciliation:"Суми та залишки всіх рядків збігаються з випискою. Комісії не списано повторно.",statementLastFour:mask,statementIBAN:iban,opening:opening,closing:closing,statementMasks:[mask])
}
