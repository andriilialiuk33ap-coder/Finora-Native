#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then echo 'SKIP: CryptoKit/CommonCrypto test requires macOS'; exit 0; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let plain = Data("test financial database".utf8)
let password = "a-test-password-only"
let first = try FinamiBackupCrypto.seal(plain, password: password)
let second = try FinamiBackupCrypto.seal(plain, password: password)
precondition(first != second)
let restored = try FinamiBackupCrypto.open(first, password: password)
precondition(restored == plain)
print("PASS: encrypted backup round-trip, fresh salt and nonce")
do { _ = try FinamiBackupCrypto.open(first, password: "incorrect"); fatalError("wrong password accepted") } catch { print("PASS: incorrect password rejected") }
var envelope = try JSONSerialization.jsonObject(with: first) as! [String: Any]
var sealed = Data(base64Encoded: envelope["sealed"] as! String)!
sealed[sealed.count-1] ^= 1
envelope["sealed"] = sealed.base64EncodedString()
let corrupted = try JSONSerialization.data(withJSONObject: envelope)
do { _ = try FinamiBackupCrypto.open(corrupted, password: password); fatalError("tampering accepted") } catch { print("PASS: tampered ciphertext rejected") }
SWIFT
swiftc Finora/FinamiBackupCrypto.swift "$tmp/main.swift" -o "$tmp/check-encryption"
"$tmp/check-encryption"
