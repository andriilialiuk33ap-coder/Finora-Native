import SwiftUI
import Charts

// Read-only presentation of existing report snapshots. Negative net categories
// remain in the original table; part-to-whole charts are only valid for nonnegative data.
struct FinamiDesignCategoryChart: View {
    var values: [String: Int64]
    var style: String
    @State private var selected: String?
    private let colors: [Color] = [.purple,.blue,.teal,.orange,.pink,.indigo,.mint,.cyan]
    private var rows: [Row] { values.filter { $0.value != 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.enumerated().map { Row(id: $0.element.key, value: Double($0.element.value)/100, color: colors[$0.offset % colors.count]) } }
    private struct Row: Identifiable { let id: String; let value: Double; let color: Color }
    var body: some View {
        let data = rows
        let total = data.reduce(0) { $0 + $1.value }
        let validParts = total > 0 && data.allSatisfy { $0.value >= 0 }
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if style == "Donut" && validParts {
                    ZStack {
                        ForEach(Array(data.enumerated()), id: \.element.id) { i, row in
                            let start = data.prefix(i).reduce(0) { $0 + $1.value } / total
                            Circle().trim(from: CGFloat(start), to: CGFloat(start + row.value/total)).stroke(row.color, lineWidth: selected == row.id ? 24 : 18).rotationEffect(.degrees(-90)).opacity(selected == nil || selected == row.id ? 1 : 0.35)
                        }
                        VStack { Text(data.first(where: { $0.id == selected })?.id ?? "Усього").font(.caption).lineLimit(1); Text((data.first(where: { $0.id == selected })?.value ?? total).formatted(.currency(code: "UAH"))).font(.caption.bold()).minimumScaleFactor(0.6) }.padding(28)
                    }.frame(width: 155,height: 155).frame(maxWidth: .infinity)
                } else if style == "Treemap" && validParts {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(data) { row in
                                Rectangle().fill(row.color.opacity(selected == nil || selected == row.id ? 0.85 : 0.3)).frame(width: geo.size.width * CGFloat(row.value/total)).overlay { if row.value/total > 0.17 { Text(row.id).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.6).padding(2) } }.accessibilityLabel(row.id)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 10))
                    }.frame(height: 92)
                } else {
                    Chart(data) { row in
                        BarMark(x: .value("UAH",row.value), y: .value("Категорія",row.id)).foregroundStyle(row.color.opacity(selected == nil || selected == row.id ? 1 : 0.35))
                    }.frame(height: CGFloat(min(440,max(100,data.count*27))))
                    if style != "Horizontal Bars" && !validParts { Text("Є від’ємні чисті витрати: використано стовпчики замість часток.").font(.caption2).foregroundStyle(.secondary) }
                }
                ForEach(data) { row in
                    Button { selected = selected == row.id ? nil : row.id } label: {
                        HStack { Circle().fill(row.color).frame(width: 9,height: 9); Text(row.id).font(.caption); Spacer(); Text(row.value.formatted(.currency(code: "UAH"))).font(.caption.monospacedDigit()); if selected == row.id { Image(systemName: "checkmark") } }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
struct FinamiDesignPeriodChart: View {
    var snapshot: FinamiReportSnapshot
    var style: String
    var showIncome: Bool
    private struct Row: Identifiable { let date: Date; let series: String; let value: Double; var id: String { String(date.timeIntervalSince1970)+series } }
    private var rows: [Row] { snapshot.periods.keys.sorted().flatMap { day -> [Row] in
        let t = snapshot.periods[day] ?? .init()
        let expense = Row(date: day, series: "Витрати", value: Double(t.expense)/100)
        return showIncome && style == "Income vs Expense" ? [Row(date: day, series: "Доходи", value: Double(t.income)/100), expense] : [expense]
    } }
    var body: some View {
        let data = rows
        if data.isEmpty { Text("Немає даних").font(.caption) }
        else if style == "Heatmap" {
            let expenses = data.filter { $0.series == "Витрати" }
            let maxValue = max(1,expenses.map { abs($0.value) }.max() ?? 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()),count: 7)) {
                ForEach(expenses) { row in
                    VStack { Text(row.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption2); Text(row.value.formatted(.number.precision(.fractionLength(0)))).font(.caption2).minimumScaleFactor(0.5) }.frame(maxWidth: .infinity,minHeight: 42).background((row.value < 0 ? Color.blue : Color.orange).opacity(max(0.06,abs(row.value)/maxValue*0.65)), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        } else {
            Chart(data) { row in
                if style == "Area Chart" {
                    AreaMark(x: .value("Дата",row.date), y: .value("UAH",row.value)).foregroundStyle(by: .value("Тип",row.series)).opacity(0.5)
                    LineMark(x: .value("Дата",row.date), y: .value("UAH",row.value)).foregroundStyle(by: .value("Тип",row.series))
                } else {
                    BarMark(x: .value("Дата",row.date), y: .value("UAH",row.value)).foregroundStyle(by: .value("Тип",row.series)).position(by: .value("Тип",row.series))
                }
            }.chartForegroundStyleScale(["Доходи": Color.teal,"Витрати": Color.purple]).frame(height: 170)
        }
    }
}
struct FinamiDesignWaterfall: View {
    var totals: FinamiReportTotals
    private struct Step: Identifiable { let id: String; let start: Double; let end: Double; let color: Color }
    var body: some View {
        let income = Double(totals.income)/100, net = Double(totals.net)/100
        let steps = [Step(id: "Доходи",start:0,end:income,color:.teal), Step(id: "Витрати",start:income,end:net,color:.orange), Step(id: "Потік",start:0,end:net,color:.purple)]
        Chart(steps) { row in
            BarMark(x: .value("Показник",row.id), yStart: .value("Початок",min(row.start,row.end)), yEnd: .value("Кінець",max(row.start,row.end))).foregroundStyle(row.color)
        }.frame(height: 150)
    }
}
