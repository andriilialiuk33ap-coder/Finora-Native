import Charts
import Combine
import UIKit
import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// Keep chart data and chart rendering separate to simplify SwiftUI type checking.
struct CashFlowPoint: Identifiable {
  let month: Date
  let series: String
  let amount: Double
  var id: String { "\(month.timeIntervalSinceReferenceDate)-\(series)" }
}
struct AnnualCashFlowChart: View {
  let points: [CashFlowPoint]
  var body: some View {
    Chart(points) { point in
      BarMark(
        x: .value("Місяць", point.month, unit: .month),
        y: .value("UAH", point.amount)
      )
      .foregroundStyle(by: .value("Тип", point.series))
      .position(by: .value("Тип", point.series))
    }
    .chartForegroundStyleScale(domain: ["Доходи", "Витрати"], range: [finoraAccent, Color.orange])
    .frame(height: 220)
  }
}
