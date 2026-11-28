import Foundation
import XCTest
@testable import FinamiLedger

final class LedgerTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    func testLegacyOperationDecoding() throws {
        let bytes = Data(#"{"id":"old","kind":"expense","amount":1234,"date":0,"category":"test","note":"test","account":"cash","destination":""}"#.utf8)
        let operation = try JSONDecoder().decode(Operation.self, from: bytes)
        XCTAssertEqual(operation.signedNative, -1234)
        XCTAssertNil(operation.receiptTreatment)
        XCTAssertNil(operation.sourceMinor)
        XCTAssertEqual(try JSONDecoder().decode(Operation.self, from: JSONEncoder().encode(operation)), operation)
    }

    func testLegacyAccountDecoding() throws {
        let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":"cash","name":"Cash","opening":10000}"#.utf8))
        XCTAssertEqual(account.code, "UAH")
        XCTAssertEqual(account.limit, 0)
        XCTAssertEqual(FinamiLedgerIndex(operations: []).balance(account), 10000)
    }

    func testTransferUsesNativeAmountsAndBothHistories() {
        let a = Account(id: "uah", name: "UAH", opening: 100_000)
        let b = Account(id: "usd", name: "USD", opening: 1_000, currency: "USD")
        let transfer = Operation(id: "transfer", kind: .transfer, amount: 42_000, date: day, account: a.id, destination: b.id, sourceMinor: 42_000, destinationMinor: 1_000)
        let ledger = FinamiLedgerIndex(operations: [transfer], accounts: [a, b])
        XCTAssertEqual(ledger.balance(a), 58_000)
        XCTAssertEqual(ledger.balance(b), 2_000)
        XCTAssertEqual(ledger.history(a.id), [transfer])
        XCTAssertEqual(ledger.history(b.id), [transfer])
        XCTAssertEqual(transfer.expenseValue, 0)
        XCTAssertEqual(transfer.incomeValue, 0)
    }

    func testReconciliationIgnoresEarlierImportsButIncludesLaterPayments() {
        let account = Account(id: "a", name: "Card", opening: 10_000, reconciliationDate: day, reconciliationNet: 8_000)
        let earlier = Operation(kind: .expense, amount: 5_000, date: day.addingTimeInterval(-1), account: account.id)
        let later = Operation(kind: .expense, amount: 500, date: day.addingTimeInterval(1), account: account.id)
        let ledger = FinamiLedgerIndex(operations: [earlier, later], accounts: [account])
        XCTAssertEqual(ledger.balance(account), 7_500)
        XCTAssertEqual(ledger.balanceAt(account, date: day), 8_000)
        XCTAssertEqual(ledger.balanceAt(account, date: day.addingTimeInterval(2)), 7_500)
    }

    func testReceiptClassificationDoesNotChangeNativeBalance() {
        var receipt = Operation(kind: .receipt, amount: 2_000, receiptTreatment: .neutral)
        XCTAssertEqual(receipt.incomeValue, 0)
        XCTAssertEqual(receipt.signedNative, 2_000)
        receipt.receiptTreatment = .income
        XCTAssertEqual(receipt.incomeValue, 2_000)
        XCTAssertEqual(receipt.signedNative, 2_000)
        receipt.receiptTreatment = .pending
        XCTAssertTrue(receipt.requiresReview)
        XCTAssertEqual(receipt.incomeValue, 0)
    }

    func testReimbursementReducesExpensesWithoutCountingAsIncome() {
        let receipt = Operation(kind: .receipt, amount: 500, refundOriginalID: "original", receiptTreatment: .reimbursement, receiptExpenseCategory: "Food")
        XCTAssertTrue(receipt.isReimbursement)
        XCTAssertEqual(receipt.expenseValue, -500)
        XCTAssertEqual(receipt.expenseGroup, "Food")
        XCTAssertEqual(receipt.incomeValue, 0)
    }

