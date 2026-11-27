import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

private enum FinamiReportExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF", xlsx = "Excel (.xlsx)", csv = "CSV", calendar = "Календар (.ics)"
    var id: String { rawValue }
    var ext: String { switch self { case .pdf: return "pdf"; case .xlsx: return "xlsx"; case .csv: return "csv"; case .calendar: return "ics" } }
    var type: UTType { UTType(filenameExtension:ext) ?? .data }
}
private func finamiZipWorkbook(_ sheets: [FinamiExportSheet]) throws -> Data {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true)
    let folder = root.appendingPathComponent("workbook",isDirectory:true), zip = root.appendingPathComponent("Finami.xlsx")
    defer { try? FileManager.default.removeItem(at:root) }
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let parts=finamiWorkbookParts(sheets)
    for (name,data) in parts { let url = folder.appendingPathComponent(name); try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); try data.write(to:url,options:.atomic) }
    let archive = try Archive(url:zip,accessMode:.create)
    for name in parts.keys.sorted() { try archive.addEntry(with:name,relativeTo:folder,compressionMethod:.deflate) }
    return try Data(contentsOf:zip)
}
@MainActor private func finamiPDF(_ sheets: [FinamiExportSheet]) -> Data {
    let bounds = CGRect(x:0,y:0,width:595,height:842)
    return UIGraphicsPDFRenderer(bounds:bounds).pdfData { context in
        var y: CGFloat = 0
        func page(_ title: String) { context.beginPage(); (("Finami · " + title) as NSString).draw(in:CGRect(x:32,y:30,width:531,height:35),withAttributes:[.font:UIFont.boldSystemFont(ofSize:19),.foregroundColor:UIColor.systemTeal]); y = 80 }
        for sheet in sheets {
            page(sheet.name)
            let head = sheet.rows.first ?? []
            for row in sheet.rows.dropFirst() {
                let text = zip(head,row).map { pair in pair.0.text + ": " + pair.1.text }.joined(separator:"   ·   ") as NSString
                let attributes: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:10),.foregroundColor:UIColor.black]
                let h = min(680, max(18,ceil(text.boundingRect(with:CGSize(width:531,height:680),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes,context:nil).height)+8))
                if y+h>805 { page(sheet.name) }
                text.draw(with:CGRect(x:32,y:y,width:531,height:h),options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine],attributes:attributes,context:nil); y += h
            }
        }
    }
}
struct FinamiExportView: View {
    @EnvironmentObject private var s: Store
    @State private var format: FinamiReportExportFormat = .pdf
    @State private var start = Calendar.current.date(byAdding:.month,value:-1,to:Date()) ?? Date()
    @State private var end = Date()
    @State private var account = "all"
    @State private var category = "all"
    @State private var includeNotes = false
    @State private var includeNames = false
    @State private var includeAmounts = false
    @State private var document: DataFile?
    @State private var exporting = false
    @State private var busy = false
    @State private var status = ""
    private var filtered: [Operation] { let cal=Calendar.current; let lower=cal.startOfDay(for:start), upper=cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:end)) ?? end; return s.db.operations.filter { $0.date >= lower && $0.date < upper && (account == "all" || $0.account == account || ($0.kind == .transfer && $0.destination == account)) && (category == "all" || $0.category == category) }.sorted {$0.date < $1.date} }
    var body: some View {
        Form {
            Section("Формат") { Picker("Файл",selection:$format) { ForEach(FinamiReportExportFormat.allCases) { Text($0.rawValue).tag($0) } } }
            Section("Період") { DatePicker("Від",selection:$start,displayedComponents:.date); DatePicker("До",selection:$end,displayedComponents:.date); if format != .calendar { Picker("Рахунок",selection:$account) { Text("Усі").tag("all"); ForEach(s.db.accounts) { Text($0.name).tag($0.id) } };Picker("Категорія",selection:$category){Text("Усі").tag("all");ForEach(Array(Set(s.db.expenseCategories+s.db.incomeCategories+s.db.availableReceiptCategories)).sorted(),id:\.self){Text($0).tag($0)}} } }
            Section("Приватність") { Toggle("Показувати суми",isOn:$includeAmounts); Toggle("Назви рахунків і платежів",isOn:$includeNames); if format != .calendar { Toggle("Оригінальні описи операцій",isOn:$includeNotes) }; Text("За замовчуванням суми, назви та банківські описи приховані. Експорт не є зашифрованою резервною копією.").font(.caption) }
            Section("Попередній перегляд") { if format != .calendar { LabeledContent("Операцій",value:String(filtered.count)) }; Text(format == .calendar ? "Заплановані платежі за вибраний період, без автоматичного додавання до календаря." : "Операції та підсумки вибраного періоду. Залишки рахунків і зобов’язань — поточні, якщо обрано всі рахунки.").font(.caption); Button("Створити файл") { make() }.disabled(busy || start > end); if busy { ProgressView() }; if !status.isEmpty { Text(status).font(.caption) } }
        }.disabled(busy).navigationTitle("Експорт звітів").fileExporter(isPresented:$exporting,document:document,contentType:format.type,defaultFilename:"Finami-report.\(format.ext)") { result in if case .failure(let error)=result {status=error.localizedDescription}; document=nil }
    }
    private func make() {
        let chosen = format
        if chosen == .calendar {
            document = DataFile(data: calendarData())
            exporting = true
            return
        }
        let db = s.db
        var names: [String: String] = [:]
        for (index, item) in db.accounts.enumerated() where names[item.id] == nil {
            names[item.id] = includeNames ? item.name : "Рахунок \(index + 1)"
        }
        let selectedAccount: String? = account == "all" ? nil : account
        let report = FinamiExportReport(operations: filtered, account: selectedAccount, accountNames: names, includeAmounts: includeAmounts, includeNotes: includeNotes)
        if chosen == .csv {
            document = DataFile(data: report.csvData)
            exporting = true
            return
        }
        var sheets = report.sheets
        if account == "all" && category == "all" {
            sheets.append(contentsOf: currentSheets(accountNames: names))
        }
        if chosen == .pdf {
            document = DataFile(data: finamiPDF(sheets))
            exporting = true
            return
        }
        busy = true
        let prepared = sheets
        Task { @MainActor in
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try finamiZipWorkbook(prepared)
                }.value
                document = DataFile(data: data)
                exporting = true
            } catch { status = error.localizedDescription }
        }
    }

    private func currentSheets(accountNames: [String: String]) -> [FinamiExportSheet] {
        func text(_ value: String) -> FinamiExportCell { FinamiExportCell(value) }
        func moneyCell(_ value: Int64) -> FinamiExportCell {
            includeAmounts ? FinamiExportCell(minor: value) : FinamiExportCell("—")
        }
        var accounts = [[text("Рахунок"), text("Валюта"), text("Баланс")]]
        for item in s.db.accounts {
            accounts.append([text(accountNames[item.id] ?? "—"), text(item.code), moneyCell(s.nativeBalance(item))])
        }
        var obligations = [[text("Назва"), text("Тип"), text("Залишок UAH")]]
        for item in s.db.obligations {
            guard item.kind == .installment || item.kind == .owe || item.kind == .recurring else { continue }
            obligations.append([text(includeNames ? item.name : item.kind.title), text(item.kind.title), moneyCell(item.remaining)])
        }
        var subscriptions = [[text("Назва"), text("Валюта"), text("Сума")]]
        for item in s.db.subscriptions ?? [] where item.active {
            subscriptions.append([text(includeNames ? item.name : "Підписка"), text(item.currency), moneyCell(item.amount)])
        }
        return [FinamiExportSheet(name: "Рахунки зараз", rows: accounts),
                FinamiExportSheet(name: "Зобов’язання зараз", rows: obligations),
                FinamiExportSheet(name: "Підписки зараз", rows: subscriptions)]
    }

    private func calendarData() -> Data {
        let cal = Calendar.current
        let lower = cal.startOfDay(for: start)
        let upper = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end
        let interval = DateInterval(start: lower, end: upper)
        var events: [FinamiCalendarExportEvent] = []
        for p in s.upcomingPayments {
            let period = s.db.subscriptions?.first { $0.id == p.id }?.period
            let occurrences = finamiPlannedOccurrences(id: p.id, start: p.date, amount: p.amount, remaining: p.remaining, subsequentAmount: p.recurringAmount, component: period?.component ?? .month, step: period?.step ?? 1, interval: interval)
            for occurrence in occurrences {
                let title = includeNames ? p.name : p.kind
                let value = NSDecimalNumber(decimal: Decimal(occurrence.amount) / 100).stringValue
                let detail = includeAmounts ? value + " " + p.currency : "Finami · плановий платіж"
                events.append(FinamiCalendarExportEvent(id: occurrence.id, date: occurrence.date, title: title, detail: detail))
            }
        }
        return finamiCalendarData(events)
    }
}
