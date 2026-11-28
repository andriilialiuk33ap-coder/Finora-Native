#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; cat Finora/Domain/Ledger/LedgerModels.swift Finora/Domain/Ledger/LedgerIndex.swift; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(),label); print("PASS: " + label) }
let outgoing = FinamiOperationChoice.options(bankIncoming:false,current:.expense)
let incoming = FinamiOperationChoice.options(bankIncoming:true,current:.reviewCredit)
let manual = FinamiOperationChoice.options(bankIncoming:nil,current:.expense)
check(outgoing == [.expense,.transfer,.withdrawal,.repayment,.reviewDebit],"simplified outgoing choices")
check(incoming == [.income,.receipt,.transfer,.refund,.reviewCredit],"one income choice; review stays distinct")
check(manual.filter{$0 == .transfer}.count == 1 && !manual.contains(.legacy),"one transfer; no new credit draw/top-up")
check(FinamiOperationChoice.options(bankIncoming:true,current:.legacy).contains(.legacy),"legacy credit type remains editable without coercion")
check(FinamiOperationChoice.legacy.ledgerKind(bankIncoming:true,existing:.creditDraw) == .creditDraw && FinamiOperationChoice.legacy.ledgerKind(bankIncoming:true,existing:.creditRepaymentIncoming) == .creditRepaymentIncoming,"existing credit classifications preserved")
check(FinamiOperationChoice.transfer.ledgerKind(bankIncoming:true,existing:.unclassifiedCredit) == .movementIn && FinamiOperationChoice.transfer.ledgerKind(bankIncoming:false,existing:.expense) == .movementOut,"imported transfer keeps original direction")
check(FinamiOperationChoice.transfer.ledgerKind(bankIncoming:nil,existing:.expense) == .transfer,"manual transfer keeps two-sided accounting")
let a = Account(id:"bank",name:"Bank",opening:10000)
let b = Account(id:"cash",name:"Cash",opening:0)
let withdrawal = Operation(kind:FinamiOperationChoice.withdrawal.ledgerKind(bankIncoming:nil,existing:.expense),amount:2000,account:a.id,destination:b.id,cashWithdrawal:true)
let index = FinamiLedgerIndex(operations:[withdrawal],accounts:[a,b])
check(index.balance(a)==8000 && index.balance(b)==2000 && withdrawal.expenseValue==0,"manual withdrawal moves funds without expense")
let bankWithdrawal = Operation(kind:FinamiOperationChoice.withdrawal.ledgerKind(bankIncoming:false,existing:.expense),amount:2000,account:a.id,cashWithdrawal:true)
let imported = FinamiLedgerIndex(operations:[bankWithdrawal],accounts:[a,b])
check(imported.balance(a)==8000 && imported.balance(b)==0 && bankWithdrawal.expenseValue==0,"bank withdrawal remains one-sided; no invented cash credit")
let restored = try JSONDecoder().decode(Operation.self,from:JSONEncoder().encode(withdrawal))
check(restored == withdrawal && restored.displayKindTitle == "Зняття готівки","withdrawal label persists")
let old = try JSONDecoder().decode(Operation.self,from:Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8))
check(old.cashWithdrawal == nil && old.kind == .expense,"old JSON remains readable")
let income = Operation(kind:.income,amount:5000,category:"💼 Зарплата",account:a.id)
check(income.kind == .income && income.category == "💼 Зарплата" && income.signedNative==5000,"salary remains a category of income")
SWIFT
swiftc -swift-version 5 -warnings-as-errors "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
