import Foundation

// Pure report preparation, shared by PDF, CSV and XLSX. Kept outside SwiftUI
// so the same implementation can be compiled and tested on every CI runner.
struct FinamiExportReport {
    let sheets: [FinamiExportSheet]
    let operationRows: [[FinamiExportCell]]

    init(operations: [Operation], account: String?, accountNames: [String: String], includeAmounts: Bool, includeNotes: Bool) {
        func text(_ value: String) -> FinamiExportCell { FinamiExportCell(value) }
        func money(_ value: Int64) -> FinamiExportCell {
            includeAmounts ? FinamiExportCell(minor: value) : FinamiExportCell("—")
        }
        let header = ["Дата", "Тип", "Сума UAH", "Категорія", "Рахунок", "Куди", "Опис", "Комісія UAH", "Оригінальна сума", "Оригінальна валюта", "Курс"].map(text)
        let date = ISO8601DateFormatter()
        let month = DateFormatter()
        month.locale = Locale(identifier: "uk_UA")
        month.dateFormat = "yyyy-MM"
        var total = FinamiReportTotals()
        var monthly: [String: FinamiReportTotals] = [:]
        var categories: [String: Int64] = [:]
        var allRows = [header]
        var incomeRows = [header]
        var expenseRows = [header]
        for o in operations {
            total.add(o, account: account)
            monthly[month.string(from: o.date), default: FinamiReportTotals()].add(o, account: account)
            var row: [FinamiExportCell] = []
            row.append(text(date.string(from: o.date)))
            row.append(text(o.kind == .receipt ? o.displayKindTitle + " · " + (o.receiptTreatment ?? .pending).title : o.displayKindTitle))
            row.append(money(o.amount))
            row.append(text(o.category))
            row.append(text(accountNames[o.account] ?? "—"))
            row.append(text(accountNames[o.destination] ?? ""))
            row.append(text(includeNotes ? o.note : ""))
            row.append(money(o.bankFee ?? 0))
            row.append(money(o.originalAmount ?? o.amount))
            row.append(text(o.originalCurrency ?? "UAH"))
            row.append(text(includeAmounts ? (o.exchangeRate ?? "") : ""))
            allRows.append(row)
            switch o.kind {
            case .income: incomeRows.append(row)
            case .receipt:
                if o.countsAsIncome { incomeRows.append(row) }
                if o.isReimbursement { expenseRows.append(row) }
            case .expense:
                expenseRows.append(row)
                categories[o.category, default: 0] += o.amount
            case .refund: expenseRows.append(row)
            default: break
            }
        }
        let summary: [[FinamiExportCell]] = [
            [text("Показник"), text("UAH")],
            [text("Доходи"), money(total.income)],
            [text("Надходження"), money(total.incoming)],
            [text("Чисті витрати"), money(total.expense)],
            [text("Чистий потік"), money(total.net)]
        ]
        var categoryRows = [[text("Категорія"), text("Витрати UAH (брутто)")]]
        for key in categories.keys.sorted() {
            categoryRows.append([text(key), money(categories[key] ?? 0)])
        }
        var monthRows = [[text("Місяць"), text("Доходи UAH"), text("Надходження UAH"), text("Витрати UAH"), text("Чистий потік UAH")]]
        for key in monthly.keys.sorted() {
            guard let t = monthly[key] else { continue }
            monthRows.append([text(key), money(t.income), money(t.incoming), money(t.expense), money(t.net)])
        }
        operationRows = allRows
        sheets = [
            FinamiExportSheet(name: "Підсумок", rows: summary),
            FinamiExportSheet(name: "Операції", rows: allRows),
            FinamiExportSheet(name: "Категорії", rows: categoryRows),
            FinamiExportSheet(name: "Доходи", rows: incomeRows),
            FinamiExportSheet(name: "Витрати", rows: expenseRows),
            FinamiExportSheet(name: "Місяці", rows: monthRows)
        ]
    }

    var csvData: Data {
        let lines = operationRows.map { row in
            row.map { cell in cell.numeric ? cell.text : finamiCSVText(cell.text) }.joined(separator: ";")
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }
}
