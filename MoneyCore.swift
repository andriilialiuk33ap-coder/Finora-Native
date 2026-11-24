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
