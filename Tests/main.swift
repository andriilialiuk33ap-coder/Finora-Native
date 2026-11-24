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
