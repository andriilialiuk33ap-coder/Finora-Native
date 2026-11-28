import Foundation

// 5.5: review suggestions never mutate the ledger. Same-minute purchases can be legitimate.
struct FinamiReviewPair: Identifiable, Equatable {
    let first: String, second: String
    var id: String { first + "|" + second }
}
func finamiReviewPairs(_ operations:[Operation], limit:Int = 100) -> [FinamiReviewPair] {
    guard limit > 0 else { return [] }
    struct Key: Hashable { let account:String; let kind:Kind; let amount:Int64; let merchant:String }
    var last:[Key:Operation] = [:], output:[FinamiReviewPair] = []
    for o in operations.sorted(by:{$0.date == $1.date ? $0.id < $1.id : $0.date < $1.date}) {
        guard o.kind != .transfer, o.amount > 0, o.groupedBankParts == nil else { continue }
        let merchant=finamiMerchantKey(o.note)
        guard !merchant.isEmpty else {continue}
        let k=Key(account:o.account,kind:o.kind,amount:o.sourceMinor ?? o.amount,merchant:merchant)
        if let previous=last[k], o.date.timeIntervalSince(previous.date) <= 120,
           o.id != previous.id { output.append(.init(first:previous.id,second:o.id)) }
        last[k]=o
        if output.count >= limit {break}
    }
    return output
}
struct FinamiPriceChange: Identifiable, Equatable {
    let id:String, previousID:String, currentID:String, merchant:String, account:String, currency:String
    let previous:Int64, current:Int64
}
// Detect large price jumps too, but require three monthly charges with a stable baseline.
func finamiPriceChanges(_ operations:[Operation], calendar:Calendar = .current) -> [FinamiPriceChange] {
    struct Key: Hashable { let merchant:String, account:String, currency:String }
    let filtered=operations.filter { $0.kind == .expense && $0.amount>0 && $0.category.localizedCaseInsensitiveContains("Підписки") }
    let groups=Dictionary(grouping:filtered) { o in Key(merchant:finamiMerchantKey(o.note),account:o.account,currency:o.originalCurrency ?? "UAH") }
    return groups.compactMap { key,rows -> FinamiPriceChange? in
        let recent=Array(rows.sorted{$0.date<$1.date}.suffix(3))
        guard recent.count==3, !key.merchant.isEmpty, key.currency=="UAH" || recent.allSatisfy({$0.originalAmount != nil}) else{return nil}
        let days=zip(recent,recent.dropFirst()).map{calendar.dateComponents([.day],from:calendar.startOfDay(for:$0.0.date),to:calendar.startOfDay(for:$0.1.date)).day ?? 0}
        guard days.allSatisfy({(25...35).contains($0)}) else{return nil}
        let a=recent.map{key.currency == "UAH" ? $0.amount : ($0.originalAmount ?? $0.amount)}
        guard a.allSatisfy({$0>0}), abs(Decimal(a[0])-Decimal(a[1])) <= Decimal(a[1])*Decimal(string:"0.05")!, abs(Decimal(a[2])-Decimal(a[1])) >= Decimal(a[1])*Decimal(string:"0.05")!, a[2] != a[1] else{return nil}
        return .init(id:recent[2].id,previousID:recent[1].id,currentID:recent[2].id,merchant:recent[2].note,account:key.account,currency:key.currency,previous:a[1],current:a[2])
    }.sorted{$0.id<$1.id}
}
func finamiCleanTags(_ raw:String)->[String] {
    var seen=Set<String>(), result:[String]=[]
    for part in raw.split(separator:",") {
        let value=String(part.trimmingCharacters(in:.whitespacesAndNewlines).prefix(40))
        if !value.isEmpty, seen.insert(value.lowercased()).inserted {result.append(value)}
        if result.count>=12 {break}
    }
    return result
}

