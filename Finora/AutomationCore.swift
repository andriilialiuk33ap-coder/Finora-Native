import Foundation

// No SMS body, OTP, card number or bank credential is retained by this feature.
struct CapturedPayment: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var date = Date()
    var account: String
    let currency: String
    let minor: Int64
    let merchant: String
    let source: String
    let incoming: Bool
    let clearPurchase: Bool
    // Optional for decoding events from Preview 4. Contains no raw SMS text.
    var messageFingerprint: String? = nil
    var cardSuffix: String? = nil
    var bankHint: String? = nil
    var ambiguousCard: Bool? = nil
    var reportedAvailable: Int64? = nil
}
enum CaptureError: LocalizedError {
    case invalid, unsafeMessage, ambiguous, storage
    var errorDescription: String? {
        switch self {
        case .invalid: return "Некоректна сума, валюта або код рахунку / Invalid amount, currency or account code."
        case .unsafeMessage: return "Це не платіж або повідомлення містить код безпеки / Not a payment or contains a security code."
        case .ambiguous: return "Не вдалося однозначно визначити суму та валюту. Додайте вручну / Ambiguous amount or currency; add manually."
        case .storage: return "Не вдалося прочитати локальну чергу / Cannot read local inbox."
        }
    }
}
func captureWallet(amount: Double, merchant: String, account: String, currency: String) throws -> CapturedPayment {
    let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ["UAH","USD"].contains(code), amount.isFinite, amount > 0, amount <= 10_000_000_000, let minor = bankMinor(String(amount)), minor > 0 else {throw CaptureError.invalid}
    return CapturedPayment(account:account.trimmingCharacters(in:.whitespacesAndNewlines),currency:code,minor:minor,merchant:String(bankRedact(merchant).prefix(160)),source:"Apple Pay",incoming:false,clearPurchase:true)
}
// Shortcuts may expose the notification title and body separately.
func captureBankNotification(title: String?, body: String, account: String) throws -> CapturedPayment {
    let header = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return try captureMessage(header.isEmpty ? body : header + "\n" + body, account: account)
}
func captureMessage(_ text: String, account: String) throws -> CapturedPayment {
    let account = account.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !account.isEmpty, text.count <= 4000 else {throw CaptureError.invalid}
    let normalized = bankClean(text)
    let lower = normalized.lowercased()
    let securityText = lower.replacingOccurrences(of: "otp bank", with: "банк").replacingOccurrences(of: "otpbank", with: "банк")
    guard !["otp", "одноразов", "код підтвердж", "код авторизац", "verification code", "password", "пароль", "не повідомляйте", "не передавайте", "one-time", "security code", "код для", "код операції", "declined", "відхилен", "неуспіш", "скасован", "відмов", "недостатньо коштів", "failed"].contains(where:{securityText.contains($0)}) else {throw CaptureError.unsafeMessage}
    let purchase = ["покупка","купівля","оплата","purchase","payment","списання","списано","сплачено","paid","debit"].contains{lower.contains($0)}
    let incoming = ["зарахування","зараховано","надходження","поповнення","поповнено","credited","received","refund","повернення"].contains{lower.contains($0)}
    guard purchase != incoming else {throw CaptureError.unsafeMessage}
    // Ignore the available-balance suffix, not the transaction itself. Multiple amounts before it require manual entry.
    let balancePattern = #"(?i)(?:\b(?:balance|available)\b|баланс|залишок|доступно|доступний ліміт|кредитний ліміт)"#
    let payment = normalized.range(of:balancePattern, options:.regularExpression).map{String(normalized[..<$0.lowerBound])} ?? normalized
    let pattern = #"(?i)(?<![\d.,])([+-]?\d+(?:[ ]\d{3})*(?:[.,]\d{1,2})?)\s*(UAH|USD|грн\.?|₴|\$)(?![\p{L}\d])"#
    let regex = try NSRegularExpression(pattern:pattern)
    let matches = regex.matches(in:payment,range:NSRange(payment.startIndex...,in:payment))
    guard matches.count == 1, let match = matches.first, let ar = Range(match.range(at:1),in:payment), let cr = Range(match.range(at:2),in:payment), let minor = bankMinor(String(payment[ar])), minor != 0 else {throw CaptureError.ambiguous}
    let code = String(payment[cr]).uppercased(); let currency = code == "USD" || code == "$" ? "USD":"UAH"
    // Extract only an explicitly labelled merchant, never arbitrary private SMS contents.
    let merchantPattern = #"(?i)(?:merchant|магазин|торговець|продавець)\s*[:=]\s*([^;|]+)"#
    let merchantRegex = try NSRegularExpression(pattern:merchantPattern)
    var merchant = ""
    if let m = merchantRegex.firstMatch(in:payment,range:NSRange(payment.startIndex...,in:payment)), let r = Range(m.range(at:1),in:payment) {
        let candidate = String(payment[r]); if !candidate.contains(where:{$0.isNumber}) {merchant = String(bankRedact(candidate).prefix(160))}
    }
    // PUMB sends title, amount, merchant, date and card metadata as separate lines.
    // Only a bounded merchant segment before an explicit transaction date is accepted.
    let pumbPattern = #"(?i)(?:купівля|покупка)\s+[+-]?\d+(?:[ ]\d{3})*(?:[.,]\d{1,2})?\s*(?:UAH|USD|грн\.?|₴|\$)\s+([^;|]+?)\s+(\d{2}[-.]\d{2}[-.]\d{4}\s+\d{2}:\d{2})(?!\d)"#
    let pumbRegex = try NSRegularExpression(pattern: pumbPattern)
    var transactionDate: Date? = nil
    if let m = pumbRegex.firstMatch(in: payment, range: NSRange(payment.startIndex..., in: payment)),
       let mr = Range(m.range(at: 1), in: payment), let dr = Range(m.range(at: 2), in: payment) {
        let candidate = String(payment[mr])
        if candidate.count <= 160 && candidate.range(of: #"(?i)(?:рахунок|картка|доступно|баланс|\d{6,})"#, options: .regularExpression) == nil {
            if merchant.isEmpty { merchant = bankRedact(candidate) }
            transactionDate = bankDate(String(payment[dr]).replacingOccurrences(of: "-", with: "."))
        }
    }
    if transactionDate == nil, let dateRegex = try? NSRegularExpression(pattern: #"(?<!\d)\d{2}[-.]\d{2}[-.]\d{4}\s+\d{2}:\d{2}(?!\d)"#),
       let m = dateRegex.firstMatch(in: payment, range: NSRange(payment.startIndex..., in: payment)), let r = Range(m.range, in: payment) {
        transactionDate = bankDate(String(payment[r]).replacingOccurrences(of: "-", with: "."))
    }
    // A masked credit-card label does not make a normal purchase a credit repayment.
    let paymentLower = payment.lowercased().replacingOccurrences(of: #"(?:кредитна картка|дебетова картка|картка|рахунок)\s*:\s*[•*… .\d]+"#, with: "", options: .regularExpression)
    guard !incoming || minor > 0 else {throw CaptureError.ambiguous}
    let transfer = ["переказ","transfer","погашення","repayment","готівк","withdrawal","кредит","loan","комісія","fee","авторизація","authorization","hold","заблоковано"].contains{paymentLower.contains($0)}
    let explicitPurchase = ["покупка","купівля","purchase","оплата","сплачено","paid"].contains{paymentLower.contains($0)}
    var event = CapturedPayment(account:account,currency:currency,minor:abs(minor),merchant:merchant,source:"Bank message",incoming:incoming,clearPurchase:purchase && explicitPurchase && !transfer && !merchant.isEmpty)
    if let transactionDate { event.date = transactionDate }
    event.messageFingerprint = captureMessageFingerprint(account:account, text:normalized)
    let masks = finamiCardSuffixes(normalized)
    event.cardSuffix = masks.count == 1 ? masks.first : nil
    event.ambiguousCard = masks.count > 1 ? true : nil
    event.reportedAvailable = finamiReportedAvailable(normalized, currency: currency)
    event.bankHint = finamiBankHint(normalized)
    return event
}
// SHA-256 for a stable, non-reversible duplicate hint. Never store the message body.
// A digest is not a bank-issued transaction ID: identical legitimate payments can exist.
func captureSHA256(_ bytes: [UInt8]) -> String {
    let k: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
    var h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
    func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32-n)) }
    var data = bytes; let bits = UInt64(bytes.count) * 8
    data.append(0x80)
    while data.count % 64 != 56 {data.append(0)}
    for i in (0..<8).reversed() {data.append(UInt8(truncatingIfNeeded:bits >> (i*8)))}
    for offset in stride(from:0,to:data.count,by:64) {
        var w = [UInt32](repeating:0,count:64)
        for i in 0..<16 {let j=offset+i*4;w[i]=(UInt32(data[j])<<24)|(UInt32(data[j+1])<<16)|(UInt32(data[j+2])<<8)|UInt32(data[j+3])}
        for i in 16..<64 {
            let x=w[i-15], y=w[i-2]
            let s0=rotate(x,7)^rotate(x,18)^(x>>3), s1=rotate(y,17)^rotate(y,19)^(y>>10)
            w[i]=w[i-16] &+ s0 &+ w[i-7] &+ s1
        }
        var a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],z=h[7]
        for i in 0..<64 {
            let s1=rotate(e,6)^rotate(e,11)^rotate(e,25), ch=(e&f)^((~e)&g)
            let t1=z &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0=rotate(a,2)^rotate(a,13)^rotate(a,22), maj=(a&b)^(a&c)^(b&c)
            let t2=s0 &+ maj
            z=g;g=f;f=e;e=d &+ t1;d=c;c=b;b=a;a=t1 &+ t2
        }
        for (i,v) in [a,b,c,d,e,f,g,z].enumerated() {h[i] = h[i] &+ v}
    }
    return h.map {String(format:"%08x",$0)}.joined()
}
func captureMessageFingerprint(account: String, text: String) -> String {
    let normalized = bankClean(text).precomposedStringWithCanonicalMapping.lowercased()
    return captureSHA256(Array(("izanami-message-v1|\(account.utf8.count)|\(account)|" + normalized).utf8))
}
// A fingerprint has no expiry: a delayed replay must never auto-post again. The user
// may explicitly save a separate real payment even if the bank sends identical text.
func captureRepeatedMessage(_ event: CapturedPayment, handled: [String]) -> Bool {
    guard let fingerprint = event.messageFingerprint else {return false}
    return handled.contains(fingerprint)
}
func captureRememberMessage(_ event: CapturedPayment, handled: [String]) -> [String] {
    guard let fingerprint = event.messageFingerprint, !handled.contains(fingerprint) else {return handled}
    return handled + [fingerprint]
}
func capturePossibleDuplicate(_ e: CapturedPayment, otherAccount: String, otherCurrency: String, otherAmount: Int64, otherIncoming: Bool, otherDate: Date, otherSource: String?, isBank: Bool) -> Bool {
    guard e.currency == otherCurrency else {return false}
    // Delayed delivery from a different source or posted bank statement gets a wider review window.
    let window: TimeInterval = isBank || (otherSource != nil && otherSource != e.source) ? 36*3600 : 600
    return captureSimilar(account:e.account,amount:e.minor,incoming:e.incoming,date:e.date,otherAccount:otherAccount,otherAmount:otherAmount,otherIncoming:otherIncoming,otherDate:otherDate,window:window)
}
func captureSimilar(account: String, amount: Int64, incoming: Bool, date: Date, otherAccount: String, otherAmount: Int64, otherIncoming: Bool, otherDate: Date, window: TimeInterval = 600) -> Bool {
    account == otherAccount && amount == otherAmount && incoming == otherIncoming && abs(date.timeIntervalSince(otherDate)) <= window
}
// Each intent writes its own atomic file. Only the foreground Store writes Finora.json.
enum CaptureInbox {
    static func folder() throws -> URL {
        let base = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
        let dir = base.appendingPathComponent("IzanamiInbox",isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir
    }
    static func enqueue(_ event: CapturedPayment, in dir: URL) throws {
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try JSONEncoder().encode(event).write(to:dir.appendingPathComponent(event.id+".json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    static func read(in dir: URL) throws -> [CapturedPayment] {
        try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter{$0.pathExtension == "json"}.map { url in
            let event = try JSONDecoder().decode(CapturedPayment.self,from:Data(contentsOf:url))
            guard UUID(uuidString:event.id) != nil, url.lastPathComponent == event.id+".json", event.minor > 0, event.minor <= 1_000_000_000_000 else {throw CaptureError.storage}
            return event
        }.sorted{$0.date < $1.date}
    }
    static func remove(_ event: CapturedPayment, in dir: URL) throws {
        guard UUID(uuidString:event.id) != nil else {throw CaptureError.invalid}
        let url = dir.appendingPathComponent(event.id+".json")
        if FileManager.default.fileExists(atPath:url.path) {try FileManager.default.removeItem(at:url)}
    }
}

// Shared shortcut links must originate from Apple Shortcuts, not a guessed identifier.
func finamiSharedShortcutURL(_ text: String) -> URL? {
    guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          c.scheme?.lowercased() == "https", c.host?.lowercased() == "www.icloud.com",
          c.user == nil, c.password == nil, c.port == nil,
          c.path.range(of: #"^/shortcuts/[0-9a-fA-F]{32}/?$"#, options: .regularExpression) != nil else { return nil }
    return c.url
}

// Only a labelled, masked suffix is accepted. Never keep full card numbers.
func finamiCardSuffixes(_ text: String) -> Set<String> {
    let pattern = #"(?i)(?:картка|картки|карта|рахунок|card|account)\s*:?\s*[*•●xX]{1,}\s*(\d{4})(?!\d)"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let values = Set(re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in Range(m.range(at: 1), in: text).map { String(text[$0]) } })
    return values
}
func finamiCardSuffix(_ text: String) -> String? { let values = finamiCardSuffixes(text); return values.count == 1 ? values.first : nil }
func finamiBankHint(_ text: String) -> String? {
    let lower = text.lowercased()
    let candidates: [(String,[String])] = [("pumb",["пумб","pumb"]),("otp",["отп","otp bank","otpbank"]),("privat",["приват","privat"]),("mono",["monobank","монобанк"]),("abank",["а-банк","a-bank","abank"])]
    let found = candidates.filter { item in item.1.contains { lower.contains($0) } }
    return found.count == 1 ? found[0].0 : nil
}
struct FinamiCaptureAccount {
    let id: String
    let currency: String
    let suffix: String?
    let bank: String?
}
// Explicit account remains the fallback only when metadata does not contradict it.
// An unscoped suffix cannot redirect a payment to a different bank on its own.
func finamiCaptureRoute(_ event: CapturedPayment, accounts: [FinamiCaptureAccount]) -> String? {
    guard event.ambiguousCard != true else { return nil }
    let compatible = accounts.filter { $0.currency == event.currency }
    let explicit = compatible.first { $0.id == event.account }
    guard let suffix = event.cardSuffix else {
        if let bank = event.bankHint, let explicit, explicit.bank != bank { return nil }
        return explicit?.id
    }
    let bank = event.bankHint ?? explicit?.bank
    if let explicit, explicit.suffix == suffix, bank == nil || explicit.bank == bank { return explicit.id }
    guard let bank else { return nil }
    let matches = compatible.filter { $0.suffix == suffix && $0.bank == bank }
    return matches.count == 1 ? matches[0].id : nil
}

struct FinamiBalanceObservation: Codable {
    var accountID: String
    var date: Date
    var available: Int64
    var currency: String
}
// A bank's reported available amount can include credit and authorization holds.
// Save it only as a comparison reference, not as an opening balance or transaction.
func finamiReportedAvailable(_ text: String, currency: String) -> Int64? {
    let pattern = #"(?i)(?:доступно|доступна сума|available)\s*[:=]?\s*([+-]?\d+(?:[ ]\d{3})*(?:[.,]\d{1,2})?)\s*(UAH|USD|грн\.?|₴|\$)(?![\p{L}\d])"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard matches.count == 1, let m = matches.first, let ar = Range(m.range(at: 1), in: text), let cr = Range(m.range(at: 2), in: text) else { return nil }
    let token = String(text[cr]).uppercased(); let code = token == "USD" || token == "$" ? "USD" : "UAH"
    guard code == currency, let n = bankMinor(String(text[ar])), n >= 0 else { return nil }
    return n
}
