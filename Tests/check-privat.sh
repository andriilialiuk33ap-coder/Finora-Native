#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ b:@autoclosure ()->Bool,_ label:String){precondition(b(),label);print("PASS: "+label)}
let iban="UA"+String(repeating:"1",count:27)
let header="ПриватБанк Виписка по картці Інформація по картці: 111111******2222 Рахунок IBAN: \(iban) Валюта рахунку: UAH Баланс на початок періоду: -100,00 Баланс на кінець періоду: 25,00 Усього витрат: -25,00 Усього надходжень: 150,00"
func line(_ y:Double,_ text:String)->FinamiPrivatLine{.init(y:y,text:text)}
func cells(y:Double,date:String,time:String,original:String,code:String,signed:String,fee:String,balance:String,description:[String])->[[FinamiPrivatLine]] {
    let descStart=y+4-Double(description.count-1)*4
    return [[line(y,date),line(y+8,time)],description.enumerated().map{line(descStart+Double($0.offset)*8,$0.element)},[line(y,original),line(y+8,code)],[line(y+4,signed)],[line(y+4,fee)],[line(y+4,"0,00")],[line(y+4,balance)]]
}
let newer=cells(y:300,date:"02.01.2026",time:"14:32",original:"-0,50",code:"USD",signed:"-25,00",fee:"1,00",balance:"25,00",description:["Таксі, тестова країна", "отримувач TEST TAXI, банк", "Коментар до платежу: -"])
let older=cells(y:360,date:"01.01.2026",time:"10:00",original:"150,00",code:"UAH",signed:"150,00",fee:"0,00",balance:"50,00",description:["Зарахування переказу,"])
let page=FinamiPrivatPage(columns:zip(newer,older).map{$0.0+$0.1})
let batch=try privatStatementBatch(header:header,pages:[page])
check(batch.rows.count==2 && batch.opening == -10000 && batch.closing==2500,"Privat reverse order and exact running balances")
check(batch.statementIBAN==iban && batch.statementLastFour=="2222","Privat labelled account identity")
check(batch.rows[1].signed == -2500 && batch.rows[1].original==50 && batch.rows[1].currency=="USD" && batch.rows[1].fee==100,"native amount and original currency preserved; embedded fee not deducted again")
check(batch.rows[1].note=="TEST TAXI" && batch.rows[1].categoryHint=="🚕 Таксі","bank category and redacted merchant extracted")
check(bankKind(signed:batch.rows[0].signed,note:batch.rows[0].note,mcc:nil,operationType:batch.rows[0].operationType,creditAccount:true)=="unclassifiedCredit","transfer credit is not salary")
check(bankNewRows(batch.rows,existing:batch.rows.map(\.key)).isEmpty,"Privat repeat import exact keys")
var broken=page.columns;broken[6][0]=line(304,"24,99")
check((try? privatStatementBatch(header:header,pages:[.init(columns:broken)]))==nil,"misaligned balance rejects entire statement")
check((try? privatStatementBatch(header:header,pages:[.init(columns:newer)]))==nil,"missing page rejects entire statement")
check((try? privatStatementBatch(header:header.replacingOccurrences(of:"UAH Баланс",with:"EUR Баланс"),pages:[page]))==nil,"unsupported account currency rejected")
check(bankCanonicalName("Приват24")==bankCanonicalName("ПриватБанк"),"Privat bank aliases")
let repayment=cells(y:300,date:"02.01.2026",time:"14:32",original:"-25,00",code:"UAH",signed:"-25,00",fee:"0,00",balance:"25,00",description:["Часткове дострокове", "погашення з Оплати частинами"])
let loan=privatParsePage(.init(columns:repayment),mask:"2222").rows.first!.row
check(loan.operationType=="Погашення кредиту","installment repayment not ordinary purchase")
SWIFT
swiftc -swift-version 5 Finora/BankCore.swift Finora/FinamiPrivatStatement.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
