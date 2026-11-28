import Foundation

struct FinamiExchangeRecord: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var kind = "income"
  var date = Date()
  var units: Int64 = 0
  var fee: Int64 = 0
  var feeIncluded = true
  var orderUAH: Int64 = 0
  var receivedUAH: Int64 = 0
  var rate = ""
  var note = ""
  var linkedReceiptIDs: [String]? = nil
}
struct FinamiPartnerGroup: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var name = ""
  var limit: Int64 = 0
  var prepaid: Int64 = 0
  var obligationIDs: [String] = []
}