// 5.7: period summaries distinguish real income, expenses and unclassified movements.
struct FinamiMonthInsight: Identifiable, Equatable {
    var id:Date {month}
    let month:Date
    var income:Int64=0, expense:Int64=0, refunds:Int64=0, unclassifiedIn:Int64=0, unclassifiedOut:Int64=0
    var count=0, review=0, uncategorized=0
    var net:Int64 {income-expense}
}
func finamiMonthInsights(_ operations:[Operation], ending:Date, months:Int=12, calendar:Calendar = .current)->[FinamiMonthInsight] {
    guard (1...36).contains(months), let last=calendar.dateInterval(of:.month,for:ending)?.start else{return []}
    let starts=(0..<months).compactMap{calendar.date(byAdding:.month,value:-$0,to:last)}.reversed()
    var result=Dictionary(uniqueKeysWithValues:starts.map{($0,FinamiMonthInsight(month:$0))})
    for o in operations where o.date<=ending {
        guard let start=calendar.dateInterval(of:.month,for:o.date)?.start,var row=result[start] else{continue}
        row.count += 1
        row.income += o.incomeValue
        row.expense += o.expenseValue
        if o.kind == .refund {row.refunds += o.amount}
        if o.kind == .unclassifiedCredit || (o.kind == .receipt && o.requiresReview && !o.countsAsIncome) {row.unclassifiedIn += o.amount}
        if o.kind == .unclassifiedDebit {row.unclassifiedOut += o.amount}
        if o.requiresReview {row.review += 1}
        if o.kind == .expense && ["Без категорії","Інше"].contains(o.category) {row.uncategorized += 1}
        result[start]=row
    }
    return starts.compactMap{result[$0]}
}

// 5.9: exact 8-decimal exchange diary. Separate from the existing 2-decimal bank ledger.
// A journal entry is evidence, not a second income or bank movement.
func finamiTokenUnits(_ input:String)->Int64? {
    let t=input.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".")
    guard t.range(of:#"^[0-9]{1,10}(\.[0-9]{1,8})?$"#,options:.regularExpression) != nil else{return nil}
    let parts=t.split(separator:".",omittingEmptySubsequences:false)
    guard let whole=Int64(parts[0]) else{return nil}
    let fraction=parts.count==2 ? String(parts[1]) : ""
    guard let frac=Int64(fraction+String(repeating:"0",count:8-fraction.count)) else{return nil}
    let (scaled,o1)=whole.multipliedReportingOverflow(by:100_000_000)
    let (value,o2)=scaled.addingReportingOverflow(frac)
    return !o1 && !o2 && value<=1_000_000_000_000_000 ? value:nil
}
func finamiTokenText(_ n:Int64)->String {
    guard n>=0 else{return "—"}
    let whole=n/100_000_000, fraction=n%100_000_000
    let digits=String(fraction)
    var tail=String(repeating:"0",count:8-digits.count)+digits
    while tail.last=="0" {tail.removeLast()}
    return tail.isEmpty ? String(whole):"\(whole),\(tail)"
}
func finamiExchangeDebit(_ record:FinamiExchangeRecord)->Int64? {
    guard record.units>0,record.units<=1_000_000_000_000_000,record.fee>=0,record.fee<=1_000_000_000_000_000,record.receivedUAH>=0,record.receivedUAH<=1_000_000_000_000,record.orderUAH>=0,record.orderUAH<=1_000_000_000_000 else{return nil}
    if record.kind == "income" {return record.fee==0 && record.orderUAH==0 && record.receivedUAH==0 ? 0:nil}
    guard record.kind=="sale",record.receivedUAH>0,fxRate(record.rate) != nil else{return nil}
    if record.feeIncluded {return record.fee<record.units ? record.units:nil}
    let (sum,overflow)=record.units.addingReportingOverflow(record.fee)
    return overflow ? nil:sum
}
func finamiExchangeBalance(_ records:[FinamiExchangeRecord])->Int64? {
    var total:Int64=0, seen=Set<String>(), receipts=Set<String>()
    for row in records.sorted(by:{$0.date == $1.date ? ($0.kind != $1.kind ? $0.kind == "income" : $0.id<$1.id) : $0.date<$1.date}) {
        guard seen.insert(row.id).inserted,let debit=finamiExchangeDebit(row) else{return nil}
        let linked=row.linkedReceiptIDs ?? []
        guard linked.count<=1000, row.kind=="sale" || linked.isEmpty else{return nil}
        for id in linked {guard !id.isEmpty,receipts.insert(id).inserted else{return nil}}
        let (sum,overflow)=total.addingReportingOverflow(row.kind=="income" ? row.units : -debit)
        guard !overflow,sum>=0 else{return nil};total=sum
    }
    return total
}

