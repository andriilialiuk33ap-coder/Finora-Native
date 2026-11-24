#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; echo 'let cash="cash"'; sed -n '/^enum Kind:/,/^enum ObligationKind:/p' Finora/Finora.swift | sed '$d'; } > "$tmp/Models.swift"
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let oldAccount = Data(#"{"id":"cash","name":"Cash","opening":10000}"#.utf8)
let oldOperation = Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8)
let a=try JSONDecoder().decode(Account.self,from:oldAccount)
let o=try JSONDecoder().decode(Operation.self,from:oldOperation)
precondition(a.code=="UAH" && a.opening==10000 && o.amount==1234 && o.sourceMinor==nil && o.bankKey==nil)
var newer=o;newer.sourceMinor=100;newer.originalAmount=100;newer.originalCurrency="USD";newer.entryCurrency="USD";newer.exchangeRate="42.35"
let copy=try JSONDecoder().decode(Operation.self,from:JSONEncoder().encode(newer))
precondition(copy.sourceMinor==100 && copy.exchangeRate=="42.35")
print("PASS: legacy Account/Operation decode; new currency data roundtrip")
SWIFT
swiftc "$tmp/Models.swift" "$tmp/main.swift" -o "$tmp/model-test"
"$tmp/model-test"
