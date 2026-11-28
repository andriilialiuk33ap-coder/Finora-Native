#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'struct PersonalReminder: Codable { var id = UUID().uuidString; var linkedID: String? = nil }; struct Database { var operations: [Operation] = []; var paidRecords: [FinamiPaidRecord]? = nil; var obligations: [Obligation] = []; var removedInstallments: [Obligation]? = nil; var reminders: [PersonalReminder]? = nil; var partnerGroups: [FinamiPartnerGroup]? = nil }'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift Finora/Domain/PaymentModels.swift Finora/Domain/FinancialRecords.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition:@autoclosure ()->Bool,_ title:String){precondition(condition(),title);print("PASS: "+title)}
let allowed=["🐾 Тварини","Зоомагазини","Пиво","☕ Кава","🍽️ Ресторани","🛒 Продукти","🚗 Транспорт","🚕 Таксі","💵 Кешбек"]
let rules=["expense:baddi":"Зоомагазини","expense:chill time":"Пиво","expense:dlyasvoyih":"Пиво","expense:okrasa":"☕ Кава"]
func category(_ note:String)->String{finamiIntelligentCategory(note,kind:.expense,allowed:allowed,learned:rules)}
check(category("BADDI VINNITSA UAUA")=="Зоомагазини","confirmed merchant aliases normalized")
check(category("CHILL TIME VINNYTSIA UA")=="Пиво" && category("DlyaSvoYih VINNITSA UAUA")=="Пиво","confirmed beverage category")
check(category("Okrasa VINNITSA UAUA")=="☕ Кава","confirmed coffee category")
check(category("Бадді Вінниця")=="Зоомагазини" && category("Для своїх")=="Пиво","confirmed Cyrillic aliases")
check(category("Clover")=="Без категорії" && category("KIOSK")=="Без категорії","uncertain merchants remain unassigned")
check(category("Smachna pica z soboiu VINNITSA UAUA")=="🍽️ Ресторани" && category("ZOOSALON LIMPOPO")=="🐾 Тварини","additional merchant aliases")
check(finamiMerchantKey("PLATON1*UKLON_V KYIV UAUA")=="uklon" && finamiMerchantKey("BOLT.EU/O/2701011200 Tallinn EEEE")=="bolt","canonical taxi variants")
check(finamiMerchantDisplay("BOLT.EUO2701021300 Tallinn EEEE")=="Bolt","short display keeps raw data untouched")
check(bankKind(signed:100,note:"акції Нагороди з ПУМБ",mcc:nil,operationType:"Надходження",creditAccount:true)=="income","positive bank reward identified")
check(bankKind(signed:100,note:"ACCOUNT TO ACCOUNT",mcc:nil,operationType:"Надходження",creditAccount:true)=="unclassifiedCredit","unidentified transfer not income")
check(bankStatementLastFour("Номер картки: 1234 **** **** 9876\nВиписка")=="9876","masked statement card header")
check(bankStatementLastFour("Номер картки: 1234 **** **** 9876\nКартка: **** **** **** 4567")==nil,"ambiguous cards are not auto-routed")
check(bankStatementLastFour("Надходження TO CARD*1234")==nil,"counterparty card not statement owner")
check(bankCanonicalName("Пумб")==bankCanonicalName("PUMB"),"bank spelling canonical")
let a=Account(id:"a",name:"Example"), b=Account(id:"b",name:"Other")
let date=Date(timeIntervalSince1970:1800000000)
let debit=Operation(id:"d",kind:.unclassifiedDebit,amount:500,date:date,category:"Без категорії",note:"ACCOUNT TO ACCOUNT",account:a.id)
let credit=Operation(id:"c",kind:.unclassifiedCredit,amount:500,date:date,category:"Без категорії",note:"ACCOUNT TO ACCOUNT",account:a.id)
check(finamiAuditIssues(operations:[debit,credit],accounts:[a,b],records:[]).count==1,"same-account opposite legs flagged")
var other=credit;other.account=b.id
check(finamiAuditIssues(operations:[debit,other],accounts:[a,b],records:[]).first?.title=="Можливий внутрішній переказ","cross-account possible transfer flagged")
var k1=debit,k2=other;k1.bankKey="key";k2.bankKey="key"
check(finamiAuditIssues(operations:[k1,k2],accounts:[a,b],records:[]).count==2,"duplicate bank keys reported without mutation")
let pair=finamiTransferFromPair(k1,k2,accounts:[a,b],records:[])
check(pair==nil,"same bank key cannot be merged")
k2.bankKey="other-key"
let transfer=finamiTransferFromPair(k1,k2,accounts:[a,b],records:[])
check(transfer?.destination==b.id && transfer?.destinationBankKey=="other-key","safe transfer retains both statement keys")
check(FinamiLedgerIndex(operations:[k1,k2]).balance(a)==FinamiLedgerIndex(operations:[transfer!]).balance(a) && FinamiLedgerIndex(operations:[k1,k2]).balance(b)==FinamiLedgerIndex(operations:[transfer!]).balance(b),"merged transfer preserves both balances")
let historical=Obligation(kind:.installment,name:"Sample",target:1000,paid:500,monthly:500,due:Date())
var oldDebit=k1;oldDebit.date=Date().addingTimeInterval(-86400)
let historic=finamiHistoricalPaymentRecord(obligation:historical,operation:oldDebit,accounts:[a,b],records:[])
check(historic?.historicalOnly==true && historical.remaining==500,"historical link does not apply principal again")
check(finamiHistoricalPaymentRecord(obligation:historical,operation:oldDebit,accounts:[a,b],records:[historic!])==nil,"historical operation cannot be linked twice")
let group=finamiCategoryGroups(operations:[Operation(kind:.expense,amount:1,category:"Без категорії",note:"Baddi VINNITSA UAUA"),Operation(kind:.expense,amount:2,category:"Без категорії",note:"BADDI UA"),Operation(kind:.expense,amount:3,category:"Інша категорія",note:"BADDI")],expense:allowed,income:[],learned:rules)
check(group.count==1 && group[0].ids.count==2 && group[0].suggestion=="Зоомагазини","bulk review groups unknown records only")
var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(secondsFromGMT:0)!
let start=cal.date(from:.init(year:2027,month:1,day:4))!,end=cal.date(from:.init(year:2027,month:5,day:1))!
let plan=finamiPlannedOccurrences(id:"sample",start:start,amount:700,remaining:2500,subsequentAmount:1000,component:.month,step:1,interval:.init(start:start,end:end),calendar:cal)
check(plan.map(\.amount)==[700,1000,800],"calendar future payments use normal amount after partial")
check(finamiScheduledAmounts(start:start,amount:700,remaining:2500,subsequentAmount:1000,component:.month,step:1,from:start,until:end,calendar:cal)==[700,1000,800],"forecast agrees with calendar")
var loan=Obligation(kind:.installment,name:"Sample",target:3000,paid:0,monthly:1000,due:start)
check(finamiApplyInstallment(&loan,scheduled:start,amount:300,calendar:cal) && loan.nextCharge==700 && loan.due==start,"partial installment retains due date")
let saved=try JSONEncoder().encode(loan);let decoded=try JSONDecoder().decode(Obligation.self,from:saved)
check(decoded.currentDuePaid==300 && decoded.nextCharge==700,"partial progress persists")
check(finamiApplyInstallment(&loan,scheduled:start,amount:1200,calendar:cal) && loan.nextCharge==1000 && loan.remaining==1500 && loan.due>start,"early repayment reduces remaining; next scheduled amount restored")
check(!finamiApplyInstallment(&loan,scheduled:loan.due,amount:1501,calendar:cal),"overpayment rejected")
check(finamiCSVText(" =1+1").contains("'"),"CSV formula injection neutralized")
let sheets=[FinamiExportSheet(name:"Підсумок",rows:[[.init("Дата"),.init("Сума")],[.init("<тест>&\""),.init(minor:12345)],[.init("=1+1"),.init(minor:-12)]]),FinamiExportSheet(name:"Операції",rows:[[.init("Приклад")],[.init("Українська")]])]
let parts=finamiWorkbookParts(sheets)
check(parts.count==6 && parts["[Content_Types].xml"] != nil && parts["_rels/.rels"] != nil,"OOXML mandatory parts")
let xml=String(data:parts["xl/worksheets/sheet1.xml"]!,encoding:.utf8)!
check(xml.contains("123.45") && xml.contains("&lt;тест&gt;&amp;&quot;") && xml.contains("=1+1") && !xml.contains("<f>"),"typed numbers, escaped XML, formula-like text remains text")
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
for (path,data) in parts {let url=root.appendingPathComponent(path);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url)}
let ics=finamiCalendarData([.init(id:"event",date:start,title:"Тест; "+String(repeating:"п",count:90),detail:"A,B\nC")],now:start,calendar:cal)
let calendar=String(data:ics,encoding:.utf8)!
check(calendar.contains("DTSTART;VALUE=DATE:20270104") && calendar.contains("DESCRIPTION:A\\,B\\nC") && calendar.components(separatedBy:"\r\n").allSatisfy{$0.utf8.count<=75},"ICS date, escaping and UTF-8 folding")
// Optional local-only audit of a user backup; no raw records or identifiers printed.
if CommandLine.arguments.count>2 {
    struct Sample:Decodable {var operations:[Operation];var accounts:[Account];var obligations:[Obligation];var paidRecords:[FinamiPaidRecord]?}
    let db=try JSONDecoder().decode(Sample.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
    let findings=finamiAuditIssues(operations:db.operations,accounts:db.accounts,records:db.paidRecords ?? [])
    let categories=finamiCategoryGroups(operations:db.operations,expense:allowed,income:allowed,learned:rules)
    print("LOCAL BACKUP: decoded \(db.operations.count) operations; \(findings.count) audit groups; \(categories.filter{$0.suggestion != "Без категорії"}.reduce(0){$0+$1.ids.count}) proposed assignments in limited test dictionary")
}
SWIFT
swiftc -warnings-as-errors "$tmp/Models.swift" Finora/MoneyCore.swift Finora/FinamiScanCore.swift Finora/BankCore.swift Finora/FinamiCore.swift Finora/FinamiIntelligenceCore.swift Finora/FinamiPaymentCore.swift Finora/FinamiAuditCore.swift Finora/FinamiExportCore.swift "$tmp/main.swift" -o "$tmp/test"
# The payment core refers to Database; lightweight model provided below in generated models.
"$tmp/test" "$tmp/workbook" "$@"
python3 - "$tmp/workbook" <<'PY'
import sys, pathlib, zipfile, xml.etree.ElementTree as ET
folder=pathlib.Path(sys.argv[1]); archive=folder.parent/'test.xlsx'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in folder.rglob('*'):
        if p.is_file(): z.write(p,p.relative_to(folder).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name in z.namelist(): ET.fromstring(z.read(name))
print('PASS: generated OOXML ZIP and XML parsed')
try:
    from openpyxl import load_workbook
except ImportError:
    print('SKIP: optional openpyxl reader unavailable')
else:
    book=load_workbook(archive,data_only=False)
    assert book['Підсумок']['B2'].value==123.45 and book['Підсумок']['A3'].data_type=='s' and book['Операції']['A2'].value=='Українська'
    print('PASS: actual XLSX opened by openpyxl, numeric and text cells')
PY