// Shared-limit calculator: one provider limit, multiple contracts; no double counting.
func finamiPartnerPosition(limit:Int64, balances:[Int64], prepaid:Int64)->(used:Int64,available:Int64,overLimit:Int64)? {
    guard limit>=0,prepaid>=0,balances.allSatisfy({$0>=0}) else{return nil}
    var used:Int64=0
    for balance in balances {let (next,overflow)=used.addingReportingOverflow(balance);guard !overflow else{return nil};used=next}
    // prepaid is a separate payment balance, not a reduction of principal until posted.
    return (used,max(0,limit-used),max(0,used-limit))
}

// Receipt matching is informational, never changes the type, amount or destination of bank rows.
func finamiExchangeReceipt(_ operation:Operation, accounts:[Account], date:Date, calendar:Calendar = .current)->Int64? {
    let days=calendar.dateComponents([.day],from:calendar.startOfDay(for:date),to:calendar.startOfDay(for:operation.date)).day ?? Int.max
    guard (-1...1).contains(days) else{return nil}
    if operation.kind == .transfer, operation.groupedBankParts != nil, accounts.contains(where:{$0.id==operation.destination && $0.code=="UAH"}) {
        return operation.destinationMinor ?? operation.amount
    }
    guard operation.kind.incoming, operation.kind != .refund, operation.sourceBank != nil, accounts.contains(where:{$0.id==operation.account && $0.code=="UAH"}) else{return nil}
    return operation.sourceMinor ?? operation.amount
}
func finamiExchangeReceiptTotal(ids:[String], operations:[Operation], accounts:[Account], date:Date, calendar:Calendar = .current)->Int64? {
    guard Set(ids).count==ids.count else{return nil}
    let lookup=Dictionary(operations.map{($0.id,$0)},uniquingKeysWith:{a,_ in a})
    var total:Int64=0
    for id in ids {
        guard let o=lookup[id],let amount=finamiExchangeReceipt(o,accounts:accounts,date:date,calendar:calendar),amount>0 else{return nil}
        let (next,overflow)=total.addingReportingOverflow(amount);guard !overflow else{return nil};total=next
    }
    return total
}
func finamiValidPartnerGroups(_ groups:[FinamiPartnerGroup])->Bool {
    var ids=Set<String>(), contracts=Set<String>()
    for g in groups {
        guard !g.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,g.limit>0,g.limit<=1_000_000_000_000,g.prepaid>=0,g.prepaid<=1_000_000_000_000,ids.insert(g.id).inserted else{return false}
        for id in g.obligationIDs {guard !id.isEmpty,contracts.insert(id).inserted else{return false}}
    }
    return true
}

struct FinamiHistoricalPosition:Identifiable,Equatable {
    var id:Date {date}
    let date:Date, own:Int64, debt:Int64, omitted:Int
    var net:Int64 {own-debt}
}
func finamiHistoricalPositions(accounts:[Account],operations:[Operation],ending:Date,months:Int,usdRate:Decimal?,calendar:Calendar = .current)->[FinamiHistoricalPosition] {
    guard (1...24).contains(months),let start=calendar.dateInterval(of:.month,for:ending)?.start else{return []}
    let included=accounts.filter{$0.excludedFromTotals != true && $0.hideAmounts != true}
    let index=FinamiLedgerIndex(operations:operations,accounts:included)
    var result:[FinamiHistoricalPosition]=[]
    for offset in (0..<months).reversed() {
        guard let month=calendar.date(byAdding:.month,value:-offset,to:start),let next=calendar.date(byAdding:.month,value:1,to:month) else{return []}
        let date=min(ending,next.addingTimeInterval(-0.001))
        var own:Int64=0,debt:Int64=0,omitted=0
        for a in included {
            let balance=index.balanceAt(a,date:date)
            let value:Int64?
            if a.code=="UAH" {value=balance}
            else if a.code=="USD",let usdRate {value=fxMinor(balance,rate:usdRate)}
            else {value=nil}
            guard let value,value != Int64.min else{omitted += 1;continue}
            let (nextOwn,of1)=own.addingReportingOverflow(max(0,value)),(nextDebt,of2)=debt.addingReportingOverflow(max(0,-value))
            guard !of1,!of2 else{return []};own=nextOwn;debt=nextDebt
        }
        result.append(.init(date:date,own:own,debt:debt,omitted:omitted))
    }
    return result
}
