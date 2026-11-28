import Foundation

/// Validate decoded and proposed data before running arithmetic or publishing it.
/// Amounts are minor units. The aggregate envelope reserves headroom for
/// repeated schedule projections, ledger/report sums and intermediate deltas.
enum FinamiDatabaseSafety {
    static let amountLimit: Int64 = 1_000_000_000_000
    static let aggregateLimit = Int64.max / 512
    enum Failure: LocalizedError {
        case structure, amount, aggregate, date, ledger, refundLink
        var errorDescription: String? {
            switch self {
            case .structure: return "Некоректні або повторювані ідентифікатори фінансових записів."
            case .amount: return "Фінансове значення поза підтримуваними межами."
            case .aggregate: return "Загальний обсяг фінансових значень перевищує безпечну межу."
            case .date: return "Некоректна дата фінансового запису."
            case .ledger: return "Некоректний рахунок, валюта, контрольний баланс або склад групового переказу."
            case .refundLink: return "Некоректний зв’язок повернення або компенсації з покупкою."
            }
        }
    }
    struct OperationFailure: LocalizedError {
        let index: Int
        let id: String
        let underlying: Error
        var errorDescription: String? {
            "Операція №\(index + 1) (ID: \(id)): \(underlying.localizedDescription)"
        }
    }
    static func validate(_ db: Database) throws {
        var sum: Int64 = 0
        func add(_ value: Int64, signed: Bool = false) throws {
            guard value >= (signed ? -amountLimit : 0), value <= amountLimit else { throw Failure.amount }
            let magnitude = value < 0 ? -value : value
            guard magnitude <= aggregateLimit - sum else { throw Failure.aggregate }
            sum += magnitude
        }
        func date(_ value: Date) throws {
            guard value.timeIntervalSinceReferenceDate.isFinite else { throw Failure.date }
        }
        func unique(_ ids: [String]) throws {
            guard !ids.contains(where: \.isEmpty), Set(ids).count == ids.count else { throw Failure.structure }
        }
        guard !db.accounts.isEmpty else { throw Failure.structure }
        try unique(db.accounts.map(\.id))
        try unique(db.operations.map(\.id))
        try unique(db.obligations.map(\.id) + (db.removedInstallments ?? []).map(\.id) + (db.subscriptions ?? []).map(\.id))
        let accountCodes = Dictionary(uniqueKeysWithValues: db.accounts.map { ($0.id, $0.code) })
        for a in db.accounts {
            guard ["UAH", "USD"].contains(a.code),
                  (a.reconciliationDate == nil) == (a.reconciliationNet == nil) else { throw Failure.ledger }
            try add(a.opening, signed: true); try add(a.creditLimit ?? 0)
            try add(a.reconciliationNet ?? 0, signed: true)
            if let d = a.reconciliationDate { try date(d) }
        }
        if accountCodes.values.contains("USD"), fxRate(db.currencyPreferences?.usdRate ?? "") == nil { throw Failure.ledger }
        for (index, o) in db.operations.enumerated() {
            do {
                guard let sourceCode = accountCodes[o.account],
                      sourceCode != "USD" || (o.sourceMinor != nil && fxRate(o.exchangeRate ?? "") != nil),
                      finamiValidGroupedBankParts(o) else { throw Failure.ledger }
                if o.kind == .transfer {
                    guard o.account != o.destination, let destinationCode = accountCodes[o.destination],
                          destinationCode != "USD" || o.destinationMinor != nil else { throw Failure.ledger }
                    if o.groupedBankParts != nil {
                        guard sourceCode == "USD", destinationCode == "UAH", o.sourceMinor != nil, o.destinationMinor == o.amount else { throw Failure.ledger }
                    }
                }
                guard o.amount > 0, (o.sourceMinor ?? o.amount) > 0, (o.destinationMinor ?? o.amount) > 0 else { throw Failure.amount }
                try add(o.amount); try add(o.sourceMinor ?? 0); try add(o.destinationMinor ?? 0)
                try add(o.bankFee ?? 0, signed: true); try add(o.originalAmount ?? 0, signed: true)
                try date(o.date)
                for p in o.groupedBankParts ?? [] { try add(p.amount); try date(p.date); try add(p.originalAmount ?? 0, signed: true) }
            } catch { throw OperationFailure(index: index, id: o.id, underlying: error) }
        }
        // Validate links only after all ledger amounts are bounded, before any sign arithmetic.
        var linkedRows = db.operations
        guard finamiSynchronizeRefundLinks(&linkedRows, accountCodes: accountCodes, validateOnly: true) else { throw Failure.refundLink }
        for o in db.obligations + (db.removedInstallments ?? []) {
            try add(o.target); try add(o.paid); try add(o.monthly); try add(o.currentDuePaid ?? 0); try date(o.due)
            guard o.paid <= o.target, (o.currentDuePaid ?? 0) <= o.paid else { throw Failure.amount }
            if let p = o.currentDuePaid { guard p == 0 || p < o.monthly else { throw Failure.amount } }
            if let facts = o.bankContractSnapshot {
                try date(facts.capturedAt)
                for value in [facts.firstContribution, facts.totalBankFee, facts.monthlyBankFee, facts.nextAmount].compactMap({ $0 }) { try add(value) }
                for d in [facts.bankNextDue, facts.opened, facts.finalDue].compactMap({ $0 }) { try date(d) }
                if let count = facts.paymentCount { guard (1...600).contains(count) else { throw Failure.structure } }
                if let paid = facts.paidCount { guard (0...600).contains(paid), paid <= (facts.paymentCount ?? 600) else { throw Failure.structure } }
            }
            for r in o.importedSchedule ?? [] { try add(r.amount); try date(r.date) }
            guard o.confirmedScheduleValid else { throw Failure.structure }
            for r in o.confirmedSchedule ?? [] { try add(r.amount); try date(r.date) }
        }
        for r in db.subscriptions ?? [] {
            try add(r.amount); try date(r.next)
            for p in r.payments { try add(p.amount); try date(p.date); try date(p.through) }
        }
        for r in db.paidRecords ?? [] {
            try add(r.amount); try date(r.scheduledDate); try date(r.paidDate)
            if let u = r.obligationUndo {
                try add(u.beforePaid); try add(u.afterPaid); try add(u.beforeProgress ?? 0); try add(u.afterProgress ?? 0)
                try add(u.target); try add(u.monthly); try date(u.beforeDue); try date(u.afterDue)
                for rows in [u.beforeSchedule, u.afterSchedule].compactMap({ $0 }) {
                    guard rows.count <= 600 else { throw Failure.structure }
                    for row in rows { try add(row.amount); try date(row.date) }
                }
            }
        }
        for r in db.exchangeDiary ?? [] { try add(r.units); try add(r.fee); try add(r.orderUAH); try add(r.receivedUAH); try date(r.date) }
        for r in db.partnerGroups ?? [] { try add(r.limit); try add(r.prepaid) }
        for r in (db.balanceObservations ?? [:]).values { try add(r.available); try date(r.date) }
        try add(db.budget)
        for v in db.limits.values { try add(v) }
        if let p = db.forecast { try add(p.expected); try add(p.planned); try add(p.reserve); try add(p.daily ?? 0) }
    }
}
