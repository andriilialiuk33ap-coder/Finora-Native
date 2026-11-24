import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Foundation-only code: exercised by tests on Linux and macOS.
struct BankRow: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var source: String
    var date: Date
    var signed: Int64 // actual change to the UAH account, in kopecks
    var note: String
    var mcc: Int? = nil
    var original: Int64? = nil
    var currency: String = "UAH"
    var fee: Int64 = 0
    var reference: String? = nil
    var warning: String? = nil
    var operationType: String? = nil
    var key: String { reference.map { source + ":" + $0 } ?? [source, String(Int64(date.timeIntervalSince1970)), String(signed), note.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " "), String(fee)].joined(separator: "|") }
}
struct BankBatch { var rows: [BankRow] = []; var rejected = 0; var reconciliation: String? = nil }
func bankReconcile(_ batch: BankBatch, debit: Int64?, credit: Int64?) -> String {
    guard let debit, let credit else {return "Підсумки банку не розпізнано. Звірте виписку вручну."}
    let out = batch.rows.filter{$0.signed<0}.reduce(Int64(0)){$0-$1.signed}
    let incoming = batch.rows.filter{$0.signed>0}.reduce(Int64(0)){$0+$1.signed}
    if out == abs(debit) && incoming == abs(credit) && batch.rejected == 0 {return "Суми рядків збігаються з підсумками виписки."}
    return "Увага: суми рядків не збігаються з підсумками банку. Перевірте комісії, коригування й залишок перед імпортом. Різниця списань: \(Double(out-abs(debit))/100) грн; зарахувань: \(Double(incoming-abs(credit))/100) грн."
}
func bankSummary(_ text:String,label:String)->Int64? {
    let clean=bankClean(text); guard let range=clean.range(of:NSRegularExpression.escapedPattern(for:label)+#"\s*:?\s*[-−]?\d+(?:[ ]\d{3})*[.,]\d{2}"#,options:[.regularExpression,.caseInsensitive]) else{return nil}
    let match=String(clean[range]);let suffix=String(match.dropFirst(label.count)).trimmingCharacters(in:CharacterSet(charactersIn:": "));return bankMinor(suffix)
}
enum BankFailure: LocalizedError {
    case format, unsupported, empty, network(Int), rate, invalidToken
    var errorDescription: String? {
        switch self {
        case .format: return "Не вдалося прочитати формат. Перевірте файл."
        case .unsupported: return "Формат або валюта рахунку поки не підтримуються."
        case .empty: return "Не знайдено операцій. Перевірте банк, формат і період."
        case .network(let code): return "Банк повернув помилку HTTP \(code)."
        case .rate: return "Ліміт API: повторіть запит через 60 секунд."
        case .invalidToken: return "Вкажіть персональний токен monobank."
        }
    }
}
func bankMinor(_ value: String) -> Int64? {
    var s = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "−", with: "-")
    s = s.filter { !$0.isWhitespace }
    if s.contains(",") && s.contains(".") { return nil }
    s = s.replacingOccurrences(of: ",", with: ".")
    guard s.range(of: #"^[+-]?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
          let x = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")), abs(x) <= 10_000_000_000 else { return nil }
    var v = x * 100; var rounded = Decimal(); NSDecimalRound(&rounded, &v, 0, .plain)
    return NSDecimalNumber(decimal: rounded).int64Value
}
func bankDate(_ s: String) -> Date? {
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "yyyy-MM-dd", "dd.MM.yyyy"] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Kyiv"); f.dateFormat = format; f.isLenient = false
        if let d = f.date(from: s), f.string(from: d) == s { return d }
    }
    return nil
}
func bankMoneyCell(_ s: String) -> (Int64, String)? {
    let parts = s.split(whereSeparator: \.isWhitespace); guard let code = parts.last, code.count == 3, let n = bankMinor(parts.dropLast().joined()) else { return nil }
    return (n, String(code))
}
func bankClean(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
func bankRedact(_ s: String) -> String {
    bankClean(s).replacingOccurrences(of: #"(?i)\bUA\d{27}\b"#, with: "[IBAN]", options: .regularExpression)
        .replacingOccurrences(of: #"\b\d{12,19}\b"#, with: "[рахунок]", options: .regularExpression)
}
func pumbRow(_ c: [String]) -> BankRow? {
    guard c.count == 7, let d = bankDate(bankClean(c[0])), let original = bankMoneyCell(c[1]), let amount = bankMoneyCell(c[2]), amount.1 == "UAH", amount.0 != 0, let commission = bankMoneyCell(c[3]), commission.1 == "UAH" else { return nil }
    let type = c[6].lowercased(); let positive = type.contains("надходження") || type.contains("повернення")
    guard positive || type.contains("покупка") || type.contains("списання") else { return nil }
    let fee = abs(commission.0), magnitude = abs(amount.0)
    // PUMB exposes fee separately; do not silently guess whether included. Review required when nonzero.
    return BankRow(source: "ПУМБ", date: d, signed: positive ? magnitude : -magnitude, note: bankRedact(c[5]), original: abs(original.0), currency: original.1, fee: fee, warning: fee > 0 ? "Комісія окремо: перевірте фактичне списання." : (c[0].contains(":") ? nil : "Час відсутній"), operationType: bankClean(c[6]))
}
func abankRow(_ c: [String]) -> BankRow? {
    guard c.count == 9, ["UAH","USD","EUR","PLN","GBP","CHF","CAD"].contains(bankClean(c[6])), let d = bankDate(bankClean(c[0])), let amount = bankMinor(c[4]), amount != 0, let original = bankMinor(c[5]) else { return nil }
    return BankRow(source: "А-БАНК", date: d, signed: amount, note: bankRedact(c[2]), mcc: Int(bankClean(c[3])), original: abs(original), currency: bankClean(c[6]), fee: abs(bankMinor(c[8]) ?? 0))
}
func excelBankDate(_ value: String) -> Date? {
    if let d = bankDate(value) { return d }
    guard let serial = Double(value), serial.isFinite, serial > 30_000, serial < 100_000 else { return nil }
    // Excel serial encodes a local wall-clock date, not UTC.
    let wall = Date(timeIntervalSince1970: ((serial - 25569) * 86400).rounded())
    let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return bankDate(f.string(from: wall))
}
func bankMCC(_ s:String) -> Int? { guard let n = Double(s), n.isFinite, n >= 0, n <= 9999, n.rounded() == n else { return nil }; return Int(n) }
func otpRow(_ c: [String]) -> BankRow? {
    guard c.count >= 21, bankClean(c[20]).lowercased() == "підтверджено", let d = excelBankDate(c[0]), c[7] == "UAH", let n = bankMinor(c[6]), n != 0 else { return nil }
    let incoming = c[1] == "Поповнення"; guard incoming || c[1] == "Списання" else { return nil }
    guard (incoming && n > 0) || (!incoming && n < 0) else { return nil }
    return BankRow(source: "ОТП", date: d, signed: n, note: bankRedact([c[13],c[19]].filter{ !$0.isEmpty }.joined(separator: " · ")), mcc: bankMCC(c[18]), original: bankMinor(c[8]).map(abs), currency: c[9], fee: abs(bankMinor(c[10]) ?? 0), warning: (bankMinor(c[10]) ?? 0) != 0 ? "Комісію не додано повторно; звірте суму." : nil, operationType: c[1])
}
// XLSX XML parsing independent of zip library; only values, never evaluate formulas.
final class BankXML: NSObject, XMLParserDelegate {
    var shared: [String] = []; var rows: [[String]] = []
    var row: [String] = []; var current = ""; var cell = ""; var kind = ""; var column = 0; var inText = false; var inValue = false; var inCell = false; var inShared = false; var isShared: Bool
    init(shared: Bool, strings: [String] = []) { isShared = shared; self.shared = strings }
    func parse(_ data: Data) throws { let p = XMLParser(data:data); p.shouldResolveExternalEntities = false; p.delegate = self; guard p.parse() else { throw BankFailure.format } }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String:String]) {
        if name == "si" { current = ""; inShared = true }
        if name == "row" { row = [] }
        if name == "c" { inCell = true; cell = ""; kind = a["t"] ?? ""; column = 0; for x in (a["r"] ?? "").utf8.prefix(while: { $0 >= 65 && $0 <= 90 }) { column = column * 26 + Int(x - 64) }; column -= 1 }
        if name == "t" { inText = true }
        if name == "v" { inValue = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inShared && inText { current += string }; if inCell && (inValue || inText) { cell += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { inText = false }; if name == "v" { inValue = false }
        if name == "si" { shared.append(current); inShared = false }
        if name == "c" { inCell = false; if column >= 0 && column < 256 { while row.count <= column { row.append("") }; if kind == "s" { if let i = Int(cell), shared.indices.contains(i) { row[column] = shared[i] } } else { row[column] = cell } } }
        if name == "row" { rows.append(row) }
    }
}
func otpBatch(_ rows: [[String]]) throws -> BankBatch {
    guard let h = rows.firstIndex(where: { $0.count >= 21 && $0[0].contains("Дата та час проведення операції") && $0[20] == "Статус" }) else { throw BankFailure.format }
    var batch = BankBatch()
    for r in rows.dropFirst(h+1) where r.count > 1 && (r[1] == "Поповнення" || r[1] == "Списання") { if let item = otpRow(r) { batch.rows.append(item) } else { batch.rejected += 1 } }
    let debit=rows.first(where:{$0.first?.contains("оборотів по дебету") == true}).flatMap{$0.count>1 ? bankMoneyCell($0[1])?.0:nil}
    let credit=rows.first(where:{$0.first?.contains("оборотів по кредиту") == true}).flatMap{$0.count>1 ? bankMoneyCell($0[1])?.0:nil}
    batch.reconciliation=bankReconcile(batch,debit:debit,credit:credit)
    return batch
}
struct MonoAccount: Codable, Identifiable { var id: String; var currencyCode: Int; var type: String?; var maskedPan: [String]?; var balance: Int64; var creditLimit: Int64? = nil }
struct MonoClient: Codable { var accounts: [MonoAccount] }
struct MonoItem: Codable { var id: String; var time: Int64; var description: String; var mcc: Int; var amount: Int64; var operationAmount: Int64; var currencyCode: Int; var commissionRate: Int64; var hold: Bool? }
func monoRows(_ items: [MonoItem], account: String) -> BankBatch {
    var batch = BankBatch()
    for i in items {
        guard i.hold != true, i.amount != 0, i.amount >= -1_000_000_000_000, i.amount <= 1_000_000_000_000, i.operationAmount >= -1_000_000_000_000, i.operationAmount <= 1_000_000_000_000 else { batch.rejected += 1; continue }
        let code = [980:"UAH",840:"USD",978:"EUR",985:"PLN",826:"GBP"][i.currencyCode] ?? String(i.currencyCode)
        batch.rows.append(BankRow(source:"monobank",date:Date(timeIntervalSince1970:Double(i.time)),signed:i.amount,note:bankRedact(i.description),mcc:i.mcc,original:abs(i.operationAmount),currency:code,fee:i.commissionRate,reference:account+":"+i.id))
    }
    return batch
}
func mccCategory(_ mcc: Int?, incoming: Bool) -> String? {
    guard !incoming, let mcc else { return nil }
    switch mcc { case 5411, 5422, 5441, 5451, 5462, 5499: return "🛒 Продукти"; case 4121: return "🚕 Таксі"; case 4111, 4131: return "🚗 Транспорт"; case 5541, 5542: return "⛽ Паливо"; case 5812, 5814: return "🍽️ Ресторани"; case 5912: return "💊 Здоров’я"; case 4814: return "📱 Зв’язок"; case 4900: return "🧾 Комунальні"; case 5995: return "🐾 Тварини"; default: return nil }
}
func bankNewRows(_ incoming: [BankRow], existing: [String]) -> [BankRow] {
    // For identical statement rows preserve multiplicity, but only import the excess on re-import.
    var counts: [String:Int] = [:]; existing.forEach { counts[$0, default:0] += 1 }
    var seen: [String:Int] = [:]; var result: [BankRow] = []
    for row in incoming { seen[row.key, default:0] += 1; if row.reference != nil && seen[row.key, default:0] > 1 { continue }; if seen[row.key, default:0] > counts[row.key, default:0] { result.append(row) } }
    return result
}

// Classification changes reporting, never the signed movement of funds. Ambiguous transfers stay unclassified.
func bankKind(signed: Int64, note: String, mcc: Int?, operationType: String?, creditAccount: Bool) -> String {
    let n = note.lowercased(), t = (operationType ?? "").lowercased()
    func has(_ words: [String]) -> Bool { words.contains { n.contains($0) || t.contains($0) } }
    let transfer = [4829, 6010, 6011, 6012, 6051, 6536, 6537, 6538, 6540].contains(mcc ?? -1) || has(["переказ", "transfer", "account ", "card*", "поповнення", "зняття готівки", "cash withdrawal"])
    if signed > 0 {
        if has(["повернення покупки", "повернення товару", "refund", "reversal"]) || t == "повернення" { return "refund" }
        if has(["погашення кредиту", "погашення заборгованості", "repayment", "погашення кредитної"]) { return creditAccount ? "creditRepaymentIncoming" : "unclassifiedCredit" }
        if has(["видача кредиту", "отримання кредиту", "кредитні кошти", "loan disbursement"]) { return "creditDraw" }
        if has(["зарплата", "заробітна плата", "salary", "кешбек", "cashback", "виплата винагороди", "нарахування відсотків", "пенсія"]) { return "income" }
        if transfer { return "unclassifiedCredit" }
        return "unclassifiedCredit"
    }
    if has(["погашення кредиту", "погашення заборгованості", "loan repayment"]) { return "creditRepayment" }
    if t.contains("покупка") { return "expense" }
    if transfer { return "unclassifiedDebit" }
    if t.contains("покупка") || mccCategory(mcc,incoming:false) != nil || has(["комісія", "відсотки за кредит", "fee", "uklon", "bolt.eu", "apteka", "thrash", "torba"]) { return "expense" }
    if let mcc, (mcc >= 3000 && mcc < 9000) && ![4829,6010,6011,6012,6051,6536,6537,6538,6540].contains(mcc) { return "expense" }
    return "unclassifiedDebit"
}