    func testAccountActivityUsesNativeCurrencyAndExcludesTransfers() {
        let account = Account(id: "a", name: "USD", currency: "USD")
        let expense = Operation(kind: .expense, amount: 4_200, date: day, account: account.id, sourceMinor: 100)
        let transfer = Operation(kind: .transfer, amount: 4_200, date: day, account: "other", destination: account.id, destinationMinor: 100)
        let income = Operation(kind: .income, amount: 8_400, date: day, account: account.id, sourceMinor: 200)
        let activity = AccountActivity(account: account, operations: [expense, transfer, income], month: day)
        XCTAssertEqual(activity.count, 3)
        XCTAssertEqual(activity.income, 200)
        XCTAssertEqual(activity.spending, 100)
        XCTAssertEqual(activity.signed(transfer), 100)
    }

    func testPinnedAccountsPreserveExplicitOrder() {
        let a = Account(id: "a", name: "A")
        let b = Account(id: "b", name: "B", cardOptions: .init(pinned: true, order: 2))
        let c = Account(id: "c", name: "C", cardOptions: .init(pinned: true, order: 1))
        XCTAssertEqual(finamiOrderedAccounts([a, b, c]).map(\.id), ["c", "b", "a"])
    }

    func testGroupedTransferUsesLegDatesAcrossReconciliationAnchor() {
        let source = Account(id: "usd", name: "USD", opening: 10_000, currency: "USD")
        var target = Account(id: "uah", name: "UAH", opening: 1_000)
        let legs: [FinamiBankPart] = [
            .init(key: "a", date: day, amount: 20_000, note: "first"),
            .init(key: "b", date: day.addingTimeInterval(60), amount: 22_000, note: "second")
        ]
        let transfer = Operation(kind: .transfer, amount: 42_000, date: day, account: source.id, destination: target.id,
                                 groupedBankParts: legs, sourceMinor: 1_000, destinationMinor: 42_000)
        let raw = FinamiLedgerIndex(operations: [transfer], accounts: [source, target])
        XCTAssertTrue(finamiValidGroupedBankParts(transfer))
        XCTAssertEqual(raw.balance(target), 43_000)
        XCTAssertEqual(raw.balanceAt(target, date: day), 21_000)
        XCTAssertEqual(raw.balanceAt(target, date: day.addingTimeInterval(60)), raw.balance(target))
        XCTAssertEqual(raw.balance(source), 9_000)
        target.reconciliationDate = day
        target.reconciliationNet = 21_000
        let anchored = FinamiLedgerIndex(operations: [transfer], accounts: [source, target])
        XCTAssertEqual(anchored.balance(target), 43_000)
        XCTAssertEqual(anchored.balanceAt(target, date: day.addingTimeInterval(-1)), 1_000)
        XCTAssertEqual(anchored.balanceAt(target, date: day), 21_000)
        XCTAssertEqual(anchored.balanceAt(target, date: day.addingTimeInterval(60)), anchored.balance(target))
        // A late import at or before the anchor must not inflate today's balance.
        let earlier = Operation(kind: .income, amount: 777, date: day, account: target.id)
        XCTAssertEqual(FinamiLedgerIndex(operations: [earlier, transfer], accounts: [target]).balance(target), 43_000)
        // Fallback for an index constructed before the anchor was selected.
        XCTAssertEqual(raw.balance(target), anchored.balance(target))
    }

    func testMalformedGroupCannotPassSharedInvariant() {
        var transfer = Operation(kind: .transfer, amount: 42_000, date: day, account: "usd", destination: "uah",
                                 groupedBankParts: [.init(key: "a", date: day, amount: 41_999, note: "leg")],
                                 sourceMinor: 1_000, destinationMinor: 42_000)
        XCTAssertFalse(finamiValidGroupedBankParts(transfer))
        transfer.groupedBankParts?[0].amount = 42_000
        XCTAssertTrue(finamiValidGroupedBankParts(transfer))
        transfer.destinationBankKey = "a"
        XCTAssertFalse(finamiValidGroupedBankParts(transfer))
    }
}
