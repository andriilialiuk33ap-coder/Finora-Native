import Foundation
// Amounts are stored as minor units. Exchange rates are UAH per USD.
func fxRate(_ text: String) -> Decimal? {
    let value = text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".")
    guard value.range(of:#"^\d+(\.\d{1,8})?$"#,options:.regularExpression) != nil, let n=Decimal(string:value,locale:Locale(identifier:"en_US_POSIX")), n>=Decimal(string:"0.0001")!, n<=100_000 else {return nil};return n
}
func fxMinor(_ minor:Int64,rate:Decimal,divide:Bool=false)->Int64? {
    guard rate>0 else{return nil}; var result=divide ? Decimal(minor)/rate : Decimal(minor)*rate;var rounded=Decimal();NSDecimalRound(&rounded,&result,0,.plain);guard abs(rounded)<=1_000_000_000_000 else{return nil};return NSDecimalNumber(decimal:rounded).int64Value
}
func fxString(_ rate:Decimal)->String {NSDecimalNumber(decimal:rate).stringValue}
struct CurrencyPreferences: Codable { var usdRate: String = ""; var display: String = "dual" }

// The net card balance never includes unused credit. All values are native minor units.
struct CardPosition {
    let net: Int64
    let limit: Int64
    var own: Int64 { max(0, net) }
    var used: Int64 { max(0, -net) }
    var unused: Int64 { max(0, limit - used) }
    var available: Int64 { max(0, net + limit) }
    static func netFrom(own: Int64, used: Int64) -> Int64? {
        guard own >= 0, used >= 0, own <= 1_000_000_000_000, used <= 1_000_000_000_000, own == 0 || used == 0 else { return nil }
        return own - used
    }
}
