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
            Section("Період") { DatePicker("Від",selection:$start,displayedComponents:.date); DatePicker("До",selection:$end,displayedComponents:.date); if format != .calendar { Picker("Рахунок",selection:$account) { Text("Усі").tag("all"); ForEach(s.db.accounts) { Text($0.name).tag($0.id) } };Picker("Категорія",selection:$category){Text("Усі").tag("all");ForEach(Array(Set(s.db.expenseCategories+s.db.incomeCategories)).sorted(),id:\.self){Text($0).tag($0)}} } }
            Section("Приватність") { Toggle("Показувати суми",isOn:$includeAmounts); Toggle("Назви рахунків і платежів",isOn:$includeNames); if format != .calendar { Toggle("Оригінальні описи операцій",isOn:$includeNotes) }; Text("За замовчуванням суми, назви та банківські описи приховані. Експорт не є зашифрованою резервною копією.").font(.caption) }
            Section("Попередній перегляд") { if format != .calendar { LabeledContent("Операцій",value:String(filtered.count)) }; Text(format == .calendar ? "Заплановані платежі за вибраний період, без автоматичного додавання до календаря." : "Операції та підсумки вибраного періоду. Залишки рахунків і зобов’язань — поточні, якщо обрано всі рахунки.").font(.caption); Button("Створити файл") { make() }.disabled(busy || start > end); if busy { ProgressView() }; if !status.isEmpty { Text(status).font(.caption) } }
        }.disabled(busy).navigationTitle("Експорт звітів").fileExporter(isPresented:$exporting,document:document,contentType:format.type,defaultFilename:"Finami-report.\(format.ext)") { result in if case .failure(let error)=result {status=error.localizedDescription}; document=nil }
    }
    private func make() {
        let rows=filtered, db=s.db, names=includeNames, amounts=includeAmounts, notes=includeNotes, selected=account
        let text: (String)->FinamiExportCell = { FinamiExportCell($0) }
        let moneyCell: (Int64)->FinamiExportCell = { amounts ? FinamiExportCell(minor:$0) : FinamiExportCell("—") }
        let accounts=Dictionary(db.accounts.enumerated().map { ($0.element.id,names ? $0.element.name : "Рахунок \($0.offset+1)") },uniquingKeysWith:{a,_ in a})
        let date=ISO8601DateFormatter(); var totals=FinamiReportTotals()
        for o in rows { totals.add(o,account:selected == "all" ? nil : selected) }
        var sheets=[FinamiExportSheet(name:"Підсумок",rows:[[text("Показник"),text("UAH")],[text("Доходи"),moneyCell(totals.income)],[text("Надходження"),moneyCell(totals.incoming)],[text("Чисті витрати"),moneyCell(totals.expense)],[text("Чистий потік"),moneyCell(totals.net)]])]
        let header=["Дата","Тип","Сума UAH","Категорія","Рахунок","Куди","Опис","Комісія UAH","Оригінальна сума","Оригінальна валюта","Курс"].map(text)
        let dataRows=rows.map { o in [text(date.string(from:o.date)),text(o.kind.title),moneyCell(o.amount),text(o.category),text(accounts[o.account] ?? "—"),text(accounts[o.destination] ?? ""),text(notes ? o.note : ""),moneyCell(o.bankFee ?? 0),moneyCell(o.originalAmount ?? o.amount),text(o.originalCurrency ?? "UAH"),text(amounts ? (o.exchangeRate ?? "") : "")] }
        sheets.append(.init(name:"Операції",rows:[header]+dataRows))
        let expenses=Dictionary(grouping:rows.filter{$0.kind == .expense},by:\.category).map { key,ops in [text(key),moneyCell(ops.reduce(0){$0+$1.amount})] }.sorted{$0[0].text<$1[0].text}
        sheets.append(.init(name:"Категорії",rows:[[text("Категорія"),text("Витрати UAH (брутто)")]]+expenses))
        sheets.append(.init(name:"Доходи",rows:[header]+zip(rows,dataRows).filter{$0.0.kind == .income}.map{$0.1}))
        sheets.append(.init(name:"Витрати",rows:[header]+zip(rows,dataRows).filter{$0.0.kind == .expense || $0.0.kind == .refund}.map{$0.1}))
        let month=DateFormatter();month.locale=Locale(identifier:"uk_UA");month.dateFormat="yyyy-MM"
        let monthly=Dictionary(grouping:rows){month.string(from:$0.date)}.map { pair -> [FinamiExportCell] in var total=FinamiReportTotals();for o in pair.value {total.add(o,account:selected == "all" ? nil:selected)};return [text(pair.key),moneyCell(total.income),moneyCell(total.incoming),moneyCell(total.expense),moneyCell(total.net)] }.sorted{$0[0].text<$1[0].text}
        sheets.append(.init(name:"Місяці",rows:[[text("Місяць"),text("Доходи UAH"),text("Надходження UAH"),text("Витрати UAH"),text("Чистий потік UAH")]]+monthly))
        if selected == "all" && category == "all" {
            sheets.append(.init(name:"Рахунки зараз",rows:[[text("Рахунок"),text("Валюта"),text("Баланс")]]+db.accounts.map{[text(accounts[$0.id] ?? "—"),text($0.code),moneyCell(s.nativeBalance($0))]}))
            sheets.append(.init(name:"Зобов’язання зараз",rows:[[text("Назва"),text("Тип"),text("Залишок UAH")]]+db.obligations.filter{[.installment,.owe,.recurring].contains($0.kind)}.map{[text(names ? $0.name : $0.kind.title),text($0.kind.title),moneyCell($0.remaining)]}))
            sheets.append(.init(name:"Підписки зараз",rows:[[text("Назва"),text("Валюта"),text("Сума")]]+(db.subscriptions ?? []).filter(\.active).map{[text(names ? $0.name : "Підписка"),text($0.currency),moneyCell($0.amount)]}))
        }
        let chosen=format
        if chosen == .pdf {document=DataFile(data:finamiPDF(sheets));exporting=true;return}
        if chosen == .csv {let content=([header]+dataRows).map{$0.map{ $0.numeric ? $0.text : finamiCSVText($0.text) }.joined(separator:";")}.joined(separator:"\r\n");document=DataFile(data:Data(("\u{FEFF}"+content).utf8));exporting=true;return}
        if chosen == .calendar {
            let cal=Calendar.current, interval=DateInterval(start:cal.startOfDay(for:start),end:cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:end)) ?? end)
            let events=s.upcomingPayments.flatMap { p -> [FinamiCalendarExportEvent] in let period=db.subscriptions?.first{$0.id==p.id}?.period; return finamiPlannedOccurrences(id:p.id,start:p.date,amount:p.amount,remaining:p.remaining,subsequentAmount:p.recurringAmount,component:period?.component ?? .month,step:period?.step ?? 1,interval:interval).map{.init(id:$0.id,date:$0.date,title:names ? p.name : p.kind,detail:amounts ? NSDecimalNumber(decimal:Decimal($0.amount)/100).stringValue+" "+p.currency : "Finami · плановий платіж")} }
            document=DataFile(data:finamiCalendarData(events));exporting=true;return
        }
        busy=true; let prepared=sheets
        Task { @MainActor in defer {busy=false}; do {let data=try await Task.detached(priority:.userInitiated){try finamiZipWorkbook(prepared)}.value;document=DataFile(data:data);exporting=true} catch {status=error.localizedDescription} }
    }
}
