import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation
import Vision
import PhotosUI
import Security

// The PDF templates are coordinate-based, so date/posting date and account/operation amounts never get mixed up.
private enum StatementPDF {
    static func read(_ url: URL) throws -> BankBatch {
        guard let doc = PDFDocument(url: url), !doc.isLocked, doc.pageCount <= 500, let first = doc.page(at: 0)?.string else { throw BankFailure.format }
        let pumb = first.localizedCaseInsensitiveContains("ПУМБ") && first.localizedCaseInsensitiveContains("Інформація про рух коштів")
        let abank = first.localizedCaseInsensitiveContains("АКЦЕНТ-БАНК") && first.localizedCaseInsensitiveContains("Виписка по картці")
        guard pumb || abank else { throw BankFailure.unsupported }
        let cols: [(CGFloat,CGFloat)] = pumb ? [(27,79),(80,149),(202,259),(260,317),(318,391),(392,520),(521,582)] : [(35,103),(104,184),(185,369),(370,405),(406,476),(477,548),(549,595),(596,637),(638,696)]
        let width: CGFloat = pumb ? 595.304 : 841.889
        let pattern = pumb ? #"^\d{4}-\d{2}-\d{2}$"# : #"^\d{2}\.\d{2}\.\d{4}$"#
        var result = BankBatch()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at:i) else { continue }
            let bounds = page.bounds(for:.mediaBox), scale = bounds.width / width
            guard page.rotation == 0, abs(scale - 1) < 0.15 else { throw BankFailure.unsupported }
            func column(_ c: (CGFloat,CGFloat), _ top: CGFloat, _ bottom: CGFloat) -> String {
                guard top > bottom else { return "" }
                let rect = CGRect(x:bounds.minX+c.0*scale,y:bottom,width:(c.1-c.0)*scale,height:top-bottom)
                return bankClean(page.selection(for:rect)?.string ?? "")
            }
            let col = CGRect(x:bounds.minX+cols[0].0*scale,y:bounds.minY,width:(cols[0].1-cols[0].0)*scale,height:bounds.height)
            guard let selection = page.selection(for:col) else { continue }
            let anchors = selection.selectionsByLine().compactMap { line -> (String,CGRect)? in
                let value = bankClean(line.string ?? "")
                guard value.range(of: pattern,options:.regularExpression) != nil else { return nil }
                let rect = line.bounds(for:page)
                if !pumb && (bounds.maxY - rect.maxY) < (i == 0 ? 400 : 140)*scale { return nil }
                return (value,rect)
            }.sorted { $0.1.midY > $1.1.midY }
            for j in anchors.indices {
                let (date, r) = anchors[j]
                // Date precedes the time by one line. A row's center is just below the date.
                let top = min(bounds.maxY,r.maxY+3*scale)
                let bottom = j+1 < anchors.count ? anchors[j+1].1.maxY+3*scale : max(bounds.minY,r.minY-(pumb ? 22 : 24)*scale)
                var cells = cols.map { column($0,top,bottom) }
                let timePattern = pumb ? #"\b\d{2}:\d{2}:\d{2}\b"# : #"\b\d{2}:\d{2}\b"#
                var time = cells[0].range(of:timePattern,options:.regularExpression).map { String(cells[0][$0]) }
                // PUMB can split the last row across two pages, including its timestamp.
                if time == nil && pumb && j == anchors.count-1 && i+1 < doc.pageCount, let next = doc.page(at:i+1) {
                    let nb = next.bounds(for:.mediaBox)
                    let head = next.selection(for:CGRect(x:nb.minX+27*scale,y:nb.maxY-45*scale,width:52*scale,height:45*scale))?.string ?? ""
                    if let match = head.range(of:timePattern,options:.regularExpression) { time = String(head[match]) }
                }
                cells[0] = date + (time.map { " " + $0 } ?? "")
                if let row = pumb ? pumbRow(cells) : abankRow(cells) { result.rows.append(row) } else { result.rejected += 1 }
            }
        }
        let summary = pumb ? (doc.page(at:doc.pageCount-1)?.string ?? "") : first
        result.reconciliation = bankReconcile(result,debit:bankSummary(summary,label:pumb ? "Всього списань за період" : "Сума витрат за період"),credit:bankSummary(summary,label:pumb ? "Всього зарахувань за період" : "Сума зарахувань за період"))
        guard !result.rows.isEmpty else { throw BankFailure.empty }
        return result
    }
}
private func readOTP(_ url: URL) throws -> BankBatch {
    let archive = try Archive(url:url,accessMode:.read)
    func entry(_ path: String, required: Bool) throws -> Data {
        guard let e = archive[path] else { if required { throw BankFailure.format }; return Data() }
        guard e.uncompressedSize <= 20_000_000 else { throw BankFailure.unsupported }
        var data = Data(); _ = try archive.extract(e) { chunk in data.append(chunk) }; return data
    }
    let shared = BankXML(shared:true); let strings = try entry("xl/sharedStrings.xml",required:false)
    if !strings.isEmpty { try shared.parse(strings) }
    let sheet = BankXML(shared:false,strings:shared.shared)
    try sheet.parse(entry("xl/worksheets/sheet1.xml",required:true))
    return try otpBatch(sheet.rows)
}
private enum MonoKeychain {
    static let base: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"ua.finora.personal.mono",kSecAttrAccount as String:"token"]
    static func get() -> String {
        var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { return "" }; return String(data:data,encoding:.utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(base as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound { var q = base; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly; guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw BankFailure.invalidToken } }
        else if status != errSecSuccess { throw BankFailure.invalidToken }
    }
    static func remove() { SecItemDelete(base as CFDictionary) }
}
private enum MonoAPI {
    static func get<T:Decodable>(_ path:String,token:String,as type:T.Type) async throws -> T {
        guard !token.isEmpty, let url = URL(string:"https://api.monobank.ua"+path) else { throw BankFailure.invalidToken }
        var request = URLRequest(url:url); request.setValue(token,forHTTPHeaderField:"X-Token"); request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data,response) = try await URLSession(configuration:.ephemeral).data(for:request)
        guard let http = response as? HTTPURLResponse else { throw BankFailure.format }
        if http.statusCode == 429 { throw BankFailure.rate }; guard http.statusCode == 200 else { throw BankFailure.network(http.statusCode) }
        return try JSONDecoder().decode(T.self,from:data)
    }
}
struct BankCenter: View {
    @EnvironmentObject var s: Store
    @State private var importing = false; @State private var pending: BankBatch?; @State private var account = ""; @State private var busy = false
    @State private var token = ""; @State private var mono: [MonoAccount] = []; @State private var monoID = ""; @State private var from = Calendar.current.date(byAdding:.day,value:-7,to:Date()) ?? Date(); @State private var lastFetch = Date.distantPast
    private var supportedMonoAccounts: [MonoAccount] {
        mono.filter { $0.currencyCode == 980 }
    }
    private var supportedLocalAccounts: [Account] {
        s.db.accounts.filter { $0.code == "UAH" }
    }
    private var statementDates: ClosedRange<Date> {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        return start...now
    }
    private var importTypes: [UTType] {
        [.pdf, UTType(filenameExtension: "xlsx") ?? .spreadsheet]
    }
    var body: some View {
        List {
            statementSection
            monoSection
            if busy { ProgressView() }
            if let batch = pending {
                reviewSection(batch)
            }
        }
        .navigationTitle("Банки та імпорт")
        .onAppear {
            if token.isEmpty { token = MonoKeychain.get() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, onCompletion: importFile)
    }
    private var statementSection: some View {
        Section("Виписки") {
            Button { importing = true } label: {
                IzanamiLabel(title: "Імпортувати PDF / XLSX", icon: "doc.badge.plus", color: .red)
            }
            .disabled(busy)
            Text("ПУМБ PDF, А-БАНК PDF, ОТП XLSX. Лише гривневі рахунки; оригінальні суми в іншій валюті зберігаються. Приват24 і PDF monobank потребують шаблону.")
                .font(.caption)
            NavigationLink { BankImportHistory() } label: {
                IzanamiLabel(title: "Історія імпорту", icon: "clock.arrow.circlepath", color: .blue)
            }
            NavigationLink { ReceiptScanView() } label: {
                IzanamiLabel(title: "Розпізнати фото чека", icon: "viewfinder", color: .purple)
            }
        }
    }
    private var monoSection: some View {
        Section("monobank · персональний API") {
            Link("Отримати токен", destination: URL(string: "https://api.monobank.ua/")!)
            SecureField("Токен", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Зберегти токен і завантажити рахунки") { loadAccounts() }
                .disabled(busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !mono.isEmpty { monoControls }
            Button("Видалити токен", role: .destructive) {
                MonoKeychain.remove()
                token = ""
                mono = []
                monoID = ""
            }
            .disabled(busy)
            Text("Читання операцій, без права оплати. Запити не частіше разу за 60 секунд. Поки оновлення вручну, без постійного фонового доступу.")
                .font(.caption)
        }
    }
    private func monoAccountTitle(_ a: MonoAccount) -> String {
        let lastFour: String
        if let pan = a.maskedPan?.first {
            lastFour = String(pan.suffix(4))
        } else {
            lastFour = String(a.id.suffix(4))
        }
        let type = a.type ?? "Рахунок"
        return type + " · " + lastFour
    }
    private var monoControls: some View {
        Group {
            Picker("Рахунок банку", selection: $monoID) {
                ForEach(supportedMonoAccounts) { a in
                    Text(monoAccountTitle(a)).tag(a.id)
                }
            }
            DatePicker("Виписка з", selection: $from, in: statementDates, displayedComponents: .date)
            Button("Завантажити операції") { fetchMono() }
                .disabled(busy || monoID.isEmpty)
        }
    }
    private func reviewSection(_ batch: BankBatch) -> some View {
        Section("Перевірка") {
            Text("Розпізнано \(batch.rows.count), пропущено \(batch.rejected)")
            Picker("Рахунок Izanami", selection: $account) {
                Text("Вибрати").tag("")
                ForEach(supportedLocalAccounts) { a in
                    Text(a.name).tag(a.id)
                }
            }
            NavigationLink("Переглянути та імпортувати") {
                BankReview(batch: batch, account: account)
            }
            .disabled(account.isEmpty)
        }
    }
    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= 30_000_000 else { throw BankFailure.unsupported }
            let batch: BankBatch
            if url.pathExtension.lowercased() == "pdf" {
                batch = try StatementPDF.read(url)
            } else {
                batch = try readOTP(url)
            }
            guard !batch.rows.isEmpty else { throw BankFailure.empty }
            pending = batch
            account = ""
        } catch {
            s.error = error.localizedDescription
        }
    }
    func loadAccounts() {
        let value=token.trimmingCharacters(in:.whitespacesAndNewlines);busy=true
        Task { defer { busy=false }; do { try MonoKeychain.save(value); let response=try await MonoAPI.get("/personal/client-info",token:value,as:MonoClient.self);mono=response.accounts;monoID=mono.first(where:{$0.currencyCode == 980})?.id ?? ""; if monoID.isEmpty {s.error="Немає підтримуваного гривневого рахунку"} } catch {s.error=error.localizedDescription} }
    }
    func fetchMono() {
        guard Date().timeIntervalSince(lastFetch) >= 60 else {s.error=BankFailure.rate.localizedDescription;return}; guard let a=mono.first(where:{$0.id == monoID && $0.currencyCode == 980}), !a.id.isEmpty, a.id.range(of:#"^[A-Za-z0-9_=-]+$"#,options:.regularExpression) != nil else {return}
        let start=Int64(Calendar.current.startOfDay(for:from).timeIntervalSince1970),end=Int64(Date().timeIntervalSince1970); guard end>start,end-start<=2_682_000 else {s.error="Обери період до 31 дня";return}; let key=MonoKeychain.get();lastFetch=Date();busy=true
        Task { defer{busy=false}; do {let items=try await MonoAPI.get("/personal/statement/\(a.id)/\(start)/\(end)",token:key,as:[MonoItem].self);pending=monoRows(items,account:a.id);account=""} catch{s.error=error.localizedDescription} }
    }
}
struct BankReview: View {
    @EnvironmentObject var s: Store; @Environment(\.dismiss) var dismiss
    let batch: BankBatch; let account: String
    @State private var excluded: Set<String> = []; @State private var confirm = false
    var rows: [BankRow] { bankNewRows(batch.rows,existing:s.db.operations.filter{$0.account == account}.compactMap(\.bankKey)) }
    var selected: [BankRow] {rows.filter{!excluded.contains($0.id)}}
    var body: some View {
        List {
            Section { LabeledContent("Нові",value:String(rows.count));LabeledContent("Повторний імпорт",value:String(batch.rows.count-rows.count));LabeledContent("Не розпізнано / не проведено",value:String(batch.rejected)); LabeledContent("Вибрано",value:String(selected.count)); if let message=batch.reconciliation {Text(message).font(.caption).foregroundStyle(message.hasPrefix("Суми") ? Color.green : Color.orange)}; Text("Перекази та комісії перевір вручну. Підозрілі операції можна зняти з вибору. Схожі платежі з різних джерел поки не зіставляються.").font(.caption) }
            ForEach(rows) { r in
                Toggle(isOn:Binding(get:{!excluded.contains(r.id)},set:{if $0{excluded.remove(r.id)}else{excluded.insert(r.id)}})) { VStack(alignment:.leading){Text(r.note.isEmpty ? "Без опису":r.note);Text(money(r.signed)).bold();Text(r.date.formatted(date:.abbreviated,time:.shortened)).font(.caption);Text(category(r)).font(.caption);if let w=r.warning{Text(w).font(.caption).foregroundStyle(.orange)}; if r.fee>0{Text("Комісія: "+money(r.fee)).font(.caption)} } }
            }
        }.navigationTitle("Перевірити імпорт").toolbar{Button("Імпортувати \(selected.count)"){confirm=true}.disabled(selected.isEmpty)}.confirmationDialog("Зберегти вибрані операції?",isPresented:$confirm){Button("Зберегти") { save() }}
    }
    func category(_ r:BankRow)->String { let kind:Kind=r.signed>0 ? .income:.expense;let byName=suggestedCategory(r.note,kind:kind,database:s.db);if byName != "Без категорії" {return byName};if let c=mccCategory(r.mcc,incoming:r.signed>0),s.db.expenseCategories.contains(c){return c};return "Без категорії" }
    func save(){guard s.db.accounts.contains(where:{$0.id == account && $0.code == "UAH"}) else{return};let rows=selected;let batchID=UUID().uuidString;let incoming=rows.map{r -> Operation in var o=Operation(kind:r.signed>0 ? .income:.expense,amount:abs(r.signed),date:r.date,category:category(r),note:r.note,account:account);o.importBatch=batchID;o.bankKey=r.key;o.sourceBank=r.source;o.originalAmount=r.original;o.originalCurrency=r.currency;o.bankFee=r.fee;return o};if s.change({d in d.operations.append(contentsOf:incoming)}){s.error="Імпортовано: \(incoming.count)";dismiss()} }
}
struct ReceiptScanView: View {
    @EnvironmentObject var s:Store
    @State private var item:PhotosPickerItem?;@State private var recognized="";@State private var amount="";@State private var merchant="";@State private var busy=false;@State private var edit:Operation?
    var body: some View {
        Form {
            PhotosPicker(selection:$item,matching:.images){Label("Обрати фото або скриншот",systemImage:"photo.on.rectangle")}
            if busy {ProgressView()};TextField("Магазин",text:$merchant);TextField("Сума, грн",text:$amount).keyboardType(.decimalPad)
            if !recognized.isEmpty {Section("Розпізнаний текст"){Text(recognized).font(.caption).textSelection(.enabled)}}
            Button("Перевірити та створити витрату"){guard let n=cents(amount),n>0 else{return};edit=Operation(kind:.expense,amount:n,category:suggestedCategory(merchant,kind:.expense,database:s.db),note:merchant,account:s.db.accounts.first(where:{$0.code == "UAH"})?.id ?? cash)}.disabled((cents(amount) ?? 0)<=0)
            Text("Розпізнавання Vision на пристрої. Перевір суму та дату перед збереженням. Якщо платіж уже є у виписці, не створюй другий.").font(.caption)
        }.navigationTitle("Сканер чеків").sheet(item:$edit){OpEditor(original:$0)}.onChange(of:item){new in guard let new else{return};busy=true;Task{defer{busy=false};do{guard let data=try await new.loadTransferable(type:Data.self),data.count<=25_000_000 else{throw BankFailure.format};let lines=try await Task.detached(priority:.userInitiated){() throws -> [String] in let req=VNRecognizeTextRequest();req.recognitionLevel = .accurate;let available=try req.supportedRecognitionLanguages();req.recognitionLanguages=["uk-UA","en-US","ru-RU"].filter{available.contains($0)};try VNImageRequestHandler(data:data,options:[:]).perform([req]);return (req.results ?? []).compactMap{$0.topCandidates(1).first?.string}}.value;recognized=lines.joined(separator:"\n");merchant=lines.first ?? "";amount="";for line in lines where ["сума","разом","total","всього","усього","до сплати"].contains(where:{line.lowercased().contains($0)}) {if let match=line.range(of:#"\d+[,.]\d{2}(?!\d)"#,options:.regularExpression){amount=String(line[match])}}}catch{s.error=error.localizedDescription}} }
    }
}

struct BankImportHistory: View {
    @EnvironmentObject var s:Store
    @State private var pending:String?;@State private var confirm=false
    struct BatchGroup:Identifiable {let id:String;let operations:[Operation]}
    var batches:[BatchGroup] { Dictionary(grouping:s.db.operations.filter{$0.importBatch != nil},by:{$0.importBatch ?? ""}).map{BatchGroup(id:$0.key,operations:$0.value)}.sorted{($0.operations.map(\.date).max() ?? .distantPast)>($1.operations.map(\.date).max() ?? .distantPast)} }
    var body:some View {
        List {
            if batches.isEmpty {Text("Немає імпортованих пакетів")}
            ForEach(batches) { batch in
                let group=batch.operations
                if let first=group.first,let id=first.importBatch {
                    VStack(alignment:.leading,spacing:8){Text(first.sourceBank ?? "Виписка").font(.headline);Text("\(group.count) операцій · \(s.accountName(first.account))").font(.caption);if let d=group.map(\.date).max(){Text("Остання операція: \(d.formatted(date:.abbreviated,time:.omitted))").font(.caption)};Button("Скасувати імпорт",role:.destructive){pending=id;confirm=true}}
                }
            }
        }.navigationTitle("Історія імпорту").confirmationDialog("Видалити всі операції пакета, включно з відредагованими?",isPresented:$confirm){Button("Видалити пакет",role:.destructive){if let id=pending{s.change{$0.operations.removeAll{$0.importBatch==id}}};pending=nil};Button("Скасувати",role:.cancel){pending=nil}}
    }
}
