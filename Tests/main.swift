import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { if !condition() { fatalError(label) }; print("PASS: \(label)") }
check(bankMinor("-1 499,85") == -149985,"signed decimal")
check(bankMinor("1,005") == 101,"decimal rounding")
check(bankMinor("NaN") == nil && bankMinor("1,2.3") == nil,"invalid amount")
check(bankDate("2026-02-30 12:00") == nil,"invalid date")
let sample = pumbRow(["2026-11-01 14:09:19","130.00 UAH","132.00 UAH","2.00 UAH","","TEST Uklon","Покупка"])!
check(sample.signed == -13200 && sample.original == 13000 && sample.fee == 200 && sample.warning != nil,"PUMB account amount and fee")
let a = abankRow(["01.06.2026 14:01","","Example","5411","-1 499,85","-1 485,00","UAH","-","14,85"])!
check(a.signed == -149985 && a.fee == 1485,"A-BANK fee not counted twice")
check(mccCategory(a.mcc,incoming:false) == "🛒 Продукти","MCC classification")
check(bankNewRows([sample,sample],existing:[]).count == 2,"identical legitimate rows retained")
check(bankNewRows([sample,sample],existing:[sample.key]).count == 1,"partial reimport")
check(bankNewRows([sample,sample],existing:[sample.key,sample.key]).isEmpty,"reimport duplicate protection")
let mono = MonoItem(id:"sample",time:1_700_000_000,description:"test",mcc:5411,amount:-10000,operationAmount:250,currencyCode:840,commissionRate:100,hold:false)
var held=mono;held.hold=true
let m=monoRows([mono,held],account:"test")
check(m.rows.count == 1 && m.rejected == 1 && m.rows[0].currency == "USD","mono original currency and held exclusion")
check(bankNewRows([m.rows[0],m.rows[0]],existing:[]).count == 1,"mono id duplicate protection")
let strings = BankXML(shared:true);try strings.parse(Data("<sst><si><t>test</t></si><si><r><t>ab</t></r><r><t>cd</t></r></si></sst>".utf8));check(strings.shared == ["test","abcd"],"XLSX shared strings")
let sheet=BankXML(shared:false,strings:strings.shared);try sheet.parse(Data("<worksheet><sheetData><row><c r=\"A1\" t=\"s\"><v>1</v></c><c r=\"C1\"><v>23</v></c></row></sheetData></worksheet>".utf8));check(sheet.rows == [["abcd","","23"]],"XLSX sparse columns")
if CommandLine.arguments.count > 1 {
    let dir = URL(fileURLWithPath:CommandLine.arguments[1]);let decoder=JSONDecoder()
    for (name,parser) in [("pumb.json",pumbRow),("abank.json",abankRow)] {
        let cells=try decoder.decode([[String]].self,from:Data(contentsOf:dir.appendingPathComponent(name)));let rows=cells.compactMap(parser)
        print("FIXTURE \(name): \(rows.count)/\(cells.count) parsed; debit \(rows.filter{$0.signed<0}.reduce(0){$0+$1.signed}); credit \(rows.filter{$0.signed>0}.reduce(0){$0+$1.signed})")
        for (i,c) in cells.enumerated() where parser(c) == nil {print("Rejected anchor \(i+1); populated columns \(c.map{!$0.isEmpty})")}
        check(rows.count == cells.count,"all extracted \(name) rows parse")
    }
    let shared=BankXML(shared:true);try shared.parse(Data(contentsOf:dir.appendingPathComponent("sharedStrings.xml")))
    let xml=BankXML(shared:false,strings:shared.shared);try xml.parse(Data(contentsOf:dir.appendingPathComponent("sheet1.xml")));let otp=try otpBatch(xml.rows)
    print("FIXTURE OTP: \(otp.rows.count) parsed, \(otp.rejected) rejected")
    check(otp.rows.count == 10 && otp.rejected == 0,"OTP real XLSX rows")
}
let rate=fxRate("42,35")!
check(fxMinor(10000,rate:rate)==423500,"USD historical UAH conversion")
check(fxMinor(423500,rate:rate,divide:true)==10000,"UAH to USD transfer")
check(fxMinor(-10000,rate:rate)==(-423500),"negative native balance")
check(fxRate("0")==nil && fxRate("NaN")==nil && fxRate("-5")==nil,"invalid FX rates")
check(fxMinor(1_000_000_000_000,rate:rate)==nil,"FX amount limit")
check(bankMCC("nan")==nil && bankMCC("5411.0")==5411,"MCC invalid numeric safety")
check(bankSummary("Всього списань за період 1 234.56",label:"Всього списань за період")==123456,"PUMB summary parsing")
check(bankSummary("Сума витрат за період: 2 345,67 UAH",label:"Сума витрат за період")==234567,"A-BANK summary parsing")
check(bankReconcile(BankBatch(rows:[sample]),debit:13200,credit:0).hasPrefix("Суми"),"statement reconciliation match")
check(bankReconcile(BankBatch(rows:[sample]),debit:13000,credit:0).hasPrefix("Увага"),"statement mismatch warning")
// Credit limits represent borrowing capacity, not an asset or income.
let emptyCredit = CardPosition(net:0,limit:3_000_000)
check(emptyCredit.own == 0 && emptyCredit.used == 0 && emptyCredit.available == 3_000_000,"unused limit is not own money")
let purchase = CardPosition(net:-500_000,limit:3_000_000)
check(purchase.used == 500_000 && purchase.unused == 2_500_000 && purchase.own == 0,"credit-funded purchase")
let repaid = CardPosition(net:-300_000,limit:3_000_000)
check(repaid.used == 300_000 && repaid.available == 2_700_000,"partial repayment")
check(CardPosition(net:-3_100_000,limit:3_000_000).available == 0,"over-limit borrowing")
check(CardPosition(net:100_000,limit:3_000_000).available == 3_100_000,"own money plus unused credit")
check(CardPosition.netFrom(own:0,used:300_000) == -300_000 && CardPosition.netFrom(own:100,used:200) == nil,"opening card components validation")
check(bankKind(signed:100000,note:"Переказ ACCOUNT",mcc:nil,operationType:"Надходження",creditAccount:true) == "unclassifiedCredit","PUMB ambiguous incoming is not income")
check(bankKind(signed:-100000,note:"Shop",mcc:nil,operationType:"Покупка",creditAccount:true) == "expense","PUMB purchase remains expense")
check(bankKind(signed:100000,note:"Погашення кредиту",mcc:nil,operationType:nil,creditAccount:true) == "creditRepaymentIncoming","incoming repayment neutral")
check(bankKind(signed:-100000,note:"Погашення кредиту",mcc:nil,operationType:nil,creditAccount:false) == "creditRepayment","outgoing repayment neutral")
check(bankKind(signed:100000,note:"Видача кредиту",mcc:nil,operationType:nil,creditAccount:false) == "creditDraw","loan draw neutral")
check(bankKind(signed:100000,note:"Повернення товару",mcc:nil,operationType:nil,creditAccount:true) == "refund","purchase refund")
check(bankKind(signed:100000,note:"Заробітна плата",mcc:nil,operationType:nil,creditAccount:false) == "income","explicit salary")
check(bankKind(signed:-100000,note:"ATM",mcc:6011,operationType:nil,creditAccount:true) == "unclassifiedDebit","cash withdrawal is not automatically expense")
check(bankKind(signed:100000,note:"Unknown",mcc:nil,operationType:nil,creditAccount:false) == "unclassifiedCredit","unknown incoming even on debit card")
// Automation inputs and local inbox, using invented payment data only.
func rejects(_ label:String,_ action:() throws -> Void) {do {try action();check(false,label)} catch {check(true,label)}}
let wallet=try captureWallet(amount:125.5,merchant:"ATБ",account:"card-a",currency:"UAH")
check(wallet.minor==12550 && wallet.clearPurchase && !wallet.incoming && wallet.source=="Apple Pay","Wallet minor units and source")
rejects("Wallet invalid negative amount"){_ = try captureWallet(amount:-2,merchant:"Shop",account:"a",currency:"UAH")}
rejects("Wallet unsupported currency"){_ = try captureWallet(amount:2,merchant:"Shop",account:"a",currency:"EUR")}
rejects("Wallet nonfinite amount"){_ = try captureWallet(amount:.infinity,merchant:"Shop",account:"a",currency:"UAH")}
rejects("Wallet missing account"){_ = try captureWallet(amount:2,merchant:"Shop",account:" ",currency:"UAH")}
let msg=try captureMessage("Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH",account:"card-a")
check(msg.minor==12550 && msg.merchant=="ATБ" && msg.clearPurchase && !msg.incoming,"SMS amount, merchant and ignore balance")
let credit=try captureMessage("Поповнення 1000 грн; Баланс 3000 грн",account:"card-a")
check(credit.incoming && !credit.clearPurchase && credit.minor==100000,"credit SMS not automatically income")
let repay=try captureMessage("Оплата погашення кредиту 100 грн; доступно 200 грн",account:"card-a")
check(!repay.clearPurchase,"repayment not automatic expense")
let usdMsg=try captureMessage("Purchase 12.34 USD; Merchant: Cafe; Balance 500 USD",account:"usd-a")
check(usdMsg.currency=="USD" && usdMsg.minor==1234,"USD message")
rejects("OTP rejected"){_ = try captureMessage("Код підтвердження оплати 50 грн 123456",account:"a")}
rejects("declined payment rejected"){_ = try captureMessage("Оплата 100 грн відхилена",account:"a")}
rejects("multiple amounts rejected"){_ = try captureMessage("Оплата 100 грн / 2 USD",account:"a")}
rejects("missing currency rejected"){_ = try captureMessage("Оплата 100",account:"a")}
rejects("balance-only rejected"){_ = try captureMessage("Баланс 100 грн",account:"a")}
rejects("contradictory incoming sign rejected"){_ = try captureMessage("Поповнення -100 грн",account:"a")}
check(captureSimilar(account:wallet.account,amount:wallet.minor,incoming:false,date:wallet.date,otherAccount:msg.account,otherAmount:msg.minor,otherIncoming:false,otherDate:wallet.date.addingTimeInterval(100)),"same account/amount/time possible duplicate")
check(!captureSimilar(account:wallet.account,amount:wallet.minor,incoming:false,date:wallet.date,otherAccount:"other",otherAmount:msg.minor,otherIncoming:false,otherDate:wallet.date),"different card not matched")
check(!captureSimilar(account:wallet.account,amount:wallet.minor,incoming:false,date:wallet.date,otherAccount:msg.account,otherAmount:msg.minor,otherIncoming:true,otherDate:wallet.date),"different direction not matched")
let inboxTestDir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
try CaptureInbox.enqueue(wallet,in:inboxTestDir);try CaptureInbox.enqueue(msg,in:inboxTestDir)
let storedEvents=try CaptureInbox.read(in:inboxTestDir)
check(Set(storedEvents.map(\.id))==Set([wallet.id,msg.id]),"two distinct events stored without overwriting")
try CaptureInbox.remove(wallet,in:inboxTestDir);try CaptureInbox.remove(wallet,in:inboxTestDir)
let remainingEvents=try CaptureInbox.read(in:inboxTestDir)
check(remainingEvents==[msg],"idempotent queue cleanup")
try FileManager.default.removeItem(at:inboxTestDir)
// Replay detection: repeat notifications have fresh UUIDs but identical account-scoped fingerprints.
check(captureSHA256([])=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","SHA256 empty vector")
check(captureSHA256(Array("abc".utf8))=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","SHA256 abc vector")
check(captureSHA256(Array(String(repeating:"a",count:1000).utf8))=="41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3","SHA256 multiple blocks")
var replay=try captureMessage("  оплата 125,50 UAH;   магазин: ATБ; баланс 1000 UAH  ",account:"card-a")
replay.date=msg.date.addingTimeInterval(86400*20)
check(replay.id != msg.id && replay.messageFingerprint==msg.messageFingerprint,"repeat SMS same fingerprint despite fresh UUID and whitespace/case")
let handledFingerprints=captureRememberMessage(msg,handled:[])
check(captureRepeatedMessage(replay,handled:handledFingerprints),"delayed replay blocked from auto-posting")
check(captureRememberMessage(replay,handled:handledFingerprints)==handledFingerprints,"duplicate ledger idempotent")
let otherCard=try captureMessage("Оплата 125,50 UAH; Магазин: ATБ; Баланс 1000 UAH",account:"card-b")
check(!captureRepeatedMessage(otherCard,handled:handledFingerprints),"same text on another card not exact repeat")
let differentPurchase=try captureMessage("Оплата 125,50 UAH; Магазин: ATБ; Баланс 874,50 UAH",account:"card-a")
check(!captureRepeatedMessage(differentPurchase,handled:handledFingerprints),"same amount with different message not exact repeat")
let restoredFingerprints=try JSONDecoder().decode([String].self,from:JSONEncoder().encode(handledFingerprints))
check(captureRepeatedMessage(replay,handled:restoredFingerprints),"repeat ledger survives restart or backup")
let replayCopy=try JSONDecoder().decode(CapturedPayment.self,from:JSONEncoder().encode(replay))
check(replayCopy.messageFingerprint==msg.messageFingerprint,"queue fingerprint survives serialization")
var oldEvent=try JSONSerialization.jsonObject(with:JSONEncoder().encode(msg)) as! [String:Any]
oldEvent.removeValue(forKey:"messageFingerprint")
let oldCapture=try JSONDecoder().decode(CapturedPayment.self,from:JSONSerialization.data(withJSONObject:oldEvent))
check(oldCapture.messageFingerprint==nil && !captureRepeatedMessage(oldCapture,handled:handledFingerprints),"old queue remains readable")
check(capturePossibleDuplicate(msg,otherAccount:msg.account,otherCurrency:"UAH",otherAmount:msg.minor,otherIncoming:false,otherDate:msg.date.addingTimeInterval(-86400),otherSource:"Apple Pay",isBank:false),"late cross-source duplicate sent to review")
check(!capturePossibleDuplicate(msg,otherAccount:msg.account,otherCurrency:"USD",otherAmount:msg.minor,otherIncoming:false,otherDate:msg.date,otherSource:"Apple Pay",isBank:false),"different currency not matched")
check(capturePossibleDuplicate(msg,otherAccount:msg.account,otherCurrency:"UAH",otherAmount:msg.minor,otherIncoming:false,otherDate:msg.date.addingTimeInterval(-180),otherSource:"Bank message",isBank:false),"nearby separate purchases require review rather than deletion")
check(!capturePossibleDuplicate(msg,otherAccount:msg.account,otherCurrency:"UAH",otherAmount:msg.minor,otherIncoming:false,otherDate:msg.date.addingTimeInterval(-86400),otherSource:"Bank message",isBank:false),"different day same source not matched by amount alone")
check(capturePossibleDuplicate(msg,otherAccount:msg.account,otherCurrency:"UAH",otherAmount:msg.minor,otherIncoming:false,otherDate:msg.date.addingTimeInterval(-86400),otherSource:nil,isBank:true),"posted statement match sent to review")

let walletAlias = finamiWalletAliasKey(" Test   Card 1234 ")!
check(walletAlias == finamiWalletAliasKey("test card 1234"),"Wallet alias normalization")
check(finamiWalletAliasKey("1234 5678 9012 3456") == nil,"Wallet full card number rejected")
var aliasPayment = try captureWallet(amount: 503.20, merchant: "Test Shop", account: walletAlias, currency: "UAH")
check(finamiWalletAccount(aliasPayment, bindings: [walletAlias:"card-a"]).account == "card-a","Wallet alias explicit routing")
check(finamiWalletAccount(aliasPayment, bindings: [:]).account.isEmpty,"Wallet unknown alias requires review")
aliasPayment.account = "card-a"
check(finamiCaptureAccountConflict(aliasPayment, otherAccount: "card-b", otherCurrency: "UAH", otherAmount: 50320, otherIncoming: false, otherDate: aliasPayment.date, otherSource: "Bank message", otherMerchant: "Test Shop VINNITSA UA"),"Wallet bank cross-account conflict requires review")
check(!finamiCaptureAccountConflict(aliasPayment, otherAccount: "card-b", otherCurrency: "UAH", otherAmount: 50320, otherIncoming: false, otherDate: aliasPayment.date, otherSource: "Bank message", otherMerchant: "Other Shop"),"Different merchant not cross-account conflict")
